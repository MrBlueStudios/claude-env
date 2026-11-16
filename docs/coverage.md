# Domain coverage audit

Measured 2026-11-13 against the work the crew actually does: hairdresser sites with booking,
a trading bot, Roblox games, a language-learning app, and Blitsol itself.

Per domain: what is covered today, what is missing, and the one change that closes the biggest
gap. Verdicts are about the *shared* environment — a tool that exists only on Léon's laptop,
or only inside one directory, counts as missing for everyone else.

---

## Summary

| Domain | Verdict | Biggest gap |
|---|---|---|
| Web + booking | strong tooling, **no booking** | nothing in the environment knows how to build a booking system |
| Trading | thin | no risk guardrail, no market data beyond crypto |
| Roblox | **best covered** — and unshareable | the toolchain lives outside the module being extracted |
| Learning apps | thin | the one relevant tool (ElevenLabs TTS) is stranded |
| Security | strong — for Léon only | the guard is a *system* module, so friends get no guardrails |
| Design + art | **over-covered** | redundancy, not absence — tier the video suite |
| Legal / GDPR | good at checking, weak at producing | no client-facing privacy/processor documents |
| Accounting | mismatched | the tool he uses is stranded; three he doesn't are connected |
| Infra / deploy | adequate | mcp-nixos registered twice in two different scopes |
| Collaboration | one real hole | Jira — already decided, not yet built |

Three findings cut across every domain and matter more than any single gap:

1. **The security guard does not ship with the flake.** `modules/system/claude-code-policy.nix`
   is a NixOS *system* module, separate from `modules/home/claude/`. The extraction plan covers
   only the home module, so every friend would get the skills, agents and MCP servers with
   **none** of the deny rules — no protection on `.env`, `/run/agenix` or SSH keys, and no
   destructive-command guard. This is the most serious thing the audit found.
2. **Roblox has the same problem.** `modules/home/roblox.nix` and `modules/system/roblox.nix`
   are a complete, genuinely good toolchain, and none of it is inside the module being extracted.
   The friend who makes Roblox games gets nothing.
3. **Tiering has to apply to skills, not just MCP servers.** 36 skills are installed. The
   HyperFrames video suite alone is six of them. Every skill's description sits in context in
   every session of every project, so the base tier should be lean and the heavy suites opt-in.

---

## Web and booking

The crew's bread and butter, and the reason the environment exists.

**Covered.** `web-design-playbook` (pinned via the `claude-web-stack` flake input),
`web-design-guidelines`, `design`, `design-review`, `full-visual`, the `frontend-design`
plugin, the official Svelte MCP with its `svelte-file-editor` agent and `svelte-code-writer`
skill, `playwright` for looking at the result, `site-analytics`, `ship` and `deploy`, the
Cloudflare MCP, and the `frontend` agent. The stack itself — SvelteKit 5, Svelte 5 runes,
shadcn-svelte, Tailwind v4, Caddy, Cloudflare — is recorded in CLAUDE.md so every session
starts from it. This is a mature setup.

Stranded in `~/projects/fastsdcpu` and therefore missing in practice: `shadcn-svelte`,
`lighthouse`, `a11y`, `fonts`, `gsap`, `lottie`, `inspiration`, `eslint`, `gsc`. `figma-dev`
is stranded *and* carries a placeholder PAT.

**Missing.** Booking. Nothing in the environment knows anything about appointment scheduling —
no availability model, no timezone/DST handling, no double-booking prevention, no
cancellation-and-reminder flow, no no-show policy, no calendar sync for the salon's own staff.
Also absent: transactional email (no Resend/Postmark anywhere) and deposit payments, since the
Stripe connector is unauthenticated.

**Biggest gap.** A **booking-system starter** — schema, availability algorithm, reminder jobs,
and the GDPR documents that come with storing a customer's name, phone and appointment history.
Every hairdresser site needs the same thing, and without it the crew rebuilds it five times,
differently, and gets the timezone handling wrong at least once.

This belongs in its own repo, not in `claude-env` — but `claude-env` should ship the skill that
knows how to drive it.

---

## Trading

**Covered.** `anthropic-skills:trading-strategy-researcher` is substantial and covers strategy
design, backtesting, signals, factor models and risk-adjusted returns. The `backend` agent
matches the FastAPI + SQLite WAL stack. `context7` gives current library docs. The Laya
decision model is a genuinely good fit here that nobody has exploited: a calibrated yes/no in
~0.1–0.3 s is exactly the shape of a signal gate, and unlike an LLM it returns a probability
you can threshold.

