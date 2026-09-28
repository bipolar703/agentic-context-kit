# Token budget

Rule files are prepended to the model's context on every request that uses them. A 3,000-token rules file across a 40-turn session is 120,000 input tokens spent before any code is read. The kit keeps that fixed cost small and pays for language detail only when it is relevant.

## Current footprint

Measured by `scripts/sync-rules.sh` (heuristic: characters ÷ 4; real tokenizers vary by model):

| File | Loaded | ~Tokens |
|---|---|---|
| `AGENTS.md` | always | ~900 |
| `.cursor/rules/typescript.mdc` | when TS/Node files are in context | ~260 |
| `.cursor/rules/python.mdc` | when Python files are in context | ~210 |
| `.cursor/rules/docker.mdc` | when Docker/Compose files are in context | ~280 |
| `.cursorrules` / `.voidrules` | legacy clients, always | ~1,470 |

A Python-only session on a scoped client pays about 1,100 tokens of rules per turn instead of about 1,470. The larger your language rules grow, the bigger the gap.

## Rules for writing rules

1. **Budget is enforced.** `AGENTS.md` must stay at or under 150 lines (`RULES_MAX_LINES`); `make check` and CI fail otherwise.
2. **One instruction per bullet.** Imperative, specific, checkable. "Use `uv` for dependencies" beats "prefer modern Python tooling".
3. **Do not document what the agent can discover.** Folder listings and dependency lists go stale and cost tokens. Point to the command that reveals them instead.
4. **Scope by file type with `.mdc` globs**, by directory with nested `AGENTS.md` files (see `templates/AGENTS.nested.md`).
5. **Prove a rule earns its tokens.** A rule-change PR should show agent behavior before and after.

## Behavioral savings

The `Context budget` section of `AGENTS.md` targets the larger cost, which is what agents read rather than the rules themselves:

- search first, then open a specific range, instead of reading whole files;
- never load dependency folders, lockfiles, build output, or source maps;
- read types and tests before implementations;
- return diffs, not re-printed files.

## Measuring

```bash
make rules                         # prints approximate bundle and core size
wc -c AGENTS.md .cursor/rules/*.mdc
```

For exact numbers, run the files through your model provider's token-counting endpoint or tokenizer.
