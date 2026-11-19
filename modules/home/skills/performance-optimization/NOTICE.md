Vendored from https://github.com/addyosmani/agent-skills (commit 8c99fa3, v0.6.17),
`skills/performance-optimization` plus `references/performance-checklist.md`, on 2026-11-19.
MIT, (c) Addy Osmani — see LICENSE.

One skill of the pack's 26. It is a method — measure, profile, find the real bottleneck —
and it spans both halves of the crew's stack: N+1 queries and missing indexes on the
FastAPI/SQLite side, Core Web Vitals and bundle size on the SvelteKit side. The `review`
skill names those as checklist items; this says how to find them.

Its sibling `accessibility-engineering` was deliberately NOT taken. web-design-guidelines
already carries 25 concrete WCAG rules written against this crew's own Tailwind and Svelte
idioms, and the addyosmani one is stack-agnostic and pulls in a reference file, a sibling
skill and an agent persona to say less. Same reason UI/UX Pro Max was rejected: a sixth
overlapping a11y asset is a cost, not a capability.

Note for anyone installing the full pack instead: it ships `hooks/session-start.sh`,
`hooks/sdd-cache-{pre,post}.sh` and `hooks/simplify-ignore.sh`. The plugin manifest does not
declare them, so `claude plugin install` does not activate them, but the repo's own setup
instructions wire them up. `just vet` blocks a SessionStart hook for a reason.

Local modifications:
- `references/performance-checklist.md` moved in from the repo-level `references/` directory,
  and the `../../references/` paths in SKILL.md and optimization-patterns.md rewritten to
  `references/`, so the skill is self-contained
