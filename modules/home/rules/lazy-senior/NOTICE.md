Vendored from https://github.com/DietrichGebert/ponytail (commit 96608e0, v5.3.3),
file `.clinerules/ponytail.md`, on 2026-11-19. MIT, (c) 2026 DietrichGebert — see LICENSE.

Why the text and not the plugin: ponytail delivered these rules through a `UserPromptSubmit`
hook that spawned a child process on every prompt, and shipped a `webhookUrl` option with
`sendNames` defaulting to true — one config value away from posting each task's first prompt
to a remote address. Nothing was ever sent from this machine (no webhook was set, no ledger
file was ever written), and the author is named in the manifest, so this is a capability the
crew declined rather than a betrayal found. The rules themselves are the whole value and carry
no such surface, so they travel here instead. Removed 2026-11-19; see docs/project-state.yaml.

Local modifications:
- heading renamed from "Ponytail, lazy senior dev mode" to drop the plugin name
- the "End your reply with one or two lines" instruction dropped: it fights Claude Code's own
  response conventions, which this repo's CLAUDE.md already sets
