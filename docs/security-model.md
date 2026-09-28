# Security model

This document explains what the kit defends against, how, and where the limits are. Every control listed here is enforced by `scripts/verify-hardening.py` or asserted by the smoke tests, unless marked otherwise.

## Assets and threats

| Asset | Threat | Primary control |
|---|---|---|
| Files outside the project | A tool (or a model steered by injected text) reads or writes arbitrary host paths | Single bind mount at `/workspace`; filesystem server restricted to it |
| Project files | Unwanted edits | Mount is read-only unless `WORKSPACE_MODE=rw` |
| Secrets and data | Exfiltration over the network | stdio servers run with `network_mode: none` |
| The host | Container escape or privilege escalation | `cap_drop: [ALL]`, `no-new-privileges`, read-only rootfs, no Docker socket in the stdio tier |
| The Docker daemon | Abuse of the Docker API (equivalent to root on the host) | Gateway only, through a filtered, network-less socket proxy |
| Gateway endpoint | Other local processes or web pages calling your tools | Loopback-only port, bearer token, upstream Origin check |

## Stdio tier (default)

Each server is started by your editor with `docker compose run --rm -T <service>` and exits when the editor closes the pipe.

| Control | Setting | Verified by |
|---|---|---|
| No network | `network_mode: none` | policy |
| Read-only root filesystem | `read_only: true`, `tmpfs /tmp` (noexec, nosuid, nodev) | policy |
| No Linux capabilities | `cap_drop: [ALL]`, no `cap_add` | policy |
| No setuid escalation | `security_opt: no-new-privileges:true` | policy |
| Resource limits | `pids_limit`, `mem_limit`, `cpus` | policy |
| One mount only | `${WORKSPACE_DIR}:/workspace:${WORKSPACE_MODE}` | policy |
| Clean stdio framing | `stdin_open: true`, `tty: false`, `-T` in client configs | policy + smoke |
| Scope confinement | Filesystem server reports `/workspace` as its only allowed directory | smoke |
| Read-only enforcement | `write_file` fails when mounted `ro` and no file appears on the host | smoke |

### The `mcp-git` exception

The upstream `mcp/git` image installs its Python interpreter under `/root` with mode `0700`, so any non-root UID gets `Permission denied` on exec. The service therefore runs as `0:0`. This is weaker than a non-root user, but:

- all capabilities are dropped, so root has no `CAP_DAC_OVERRIDE` and cannot bypass file permissions on the mount;
- there is no network and the rootfs is read-only;
- the policy check requires an `io.agentic-context-kit.root-reason` label for any root service and prints a warning.

A side effect: even with `WORKSPACE_MODE=rw`, `git_add` and `git_commit` fail with `Permission denied` on `.git/objects`, because root without capabilities cannot write to directories owned by your user. The kit treats this as a feature. Commits stay in your hands.

## Gateway tier (optional, `--profile gateway`)

The Docker MCP Gateway starts catalog servers as sibling containers, so it needs the Docker API. Handing any container the Docker API is equivalent to handing it root on the host, so the kit narrows and isolates that access.

### Why the proxy has no network

Two behaviors of the upstream gateway drive this design (both visible in its source and logs):

1. When running inside a container, the gateway attaches every MCP server it spawns to **all of the gateway's own networks**.
2. The `docker run` child process that starts each server receives a sanitized environment (essentially `PATH` plus server variables), so `DOCKER_HOST` is not inherited.

A TCP proxy (`DOCKER_HOST=tcp://proxy:2375`) on a shared network would therefore be unused by the child process and reachable from every spawned MCP server. Instead:

- `docker-socket-proxy` runs with `network_mode: none` and binds a UNIX socket (`BIND_CONFIG=/sock/docker.sock mode 600`) on the `docker-api-socket` volume;
- the gateway mounts that volume at `/run`, so `/var/run/docker.sock` inside the gateway is the filtered socket;
- spawned servers join only `gateway-edge` plus the gateway's own egress proxy networks, and never see the socket.

The policy check rejects a networked proxy and any `DOCKER_HOST=tcp://...`.

### What the proxy allows

| Allowed | Denied (HTTP 403) |
|---|---|
| ping, version, events, info, containers (create/start/stop/attach), images, networks, distribution | exec, volumes, build, commit, secrets, configs, auth, swarm, services, tasks, nodes, plugins, system, session, grpc |

`make smoke-gateway` probes this through the shared socket and fails if containers are denied or volumes/system are allowed.

**This is not a sandbox.** Anything that can create containers can create a privileged one. The proxy removes the easiest abuse paths and keeps the socket away from MCP servers. If you do not need the gateway, do not run it.

### Endpoint protection

- Published on `127.0.0.1` only (policy-enforced).
- Bearer token required. The upstream gateway refuses to start streaming mode without one; if `MCP_GATEWAY_AUTH_TOKEN` is empty, it generates a token and prints it in the logs.
- Upstream Origin validation rejects browser requests whose `Origin` is not localhost, which blocks DNS-rebinding attacks.
- The gateway flags `--verify-signatures`, `--block-secrets`, `--block-network`, and `--log-calls` are set explicitly.

## What this kit does not protect against

- **Prompt injection.** A model can still be talked into misusing the tools it has. Containers limit what those tools can reach. Keep write tools behind client approval prompts, and `AGENTS.md` instructs agents to treat tool output as data.
- **Secrets inside the workspace.** Anything under `WORKSPACE_DIR`, including `.env` and `.git`, is readable by the filesystem server.
- **Your editor and model provider.** Prompts and file contents you send to a hosted model leave your machine by design.
- **Supply chain.** Images default to `latest`. Pin digests (`docker buildx imagetools inspect <image>`) and review updates.
- **Docker Desktop and daemon configuration.** Rootless Docker, user namespaces, and Desktop's Enhanced Container Isolation add further protection and are recommended where available.
