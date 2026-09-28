# Contributing

Thanks for helping. This project optimizes for **safety, token efficiency, and portability**, in that order. A change that saves tokens but weakens the sandbox will be declined.

## Before you start

- **Open an issue first** for new servers, rule changes, or anything touching `docker-compose.yml` hardening or `scripts/verify-hardening.py`.
- Small fixes (typos, broken links, clearer docs) can go straight to a PR.

## Setup

```bash
git clone https://github.com/<you>/agentic-context-kit.git
cd agentic-context-kit
make env && make pull && make doctor
```

Windows: use Git Bash or WSL for the scripts. Keep `core.autocrlf=false`; `.gitattributes` enforces LF for shell scripts.

## Workflow

1. Branch from `main`: `feat/<topic>`, `fix/<topic>`, `docs/<topic>`.
2. Make one logical change per commit, using [Conventional Commits](https://www.conventionalcommits.org/) (`feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`, `refactor:`).
3. Run the full local check:

   ```bash
   make check          # rules drift + budget, compose config, hardening policy, shellcheck
   make smoke          # live stdio servers
   make smoke-gateway  # only if you touched the gateway tier
   ```

4. Open a PR and fill in the template.

## Changing rules

- Edit `AGENTS.md` or `.cursor/rules/*.mdc` only, then run `make rules`. Never hand-edit `.cursorrules` or `.voidrules`; CI rejects drift.
- `AGENTS.md` has a 150-line budget.
- Include a before/after example of agent behavior. Rules that add tokens without a demonstrated behavior change will likely be declined.
- Language-specific rules belong in a glob-scoped `.mdc`, not in `AGENTS.md`.

## Changing the runtime

- New services reuse `*hardened` and the `stdio` profile, and follow [docs/adding-a-server.md](docs/adding-a-server.md).
- Any loosening (network, extra mounts, root, socket access) must be called out in the PR description and reflected in `scripts/verify-hardening.py` and `docs/security-model.md`.
- Extend the smoke tests with at least one assertion that proves the new behavior.

## Hard rules

- No telemetry, analytics, crash reporting, or update pings.
- No secrets in commits, examples, or test fixtures.
- New dependencies need a one-line justification and an MIT-compatible license.

## Code of conduct

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
