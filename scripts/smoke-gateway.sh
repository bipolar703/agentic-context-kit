#!/usr/bin/env bash
# Bring up the optional gateway profile, wait for it to become healthy, then
# speak MCP over streamable HTTP with bearer auth and assert tools/list works.
#
# Usage: scripts/smoke-gateway.sh [--keep]   (--keep leaves the stack running)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE=(docker compose -f "$ROOT/docker-compose.yml" --profile gateway)
PORT="${GATEWAY_PORT:-8811}"
URL="http://127.0.0.1:${PORT}/mcp"
PROTOCOL_VERSION="${MCP_SMOKE_PROTOCOL_VERSION:-2025-06-18}"
KEEP=0; [[ "${1:-}" == "--keep" ]] && KEEP=1

command -v curl >/dev/null || { echo "curl not found" >&2; exit 2; }
command -v jq >/dev/null || { echo "jq not found" >&2; exit 2; }

export MCP_GATEWAY_AUTH_TOKEN="${MCP_GATEWAY_AUTH_TOKEN:-$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')}"

cleanup() { [[ $KEEP -eq 1 ]] || "${COMPOSE[@]}" down --remove-orphans >/dev/null 2>&1 || true; }
trap cleanup EXIT

"${COMPOSE[@]}" up -d

echo "waiting for mcp-gateway to become healthy..."
for _ in $(seq 1 60); do
  cid="$("${COMPOSE[@]}" ps -q mcp-gateway)"
  status="$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' "$cid" 2>/dev/null || echo starting)"
  [[ "$status" == "healthy" ]] && break
  sleep 3
done
if [[ "$status" != "healthy" ]]; then
  echo "FAIL: gateway status '$status'" >&2
  "${COMPOSE[@]}" logs --tail 80 mcp-gateway docker-socket-proxy >&2
  exit 1
fi

# Unauthenticated requests must be rejected.
code="$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL" -H 'Content-Type: application/json' -d '{}')"
if [[ "$code" != "401" && "$code" != "403" ]]; then
  echo "FAIL: unauthenticated request returned HTTP $code (expected 401/403)" >&2
  exit 1
fi
echo "    unauthenticated request rejected (HTTP $code)"

hdrs="$(mktemp)"; trap 'rm -f "$hdrs"; cleanup' EXIT
post() { # $1 = JSON body; prints JSON payload(s), handles SSE framing
  local sid_hdr=()
  [[ -n "${SESSION_ID:-}" ]] && sid_hdr=(-H "Mcp-Session-Id: $SESSION_ID")
  curl -sS -D "$hdrs" -X POST "$URL" \
    -H "Authorization: Bearer $MCP_GATEWAY_AUTH_TOKEN" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "MCP-Protocol-Version: $PROTOCOL_VERSION" \
    ${sid_hdr[@]+"${sid_hdr[@]}"} -d "$1" \
  | sed -n 's/^data: //p; /^{/p'
}

init="$(post "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"$PROTOCOL_VERSION\",\"capabilities\":{},\"clientInfo\":{\"name\":\"ack-smoke\",\"version\":\"1.0.0\"}}}")"
SESSION_ID="$(awk 'tolower($1)=="mcp-session-id:" {print $2}' "$hdrs" | tr -d '\r')"
echo "    server: $(printf '%s\n' "$init" | jq -rc 'select(.id==1) | .result.serverInfo | "\(.name) \(.version)"' | head -n1)"
post '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null || true

tools=""
for _ in $(seq 1 10); do   # servers register asynchronously after startup
  tools="$(post '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' | jq -r 'select(.id==2) | .result.tools[]?.name' 2>/dev/null || true)"
  [[ -n "$tools" ]] && break
  sleep 3
done
if [[ -z "$tools" ]]; then
  echo "FAIL: tools/list returned no tools" >&2
  "${COMPOSE[@]}" logs --tail 80 mcp-gateway >&2
  exit 1
fi
echo "    tools ($(printf '%s\n' "$tools" | wc -l | tr -d ' ')): $(printf '%s' "$tools" | tr '\n' ' ')"
echo "gateway smoke test: OK"
