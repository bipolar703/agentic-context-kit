#!/usr/bin/env bash
# Start each stdio MCP server exactly the way an editor does
# (docker compose run --rm -T <service>), perform the MCP handshake, and
# assert that tools/list returns at least one tool.
#
# Uses a throwaway fixture repository as the workspace, so it never touches
# your real WORKSPACE_DIR.
#
# Usage: scripts/smoke-test.sh [service ...]   (default: mcp-filesystem mcp-git)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROTOCOL_VERSION="${MCP_SMOKE_PROTOCOL_VERSION:-2025-06-18}"
READ_WAIT="${MCP_SMOKE_WAIT_SECONDS:-8}"
SERVICES=("$@")
[[ ${#SERVICES[@]} -eq 0 ]] && SERVICES=(mcp-filesystem mcp-git)

command -v docker >/dev/null || { echo "docker not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 2; }

fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
git -C "$fixture" init -q
git -C "$fixture" -c user.name=smoke -c user.email=smoke@example.invalid \
  commit -q --allow-empty -m "fixture"
echo "hello from agentic-context-kit" > "$fixture/README.md"
chmod -R a+rX "$fixture"

export WORKSPACE_DIR="$fixture"
export WORKSPACE_MODE=ro
export HOST_UID="${HOST_UID:-$(id -u)}"
export HOST_GID="${HOST_GID:-$(id -g)}"

# Extra per-service probes (id 3+), sent after tools/list.
probes() {
  case "$1" in
    mcp-filesystem)
      # Must succeed: reads inside the mount.
      printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_allowed_directories","arguments":{}}}'
      # Must fail: the mount is read-only.
      printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"write_file","arguments":{"path":"/workspace/pwned.txt","content":"x"}}}'
      ;;
    mcp-git)
      printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"git_status","arguments":{"repo_path":"/workspace"}}}'
      ;;
  esac
}

requests() {
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"$PROTOCOL_VERSION\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ack-smoke\",\"version\":\"1.0.0\"}}}"
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}'
  probes "$1"
  # Keep stdin open long enough for the server to answer before EOF.
  sleep "$READ_WAIT"
}

failed=0
for svc in "${SERVICES[@]}"; do
  echo "==> $svc"
  out="$(requests "$svc" | docker compose -f "$ROOT/docker-compose.yml" run --rm -T "$svc" 2>/dev/null || true)"
  server="$(printf '%s\n' "$out" | jq -rc 'select(.id==1) | .result.serverInfo | "\(.name) \(.version)"' 2>/dev/null | head -n1)"
  tools="$(printf '%s\n' "$out" | jq -r 'select(.id==2) | .result.tools[]?.name' 2>/dev/null || true)"
  if [[ -n "$tools" ]]; then
    count="$(printf '%s\n' "$tools" | wc -l | tr -d ' ')"
    echo "    server: ${server:-unknown}"
    echo "    tools ($count): $(printf '%s' "$tools" | tr '\n' ' ')"
  else
    echo "    FAIL: no tools/list result. Raw output:" >&2
    printf '%s\n' "$out" | head -n 20 >&2
    failed=1
    continue
  fi

  text_of() { printf '%s\n' "$out" | jq -r "select(.id==$1) | (.result.content[]?.text // .error.message // empty)" 2>/dev/null; }
  is_error() { printf '%s\n' "$out" | jq -e "select(.id==$1) | (.error != null or .result.isError == true)" >/dev/null 2>&1; }

  case "$svc" in
    mcp-filesystem)
      if text_of 3 | grep -q "/workspace"; then echo "    PASS: allowed directories = /workspace only"
      else echo "    FAIL: list_allowed_directories did not report /workspace" >&2; failed=1; fi
      if is_error 4 && [[ ! -e "$fixture/pwned.txt" ]]; then echo "    PASS: write rejected on read-only mount"
      else echo "    FAIL: write_file succeeded on a read-only mount" >&2; failed=1; fi
      ;;
    mcp-git)
      if text_of 3 | grep -qi "branch"; then echo "    PASS: git_status works inside the sandbox"
      else echo "    FAIL: git_status failed: $(text_of 3 | head -n 3)" >&2; failed=1; fi
      ;;
  esac
done

exit "$failed"
