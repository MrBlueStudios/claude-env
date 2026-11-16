---
name: web-design-guidelines
description: Review UI code for Web Interface Guidelines compliance (accessibility, focus, forms, motion, typography, i18n). Use when asked to review UI, check accessibility, audit design or UX, or check a site against best practices.
argument-hint: <file-or-pattern>
---

# Web Interface Guidelines review

Adapted from vercel-labs/agent-skills (MIT). The rules are vendored next to this file in
`rules.md`, pinned to a known upstream commit, instead of being fetched from GitHub on every run.

1. Read `rules.md` in this skill's directory.
2. Read the files given as arguments (ask which files if none were given).
3. Check every rule. Report in the `file:line` format the rules file specifies, grouped by file.

Project rules win over these guidelines: where a repo's CLAUDE.md or SPEC fixes copy, casing or
design (e.g. blitsolhq-site's final copy), report the conflict instead of proposing a change.
