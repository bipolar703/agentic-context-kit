<div align="center">

# agentic-context-kit

**One source of truth for agent context. Local MCP tools in locked-down containers. Zero telemetry.**

[![validate](https://github.com/bipolar703/agentic-context-kit/actions/workflows/validate.yml/badge.svg)](https://github.com/bipolar703/agentic-context-kit/actions/workflows/validate.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![AGENTS.md](https://img.shields.io/badge/context-AGENTS.md-black)](https://agents.md)
[![MCP](https://img.shields.io/badge/MCP-stdio%20%2B%20streamable%20HTTP-blue)](https://modelcontextprotocol.io)
[![Docker](https://img.shields.io/badge/runtime-Docker%20Compose%20v2-2496ED?logo=docker&logoColor=white)](docker-compose.yml)

[Quick start](#quick-start) · [How it works](#how-it-works) · [Security model](docs/security-model.md) · [Clients](docs/clients.md) · [Contributing](CONTRIBUTING.md)

</div>

---

## Why this exists

| Problem | What usually happens | What this kit does |
|---|---|---|
| **Token waste** | One giant rules file is injected into every turn, whether you are editing Python or a Dockerfile. | A ~900-token core (`AGENTS.md`) plus language rules that load only when matching files are in play. |
| **Fragmented context** | `.cursorrules`, `.cursor/rules`, `.voidrules`, `AGENTS.md`, `CLAUDE.md` drift apart. | `AGENTS.md` is canonical. `CLAUDE.md` imports it. `.cursorrules` and `.voidrules` are generated and drift-checked. |
| **Unsafe local tools** | MCP servers run as host processes with your full user permissions and network. | Each server is a container with no network, read-only rootfs, all capabilities dropped, and one mounted directory. |
| **Silent telemetry** | Toolchains phone home by default. | No analytics code in the kit; common opt-out variables preset in every container. |

> **Scope of "zero telemetry":** it covers this kit and the containers it defines. Your editor, model provider, and Docker Desktop have their own data policies. The optional gateway downloads Docker's MCP catalog and the default `duckduckgo` server makes outbound web requests; remove it from `GATEWAY_SERVERS` for a fully offline stack.

---

## Quick start

**Prerequisites:** Docker Engine or Docker Desktop with Compose v2, Git, `jq` (for smoke tests), and an MCP client (Cursor, VS Code, Claude Code, Claude Desktop, or any stdio/HTTP MCP client). Windows: run the scripts from Git Bash or WSL.

```bash
# 1. Get the kit (or click "Use this template" on GitHub)
git clone https://github.com/bipolar703/agentic-context-kit.git
cd agentic-context-kit

# 2. Configure: creates .env with your UID/GID; never overwrites an existing .env
make env            # or: cp .env.example .env

# 3. Pull the stdio servers and verify your setup
make pull
make doctor

# 4. Prove the sandbox works (handshake, tool list, read-only enforcement)
make smoke
```

Expected `make smoke` output:

```text
==> mcp-filesystem
    server: secure-filesystem-server 0.2.0
    tools (11): read_file read_multiple_files write_file edit_file create_directory list_directory directory_tree move_file search_files get_file_info list_allowed_directories
    PASS: allowed directories = /workspace only
    PASS: write rejected on read-only mount
==> mcp-git
    server: mcp-git 1.1.0
    tools (12): git_status git_diff_unstaged git_diff_staged git_diff git_commit git_add git_reset git_log git_create_branch git_checkout git_show git_init
    PASS: git_status works inside the sandbox
```

**5. Open the folder in your editor.** The client configs are already in the repo:

| Client | Config file | Notes |
|---|---|---|
| Cursor | [`.cursor/mcp.json`](.cursor/mcp.json) | Uses `${workspaceFolder}` |
| VS Code (Copilot agent mode) | [`.vscode/mcp.json`](.vscode/mcp.json) | Top-level key is `servers` |
| Claude Code and portable clients | [`.mcp.json`](.mcp.json) | Paths relative to the project root |

Per-client details, Claude Desktop, and the HTTP gateway are in [docs/clients.md](docs/clients.md).

### Using the kit inside an existing project

Copy `docker-compose.yml`, `.env.example`, `AGENTS.md`, `CLAUDE.md`, `.cursor/`, `.vscode/mcp.json`, `.mcp.json`, `scripts/`, and `Makefile` into your project root. `WORKSPACE_DIR` defaults to `.` (the directory containing `docker-compose.yml`), so the servers see that project and nothing else. Then edit `AGENTS.md` for your project and run `make rules`.

### Optional: HTTP gateway

For several clients at once, or clients that only speak HTTP:

```bash
echo "MCP_GATEWAY_AUTH_TOKEN=$(openssl rand -hex 32)" >> .env
make gateway-up          # waits until healthy
make smoke-gateway       # proxy filtering, 401 without token, tools/list
```

Clients connect to `http://127.0.0.1:8811/mcp` with `Authorization: Bearer <token>`. Stop it with `make gateway-down`; `make clean` also removes containers the gateway spawned.

---

## How it works

### Context layering

```text
Always loaded (~900 tokens)          Loaded on demand (~200-280 tokens each)
┌──────────────────────────┐         ┌───────────────────────────────┐
│ AGENTS.md                │         │ .cursor/rules/typescript.mdc  │  *.ts, package.json ...
│  operating mode          │ ──────► │ .cursor/rules/python.mdc      │  *.py, pyproject.toml
│  context budget          │  glob / │ .cursor/rules/docker.mdc      │  Dockerfile, compose
│  MCP tool use            │  table  └───────────────────────────────┘
│  security, git, output   │
└──────────────────────────┘
      ▲ @import                         Generated for legacy clients (~1,470 tokens, everything inline)
  CLAUDE.md                             .cursorrules   .voidrules    ◄── scripts/sync-rules.sh
```

- **Cursor** reads `AGENTS.md` and attaches `.mdc` rules by their `globs` frontmatter.
- **Claude Code** reads `CLAUDE.md`, which imports `AGENTS.md` with `@AGENTS.md`. (Claude Code only falls back to `AGENTS.md` when no `CLAUDE.md` exists, so the import keeps one source of truth.)
- **Other AGENTS.md agents** follow the table at the top of `AGENTS.md` and open a language rule only when they touch that file type.
- **Legacy clients** (root `.cursorrules`, Void and its forks via `.voidrules`) cannot scope rules, so they receive a generated bundle. CI fails if it drifts.

Token figures come from `scripts/sync-rules.sh`, which uses a rough 4-characters-per-token heuristic, not a real tokenizer. See [docs/token-budget.md](docs/token-budget.md).

### Runtime

```text
┌─────────────────────────────────── Host ───────────────────────────────────┐
│  Editor / agent                                                            │
│    │                                                                       │
│    ├─ stdio ─► docker compose run --rm -T mcp-filesystem ┐  profile: stdio │
│    ├─ stdio ─► docker compose run --rm -T mcp-git ───────┤                 │
│    │            network none · read-only rootfs · cap_drop ALL             │
│    │            no-new-privileges · pids/mem/cpu limits                    │
│    │            ${WORKSPACE_DIR} ──► /workspace (ro by default)            │
│    │                                                                       │
│    └─ HTTP 127.0.0.1:8811/mcp + Bearer ─► mcp-gateway   profile: gateway   │
│                                            │  /run/docker.sock (volume)    │
│                                            ▼                               │
│                                   docker-socket-proxy  (network none)      │
│                                            │  containers/images/networks   │
│                                            │  exec/volumes/system: 403     │
│                                            ▼                               │
│                                   /var/run/docker.sock (ro)                │
└────────────────────────────────────────────────────────────────────────────┘
```

Why the proxy has no network: the gateway attaches every MCP server it spawns to all of the gateway's own networks. A TCP proxy on a shared network would hand those servers the Docker API. A UNIX socket on a volume only the gateway mounts does not. Full reasoning in [docs/security-model.md](docs/security-model.md).

### Directory structure

```text
agentic-context-kit/
├── AGENTS.md                    # Canonical agent rules (always loaded, ≤150 lines)
├── CLAUDE.md                    # @AGENTS.md import for Claude Code
├── .cursorrules                 # GENERATED bundle for legacy Cursor
├── .voidrules                   # GENERATED bundle for Void / forks
├── .cursor/
│   ├── mcp.json                 # Cursor MCP registration
│   └── rules/
│       ├── typescript.mdc       # glob-scoped
│       ├── python.mdc           # glob-scoped
│       └── docker.mdc           # glob-scoped
├── .vscode/mcp.json             # VS Code MCP registration
├── .mcp.json                    # Portable registration (Claude Code, others)
├── docker-compose.yml           # stdio tier + optional gateway tier
├── .env.example                 # Every variable, documented
├── Makefile                     # env, doctor, rules, check, pull, smoke, gateway-*
├── scripts/
│   ├── sync-rules.sh            # Generate/check legacy bundles, enforce budget
│   ├── doctor.sh                # Read-only environment diagnostics
│   ├── verify-hardening.py      # Policy gate over the resolved compose model
│   ├── smoke-test.sh            # Live MCP handshake + sandbox assertions
│   └── smoke-gateway.sh         # Proxy filtering, auth, tools/list over HTTP
├── templates/AGENTS.nested.md   # Starter for per-package AGENTS.md files
├── docs/
│   ├── security-model.md
│   ├── clients.md
│   ├── token-budget.md
│   ├── adding-a-server.md
│   └── troubleshooting.md
└── .github/                     # CI, Dependabot, issue/PR templates
```

---

## Everyday commands

| Command | What it does |
|---|---|
| `make doctor` | Checks Docker, Compose v2, `.env`, workspace path/mode, UID mapping, pulled images, gateway token, rule drift, CRLF |
| `make rules` | Regenerates `.cursorrules` / `.voidrules` and prints approximate token cost |
| `make check` | Rule drift and budget, compose validity, hardening policy, shellcheck |
| `make smoke` | Starts each stdio server like an editor would and asserts sandbox behavior |
| `make smoke-gateway` | Gateway end-to-end test |
| `make help` | Lists every target |

## Configuration

All settings live in `.env` (template: [.env.example](.env.example)).

| Variable | Default | Purpose |
|---|---|---|
| `WORKSPACE_DIR` | `.` | The only directory servers can see |
| `WORKSPACE_MODE` | `ro` | `rw` lets the filesystem server write (files are owned by `HOST_UID`) |
| `HOST_UID` / `HOST_GID` | `1000` | Container user for the filesystem server; `make env` fills in yours |
| `MCP_MEM_LIMIT` / `MCP_CPUS` | `512m` / `1.0` | Per-server limits |
| `MCP_FILESYSTEM_TAG` / `MCP_GIT_TAG` | `latest` | Pin to digests for reproducibility |
| `GATEWAY_PORT` | `8811` | Loopback port for the gateway |
| `GATEWAY_SERVERS` | `duckduckgo` | Docker MCP Catalog servers the gateway runs |
| `MCP_GATEWAY_AUTH_TOKEN` | empty | Bearer token; if empty the gateway generates one and logs it |

## Known limitations

- **`mcp-git` is read-only in practice.** Its image needs root to run (the interpreter lives under `/root`), and with every capability dropped, root cannot write to your host-owned `.git` even with `WORKSPACE_MODE=rw`. Commit from your editor or terminal.
- **The agent can read anything in the workspace, including `.env`.** Keep secrets outside `WORKSPACE_DIR`, or point `WORKSPACE_DIR` at a subdirectory.
- **Prompt injection is not solved by containers.** They limit the blast radius. Keep write-capable tools behind your client's approval prompts.
- **Upstream images float on `latest` by default.** Pin digests before relying on this in a team.

## Contributing

Contributions are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md) first; security reports go through [SECURITY.md](SECURITY.md), not public issues.

## License

[MIT](LICENSE). Third-party images (`mcp/filesystem`, `mcp/git`, `docker/mcp-gateway`, `tecnativa/docker-socket-proxy`, and servers the gateway pulls) are distributed under their own licenses.
