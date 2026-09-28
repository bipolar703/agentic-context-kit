# Security policy

## Reporting a vulnerability

**Do not open a public issue.** Use GitHub's private vulnerability reporting: **Security → Report a vulnerability** on this repository.

Include:

- what is affected (file, service, or configuration);
- steps to reproduce, ideally with a minimal `.env`;
- the impact (for example: container can reach the Docker API, path escape from `/workspace`, unauthenticated gateway access).

You will get an acknowledgement as soon as the maintainer can review it. Coordinated disclosure is expected; credit is given unless you ask otherwise.

## In scope

- Hardening gaps in `docker-compose.yml`
- Bypasses of `scripts/verify-hardening.py`
- Client configs that expose more than intended
- Rules in `AGENTS.md` or `.cursor/rules` that instruct agents to act unsafely

## Out of scope

Report these upstream:

- `mcp/filesystem`, `mcp/git`: <https://github.com/modelcontextprotocol/servers>
- `docker/mcp-gateway`: <https://github.com/docker/mcp-gateway>
- `tecnativa/docker-socket-proxy`: <https://github.com/Tecnativa/docker-socket-proxy>
- Editors, model providers, and Docker Desktop

See [docs/security-model.md](docs/security-model.md) for the threat model and known limitations.
