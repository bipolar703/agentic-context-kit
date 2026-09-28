# AGENTS.md (package: <name>)

Scoped instructions for `<path/to/package>`. Agents read the closest AGENTS.md to the files they edit, so keep only what differs from the root file. Target under 30 lines.

## Purpose

- One sentence on what this package does and who calls it.

## Commands (run from this directory)

- Test: `<command>`
- Lint/typecheck: `<command>`

## Local conventions

- <Rule that applies here but not repo-wide.>

## Boundaries

- Do not edit: `<generated or vendored paths>`.
- Public API lives in `<file>`; changes there need a changelog entry.
