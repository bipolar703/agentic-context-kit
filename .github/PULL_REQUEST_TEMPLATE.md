## What and why

<!-- One or two sentences. Link the issue: Closes #123 -->

## Type

- [ ] Rules (`AGENTS.md`, `.cursor/rules/*.mdc`)
- [ ] Runtime (`docker-compose.yml`, new server)
- [ ] Scripts / CI
- [ ] Docs

## Checklist

- [ ] `make check` passes
- [ ] `make smoke` passes (and `make smoke-gateway` if the gateway tier changed)
- [ ] Ran `make rules` after editing rule sources; did not hand-edit `.cursorrules` / `.voidrules`
- [ ] No telemetry, analytics, or phone-home code added
- [ ] No secrets in code, examples, or fixtures
- [ ] New services use `*hardened` and the `stdio` profile, or the PR explains why not
- [ ] Docs and `CHANGELOG.md` updated

## Security impact

<!-- Does this change network access, mounts, users, capabilities, or Docker API access? If yes, explain. -->

## Rule changes: before / after

<!-- For rule PRs: show agent behavior before and after the change. -->
