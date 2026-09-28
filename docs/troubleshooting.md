# Troubleshooting

Start with `make doctor`. It changes nothing and reports PASS/WARN/FAIL for each check.

| Symptom | Cause | Fix |
|---|---|---|
| Client shows the server as failed immediately | Image not pulled, or Docker not running | `make pull`; start Docker |
| `the input device is not a TTY` or garbled JSON | Missing `-T` in the client config | Use the shipped configs; keep `-T` |
| `EACCES` / `Permission denied` reading files (Linux) | `HOST_UID`/`HOST_GID` do not match your user | `make env` on a fresh `.env`, or set them to `id -u` / `id -g` |
| Writes fail with `WORKSPACE_MODE=rw` | Container UID cannot write to host dirs | Fix `HOST_UID`/`HOST_GID`; check directory permissions |
| `git_add` / `git_commit` fail with `Permission denied` | Expected: `mcp-git` runs as capability-less root | Commit from your editor; see the security model |
| `exec mcp-server-git failed: Permission denied` | `mcp-git` was forced to a non-root user | Keep `user: "0:0"` for that service |
| `WORKSPACE_DIR does not exist` | Relative path resolved from the compose directory | Use an absolute path |
| Windows path errors | Backslashes or drive-letter parsing | Use forward slashes: `C:/Users/me/project` |
| `$'\r': command not found` in scripts | CRLF checkout | `git config core.autocrlf false`, then re-checkout; `.gitattributes` forces LF |
| `docker compose up` starts nothing | Expected: services are behind `stdio` / `gateway` profiles | Editors use `compose run`; gateway uses `make gateway-up` |
| Gateway exits: authentication token is required | Streaming mode needs a token | Set `MCP_GATEWAY_AUTH_TOKEN` (`make token`) or read the generated one from `make gateway-logs` |
| Gateway healthy but `tools/list` is empty | Servers still starting, or the catalog/image download failed | `make gateway-logs`; look for `Can't start <server>` |
| `failed to connect to the docker API at unix:///var/run/docker.sock` in gateway logs | Socket volume not mounted or proxy unhealthy | `docker compose --profile gateway ps`; the proxy must be healthy before the gateway starts |
| Leftover `docker-mcp-l7proxy-*` containers | Spawned by the gateway, not owned by Compose | `make clean` |
