Vendored from https://github.com/cursor/plugins/tree/main/thermos (commit 2776ddd)
on 2026-11-05. MIT, (c) 2026 Cursor — see LICENSE.

Local modifications for Claude Code (upstream targets Cursor):
- `Task` -> `Agent`; `subagent_type: "shell"`/`"explore"` -> `Explore` (or plain Bash)
- `run_in_background: true` dropped (Claude Code subagents background by default)
- rubric location changed from "shipped in the Thermos plugin" to ~/.claude/skills/<name>/SKILL.md
