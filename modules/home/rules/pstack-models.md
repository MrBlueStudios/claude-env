# pstack model configuration. One line per role. Delete a line to fall back to the skill default.
# `inherit-parent` as a value: the role runs on the parent chat model (omit Task `model`).
# Written for Claude Code 2.1.278, where the Agent tool exposes no `effort` parameter, so role
# values carry a model only. Non-Claude (grok-*) defaults map to `inherit-parent` per the adapter.
# budget: medium (high reasoning) — conservative, to protect the account's usage limits.
feature, refactoring: inherit-parent
bug-fix: inherit-parent
perf-issue: inherit-parent
hillclimb: inherit-parent
judgment and prose: opus
hardest tasks: opus
how explorer: inherit-parent
how explainer: opus
why investigators: inherit-parent
why synthesizer: opus
reflect tooling: inherit-parent
reflect judgment, divergent, synthesizer: opus
arena runners: opus, inherit-parent
arena cross-judge pool: opus, inherit-parent
swarm workers: inherit-parent
architect runners: opus, inherit-parent
interrogate reviewers: opus, inherit-parent
