# vet exemptions

`claude-vet` blocks a plugin that declares a `SessionStart`, `UserPromptSubmit` or
`SubagentStart` hook, because those run code without anyone asking them to: on every session,
every prompt, every subagent. A plugin may still be worth it, but then the reason is written
here rather than clicked past.

One line per exemption, in the form

    - `<plugin name>` <HookEvent> — <why it is worth it, and what it would take to withdraw this>

The name must match the `name` in the plugin's manifest, and the reason has to be an actual
sentence — the check requires it. Re-read this file whenever a plugin is updated: an exemption
is granted to a behaviour, not to a maintainer.

## Granted

- `superpowers` SessionStart — injects the `using-superpowers` skill text at session start,
  which is the entire delivery mechanism for the plugin and is visible in every transcript.
  It is the crew's most-used plugin by a distance (15 brainstorming, 9 systematic-debugging,
  6 TDD invocations in the local history). The hook writes nothing outside `~/.claude` and
  makes no network call; `scripts/server.cjs` and `helper.js` do spawn and open a WebSocket,
  but only on `localhost` when `/brainstorming` is actually run. Withdraw this if a release
  ever adds an outbound address or starts the brainstorm server from the hook itself.

- `svelte` LICENSE — the plugin is the `plugins/svelte` subdirectory of `sveltejs/ai-tools`,
  which carries one MIT LICENSE at its repo root; the per-plugin copy Claude Code caches does
  not include it. Verified 2026-11-19 at
  `~/.claude/plugins/marketplaces/svelte/LICENSE`. Withdraw if the upstream repo relicenses.
- `inbox` LICENSE — first-party: written in this repo on 2026-11-25 for the share inbox
  (`docs/superpowers/specs/2026-11-25-share-inbox-design.md`), nothing in it is vendored, so
  there is no upstream licence to carry. Withdraw the moment any third-party text is copied in.

## Refused

Kept here because a refusal is as worth recording as a grant, and because both of these
remain one `claude plugin install` away.

- `ponytail` SessionStart, SubagentStart, UserPromptSubmit — removed 2026-11-19. The rules
  were the whole value and now live in `modules/home/rules/lazy-senior/`; the hook was not.
  `hooks/band/register.tsx:177` is a `fetch(` behind a `webhookUrl` option whose `sendNames`
  default is `true`, so one settings edit would start posting each task's first prompt to a
  remote address. Nothing was ever sent from this machine and the author is named — this is a
  capability declined, not a betrayal found.
