#!/usr/bin/env bash
# Generate legacy single-file rule bundles (.cursorrules, .voidrules) from the
# canonical sources: AGENTS.md + .cursor/rules/*.mdc (frontmatter stripped).
#
# Legacy clients cannot scope rules by file type, so they get the full bundle.
# Modern clients (Cursor, Claude Code, Codex) read AGENTS.md and load
# language rules on demand, which is cheaper in tokens.
#
# Usage:
#   scripts/sync-rules.sh           write .cursorrules and .voidrules
#   scripts/sync-rules.sh --check   exit 1 if the generated files are stale
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TARGETS=(.cursorrules .voidrules)
MAX_LINES="${RULES_MAX_LINES:-150}"

build_bundle() {
  printf '%s\n' "# GENERATED FILE. Do not edit."
  printf '%s\n' "# Source: AGENTS.md + .cursor/rules/*.mdc. Regenerate: scripts/sync-rules.sh"
  printf '\n'
  # Drop the on-demand loading table: legacy clients get everything inline.
  awk '
    /^Language and tooling rules are loaded on demand/ { skip=1 }
    skip && /^## / { skip=0 }
    !skip { print }
  ' AGENTS.md
  local f
  for f in .cursor/rules/*.mdc; do
    printf '\n'
    # Strip YAML frontmatter delimited by the first two --- lines.
    awk 'NR==1 && /^---$/ { fm=1; next } fm && /^---$/ { fm=0; next } !fm { print }' "$f" \
      | sed -e 's/^# /## /'
  done
}

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
build_bundle > "$tmp"

lines=$(wc -l < AGENTS.md | tr -d ' ')
if (( lines > MAX_LINES )); then
  echo "error: AGENTS.md has $lines lines (budget: $MAX_LINES). Move detail into .cursor/rules/*.mdc or nested AGENTS.md files." >&2
  exit 1
fi

if [[ "${1:-}" == "--check" ]]; then
  stale=0
  for t in "${TARGETS[@]}"; do
    if ! cmp -s "$tmp" "$t"; then
      echo "stale: $t (run scripts/sync-rules.sh)" >&2
      stale=1
    fi
  done
  exit "$stale"
fi

for t in "${TARGETS[@]}"; do
  cp "$tmp" "$t"
done

chars=$(wc -c < "$tmp" | tr -d ' ')
core_chars=$(wc -c < AGENTS.md | tr -d ' ')
# ~4 characters per token is a rough heuristic for English prose, not a tokenizer.
echo "wrote ${TARGETS[*]}  (bundle ~$((chars / 4)) tokens; AGENTS.md alone ~$((core_chars / 4)) tokens; heuristic chars/4)"