**Missing.** Market data for anything but crypto — `coingecko` is the only data MCP and it is
stranded under `~/projects/fastsdcpu`. No broker or exchange integration. No backtesting
framework pinned to a version. No paper-trading default. And no pattern for holding exchange
API keys, though agenix already solves this and is sitting right there.

**Biggest gap.** **Nothing in the environment stops a bad change from trading real money.**
There is no kill switch, no paper-trade-by-default convention, no position-size ceiling, and no
rule that live credentials come from agenix rather than a `.env`. The managed guard denies
reading `.env` files, which is a start, but it has nothing to say about placing an order.

A short `trading-safety` skill — paper by default, live mode requires an explicit flag plus an
agenix-held key, hard position ceiling — is cheap and is the difference between a bug costing
an afternoon and costing money.

---

## Roblox

**Covered — and this is the strongest domain in the environment.** `modules/home/roblox.nix`
is a complete free toolchain: Studio under Wine via Vinegar, `rojo` for two-way file sync,
`selene` linting, `stylua` formatting, `luau-lsp` types, `rokit` for toolchain pinning, a
`roblox-doctor` that checks seven things and names the broken one, and a project scaffolder.
The `roblox` skill puts Studio, MCP and Rojo state beside the chat. The `Roblox_Studio` MCP is
correctly project-scoped in `~/Projects/Roblox-Games`, which is the right place for it. There
are two written guides in `/etc/nixos/docs/`. `security-audit` explicitly covers reviewing a
Roblox game against exploits.

**Missing.** Portability, and only portability. Every piece of this lives in nix-config, not in
`modules/home/claude/`. The friend who makes Roblox games would install `claude-env` and find
no Studio, no Rojo, no doctor and no skill.

**Biggest gap.** Move the Roblox modules into the shared flake as an **opt-in module** —
`claude-env.roblox.enable = true` — rather than leaving them behind or forcing Wine and a
multi-gigabyte Studio install on friends who build websites.

---

## Learning apps

**Covered.** The web stack carries most of it. Laya is a strong fit for grading a free-text
answer against a fixed set of outcomes with a calibrated confidence, which is exactly what an
exercise checker needs and is far cheaper than an LLM call per answer. Obsidian tooling covers
content authoring.

**Missing.** Text-to-speech for pronunciation — `elevenlabs` exists but is stranded under `~`.
No spaced-repetition algorithm reference (FSRS or SM-2), which is the single most consequential
design decision in a learning app and the easiest to get subtly wrong. No audio pipeline, and
no i18n skill beyond what `web-design-guidelines` covers in passing.

**Biggest gap.** **Rescue `elevenlabs` to user scope.** It is the one tool in the environment
that directly serves this project, and it is invisible from the project's own directory.

---

## Security

**Covered, and well — on Léon's machine.** The managed PreToolUse guard
(`modules/system/claude-code-policy.nix` plus `claude-code/guard.sh`, with its own test script)
sits above user and project settings, so its deny rules cannot be overridden: `.env`,
`.env.local`, `.env.production`, `/run/agenix/**` and `~/.ssh/id_*` are unreadable, and the
guard covers `cat`/`grep`/`cp` through Bash as well. On top of that: `security-audit`, the
read-only `reviewer` agent, both thermo-nuclear review skills, `review`, and the built-in
`/security-review` and `/code-review`. agenix is already in use for real secrets.

**Missing.** Everything above that is a *system* module, not part of `modules/home/claude/`.
Sentry is unauthenticated. Worth verifying separately whether a CVE scanner (osv-scanner,
trivy, grype) and a secret-scanning pre-commit hook are actually on PATH — `security-audit`
claims dependency auditing, and the claim should be checked rather than trusted.

**Biggest gap.** **The flake must carry the guard.** `claude-env` should expose both a
home-manager module and a NixOS module, with the policy in the second one, and the friend-facing
guide should state plainly that installing only the home module gives you the tools without the
brakes. A shared environment that hands four people an agent with no deny rules is worse than
no shared environment.

---

## Design and art

