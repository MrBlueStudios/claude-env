Vendored from https://github.com/mattpocock/skills (commit abeeaf9, v1.3.2),
`skills/productivity/writing-for-agents`, on 2026-11-19. MIT, (c) Matt Pocock — see LICENSE.

Taken on its own rather than with the pack: the repo ships 39 skills (~2,500 always-on tokens
at the 64-tokens-per-skill rate measured in research/context-budget.md), and most of them
duplicate superpowers, which the crew actually uses — its tdd, diagnosing-bugs, code-review,
research and implement-spec all have a used equivalent already. This one has none.

Local modifications:
- `agents/openai.yaml` dropped (a Codex variant; this repo targets Claude Code)
