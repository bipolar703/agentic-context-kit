# Adding an MCP server

## 1. Prefer a stdio server with no network

Add a service to `docker-compose.yml` that reuses the hardened anchor:

```yaml
  mcp-example:
    <<: *hardened
    profiles: [stdio]
    image: mcp/example:${MCP_EXAMPLE_TAG:-latest}
    network_mode: none
    environment:
      <<: *no-telemetry
    volumes:
      - ${WORKSPACE_DIR:-.}:/workspace:${WORKSPACE_MODE:-ro}
```

The anchor supplies read-only rootfs, `cap_drop: [ALL]`, `no-new-privileges`, host UID/GID, tmpfs `/tmp`, resource limits, `init`, `stdin_open: true`, and `tty: false`.

## 2. If it needs the network

Say why in the PR. Keep it on the stdio tier if possible and drop `network_mode: none`. The policy check will fail until you update `scripts/verify-hardening.py`, which is deliberate: loosening the sandbox must be an explicit, reviewed change. Alternatively, run it through the gateway tier, which adds an egress proxy per allowed host (`--block-network`).

## 3. If the image will not run as your UID

Check where the entrypoint lives:

```bash
docker image inspect mcp/example --format '{{json .Config.Entrypoint}} {{.Config.User}}'
docker run --rm --entrypoint sh mcp/example -c 'ls -ld /app /root'
```

If it only works as root, set `user: "0:0"` and add the label `io.agentic-context-kit.root-reason: "<why>"`. Capabilities stay dropped.

## 4. Register it with clients

Add the same entry to `.cursor/mcp.json`, `.vscode/mcp.json` (`servers` key), and `.mcp.json`.

## 5. Test it

Extend `scripts/smoke-test.sh`: add a `probes` case with at least one tool call that must succeed and, if relevant, one that must fail (a write on a read-only mount, a path outside `/workspace`). Then run:

```bash
make check
scripts/smoke-test.sh mcp-example
```

## 6. Document it

Add the variable to `.env.example`, a row to the README configuration table, and a line to `CHANGELOG.md`.
