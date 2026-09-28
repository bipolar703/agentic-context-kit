# Changelog

All notable changes are documented here. Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/).

## [Unreleased]

### Added

- Layered agent context: `AGENTS.md` core, glob-scoped `.cursor/rules/{typescript,python,docker}.mdc`, `CLAUDE.md` import, and generated `.cursorrules` / `.voidrules` with drift and budget checks.
- Hardened stdio runtime (`profile: stdio`) for `mcp/filesystem` and `mcp/git`: no network, read-only rootfs, `cap_drop: [ALL]`, `no-new-privileges`, resource limits, single workspace mount.
- Optional gateway tier (`profile: gateway`): `docker/mcp-gateway` on `127.0.0.1` with bearer auth and a healthcheck, using a network-less `tecnativa/docker-socket-proxy` shared over a UNIX socket volume.
- Client registrations for Cursor, VS Code, and portable `.mcp.json`.
- `scripts/doctor.sh`, `scripts/verify-hardening.py`, `scripts/smoke-test.sh`, `scripts/smoke-gateway.sh`, and a `Makefile`.
- CI: static checks and live smoke tests for both tiers; Dependabot for Actions.
- Documentation: security model, client setup, token budget, adding servers, troubleshooting.

### Security

- Gateway-spawned MCP servers cannot reach the Docker API: the upstream gateway attaches servers to all of its networks, so the proxy has no network and is reachable only through a socket file mounted into the gateway.