**Covered — more than any other domain.** `design`, `design-review`, `full-visual`,
`frontend-design`, `figma`, `dataviz`, `artifact-design`, `artifact-diagramming`,
`artifact-capabilities`, `web-design-guidelines`, `web-design-playbook`, `style-sampling`,
`slideshow`, the six-skill HyperFrames suite (`hyperframes`, `hyperframes-cli`,
`hyperframes-registry`, `media-use`, `remotion-to-hyperframes`, `reverse-any-video`), `brag`
and `brag-slim`, plus the Excalidraw connector. `media-use` covers music, sound effects,
images, logos, voiceover and colour grading.

**Missing.** Nothing material. `figma-dev` carries a placeholder PAT; the `figma` skill works
through other means.

**Biggest gap.** **Redundancy.** This is the clearest argument that tiering must cover skills.
A friend building a hairdresser's website pays context for six video-production skills in every
session. Put the HyperFrames suite behind `claude-env.video.enable`, default off.

---

## Legal and GDPR

**Covered.** The `legal-audit` skill covers GDPR, cookie banners, privacy policies, the AI Act
and accessibility. `compliance-scan` is a local tool for web legal red flags.
`web-design-guidelines` covers the accessibility side. `vies-vat` validates EU VAT numbers and
works at user scope. `eu-law` and `overheid-apis` are stranded.

**Missing.** The environment is good at *checking* a site and has nothing for *producing* the
documents. A booking system stores a named person's phone number and appointment history, which
makes every hairdresser client a controller and Blitsol a processor — so each one needs a
privacy policy, a cookie banner that matches what the site actually sets, and a processor
agreement. None of that is generated today.

**Biggest gap.** A **client-document generator** for the booking sites: privacy policy,
processor agreement, retention schedule. It pairs with the booking starter and is the part a
lawyer should review once rather than five times.

---

## Accounting and business operations

**Covered.** HubSpot and Clay connect. QuickBooks connects and exposes a very large surface.
`vies-vat` works. `site-analytics` covers the Blitsol domains.

**Missing.** `moneybird` — the tool actually used for Blitsol's books — is stranded under `~`.

**Biggest gap.** **The connector set does not match the business.** Intuit QuickBooks, Clay and
Indeed are connected or half-connected and appear unused, while Moneybird is stranded. GoDaddy
times out. Each connected server costs context in every session of every project. Rescue
Moneybird, drop what is not used, and put the rest behind the Blitsol tier.

---

## Infrastructure and deployment

**Covered.** The Cloudflare MCP connects. `ship` and `deploy` skills. The `nixadmin` agent.
`docker` and `tailscale` MCPs exist but are stranded under `~`. `mcp-nixos` is registered
**twice** — once in local scope under `~` and again in `/etc/nixos/.mcp.json`. CLAUDE.md
records the Contabo + Caddy + Cloudflare + Litestream stack.

**Missing.** No uptime or certificate-expiry monitoring. Sentry is unauthenticated, so nothing
is watching production errors.

**Biggest gap.** The duplication is the tell: `mcp-nixos` in two scopes, `sequential-thinking`
in two scopes. This is the drift problem in miniature, and `mcp-declarative` is the fix.

---

## Collaboration

**Covered.** GitHub via the MCP, now being pruned in favour of `gh --json --jq`. Google
Calendar, Gmail, Drive and Claude Docs all connect.

**Missing.** Jira, entirely — no server at any scope, despite the crew sharing one board.
Already decided: Atlassian's remote MCP at base tier.

---

## What this changes in the plan

Four items the audit adds or sharpens:

1. **`guard-portability`** — the flake must expose a NixOS module carrying
   `claude-code-policy.nix`, not just the home-manager module. New feature; highest priority of
   the four, because the failure mode is silent.
2. **Roblox as an opt-in module** in the same flake, so the Roblox friend is not left out.
   Folds into `tiers`.
3. **Tiering covers skills too** — the HyperFrames suite and other heavy sets go behind
   opt-in flags. Folds into `tiers`.
4. **Three stranded servers are now named priorities** for the audit table: `elevenlabs`
   (language app), `moneybird` (Blitsol books), `coingecko` (trading). The web-design set from
   `fastsdcpu` was already on the list.

Two product gaps are real but belong to their own projects, not to `claude-env`: the **booking
starter** and the **client-document generator**. `claude-env` should ship the skills that know
how to drive them once they exist.
