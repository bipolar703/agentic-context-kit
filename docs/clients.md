# Client setup

All stdio configs launch the same command:

```text
docker compose [--project-directory <root>] -f <root>/docker-compose.yml run --rm -T <service>
```

`-T` disables TTY allocation (a TTY corrupts JSON-RPC framing). `run` activates the service's `stdio` profile automatically, so no `--profile` flag is needed. Run `make pull` first so the first launch does not stall on an image download.

## Cursor

File: `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global).

The shipped file uses `${workspaceFolder}`, which Cursor resolves to the folder containing `.cursor/mcp.json`. Open the project root in Cursor, then check **Settings → MCP** for `filesystem` and `git`.

Rules: Cursor reads `AGENTS.md` and the glob-scoped `.cursor/rules/*.mdc`. The root `.cursorrules` is a generated legacy bundle; Cursor documents that file as legacy.

## VS Code (GitHub Copilot agent mode)

File: `.vscode/mcp.json`. The top-level key is `servers` (not `mcpServers`), and `${workspaceFolder}` is resolved by VS Code. Start the servers from the MCP view or the code lens in the file.

## Claude Code

File: `.mcp.json` at the project root. Paths are relative because Claude Code runs from the project root. Rules come from `CLAUDE.md`, which imports `AGENTS.md`.

## Claude Desktop and other global-config clients

These clients start servers from an arbitrary working directory, so use absolute paths:

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "docker",
      "args": [
        "compose",
        "--project-directory", "/ABSOLUTE/PATH/TO/agentic-context-kit",
        "-f", "/ABSOLUTE/PATH/TO/agentic-context-kit/docker-compose.yml",
        "run", "--rm", "-T", "mcp-filesystem"
      ]
    }
  }
}
```

Windows paths in JSON use forward slashes or escaped backslashes: `C:/Users/me/agentic-context-kit/docker-compose.yml`.

## Gateway over HTTP (any client)

Start it with `make gateway-up`, then register a remote server:

```json
{
  "mcpServers": {
    "docker-gateway": {
      "url": "http://127.0.0.1:8811/mcp",
      "headers": { "Authorization": "Bearer ${env:MCP_GATEWAY_AUTH_TOKEN}" }
    }
  }
}
```

`${env:NAME}` interpolation is Cursor syntax; other clients have their own (VS Code uses `${input:...}` or env files). Never paste the literal token into a committed file.

Test it by hand:

```bash
curl -s http://127.0.0.1:8811/health
curl -s -X POST http://127.0.0.1:8811/mcp \
  -H "Authorization: Bearer $MCP_GATEWAY_AUTH_TOKEN" \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json, text/event-stream' \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"curl","version":"1"}}}'
```
