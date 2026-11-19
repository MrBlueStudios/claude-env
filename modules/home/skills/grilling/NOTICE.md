Vendored from https://github.com/mattpocock/skills (commit abeeaf9, v1.3.2),
`skills/productivity/grilling`, on 2026-11-19. MIT, (c) Matt Pocock — see LICENSE.

Adversarial stress-testing of a plan before it is built. This is the one thing the removed
pstack plugin would have given (its `interrogate`), at one skill instead of 58. The sibling
`grill-me` is a thin entry point that delegates here, so only this one is needed.

Local modifications:
- `agents/openai.yaml` dropped (a Codex variant; this repo targets Claude Code)
