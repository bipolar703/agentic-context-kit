#!/usr/bin/env bash
# Diagnose the local setup. Prints PASS / WARN / FAIL per check.
# Exit 1 if any FAIL. Safe to run repeatedly; changes nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2
fails=0; warns=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
warn() { printf '  \033[33mWARN\033[0m  %s\n' "$1"; warns=$((warns+1)); }
fail() { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fails=$((fails+1)); }

# Read a key from .env without sourcing it (never executes .env content).
env_get() { [[ -f .env ]] && sed -n "s/^$1=//p" .env | tail -n1 | tr -d '\r' || true; }

echo "Docker"
if command -v docker >/dev/null; then
  pass "docker CLI: $(docker --version 2>/dev/null)"
  if docker info >/dev/null 2>&1; then pass "daemon reachable"; else fail "daemon not reachable (is Docker running?)"; fi
  if cv="$(docker compose version --short 2>/dev/null)"; then
    major="${cv%%.*}"; major="${major#v}"
    if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 2 )); then pass "compose v$cv"; else fail "compose v2+ required (found $cv)"; fi
  else
    fail "docker compose plugin missing"
  fi
else
  fail "docker not installed"
fi

echo "Configuration"
if [[ -f .env ]]; then
  pass ".env present"
  if grep -q $'\r' .env; then warn ".env has CRLF line endings; values may include stray \\r"; fi
else
  warn ".env missing (defaults apply). Run: cp .env.example .env"
fi

ws="$(env_get WORKSPACE_DIR)"; ws="${ws:-.}"
if [[ -d "$ws" ]]; then pass "WORKSPACE_DIR exists: $ws"; else fail "WORKSPACE_DIR does not exist: $ws"; fi
[[ "$ws" == "/" || "$ws" == "$HOME" ]] && fail "WORKSPACE_DIR is '/' or \$HOME; mount a single project instead"

mode="$(env_get WORKSPACE_MODE)"; mode="${mode:-ro}"
case "$mode" in
  ro) pass "WORKSPACE_MODE=ro (agent cannot write via MCP)";;
  rw) warn "WORKSPACE_MODE=rw (agent can modify files via MCP)";;
  *)  fail "WORKSPACE_MODE must be ro or rw (got '$mode')";;
esac

if [[ "$(uname -s)" == "Linux" ]]; then
  uid="$(env_get HOST_UID)"; uid="${uid:-1000}"
  if [[ "$uid" == "$(id -u)" ]]; then pass "HOST_UID matches your user ($uid)"
  else warn "HOST_UID=$uid but id -u is $(id -u); bind-mount permissions may fail"; fi
fi

echo "Images"
if command -v docker >/dev/null && docker info >/dev/null 2>&1; then
  for img in "mcp/filesystem:$(env_get MCP_FILESYSTEM_TAG)" "mcp/git:$(env_get MCP_GIT_TAG)"; do
    img="${img%:}"; [[ "$img" == *:* ]] || img="$img:latest"
    if docker image inspect "$img" >/dev/null 2>&1; then pass "$img pulled"
    else warn "$img not pulled yet (first client launch will be slow). Run: docker compose --profile stdio pull"; fi
  done
  if docker compose --profile stdio --profile gateway config -q 2>/dev/null; then pass "compose config valid"; else fail "docker compose config failed"; fi
fi

echo "Gateway (optional)"
tok="$(env_get MCP_GATEWAY_AUTH_TOKEN)"
if [[ -n "$tok" ]]; then
  if (( ${#tok} >= 32 )); then pass "MCP_GATEWAY_AUTH_TOKEN set"
  else warn "MCP_GATEWAY_AUTH_TOKEN shorter than 32 chars"; fi
else
  warn "MCP_GATEWAY_AUTH_TOKEN empty; the gateway will generate one per start (openssl rand -hex 32)"
fi

echo "Rules"
if scripts/sync-rules.sh --check >/dev/null 2>&1; then pass ".cursorrules/.voidrules in sync with AGENTS.md"
else fail "rule bundles stale or AGENTS.md over budget. Run: scripts/sync-rules.sh"; fi
if grep -lI $'\r' scripts/*.sh >/dev/null 2>&1; then fail "CRLF in scripts/*.sh (set git core.autocrlf=false and re-checkout)"; else pass "scripts use LF"; fi

echo
echo "doctor: $fails fail, $warns warn"
(( fails == 0 ))
