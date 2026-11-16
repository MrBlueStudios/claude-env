# MCP audit — every server, a verdict, one reason

*16 November 2026. Applies the settled CLI-first rule (q-mcp-philosophy) and the tier decision (q-tiers) to every MCP registration found on Léon's machine. Context costs are from `research/context-budget.md`; free-tier facts from `research/mcp-free-tiers.md`.*

**Rule of thumb used:** a server stays only if it does something a CLI cannot do as cheaply (OAuth-bound SaaS APIs, browser automation, model inference) *and* it carries no secret that a later friend should not have. Anything whose token is still `YOUR_…` is dead today and is marked **fix** or **drop**.

## Where the 39 registrations are

| scope | count | file |
|---|---|---|
| user | 9 | `~/.claude.json` → `mcpServers` |
| local | 25 | `~/.claude.json` → `projects[…].mcpServers` (10 under `~`, 1 under `/etc/nixos`, 14 under `~/projects/fastsdcpu`) |
| project | 5 | `.mcp.json` in `/etc/nixos`, `Roblox-Games`, `Laya_And_CLM-MCPs` |
| account | 12 connectors + 1 plugin | claude.ai connectors (not in any file) and the Svelte plugin |

## Verdicts

Tier column: **base** = every friend gets it · **blitsol** = the four of us, needs a shared credential or invite · **opt-in** = a named module someone turns on · **project** = stays in that repo's `.mcp.json` · **personal** = Léon's own, never in the flake · **drop** = removed.

### User scope (9)

| server | today | verdict | tier | reason |
|---|---|---|---|---|
| context7 | http, no key | **keep** | base | Current library docs; 239 tokens; free 1,000 calls/month per person with their own key. |
| playwright | npx `@playwright/mcp@latest`, custom Chromium path | **keep, repackage** | base | Browser automation for the design skills; use nixpkgs `playwright-mcp` so there is no `@latest` lookup, no browser download, and no Léon-specific `~/.local/bin/claude-chromium` path. |
| sentry | http, OAuth | **opt-in** | opt-in `sentry` | 1,089 tokens, the most expensive server; only projects that ship to Sentry need it. |
| cloudflare | http `mcp.cloudflare.com`, OAuth | **keep** | blitsol | Official API server, per-user OAuth; replaces the deprecated Developer Platform connector. `wrangler` covers deploys, this covers everything else. |
| vies-vat | node, Léon's own build in `~/projects` | **keep, package** | base | EU VAT check for invoicing; no secret; must be built by Nix in the flake instead of pointing at a path on one laptop. |
| obsidian | `@bitbonsai/mcpvault` on `~/Obsidian/ZEN-Vault` | **drop from user scope** | personal | Points at Léon's private vault; the crew vault is written by hooks and read with file tools. Re-add at local scope if Léon wants it for himself. |
| memory | npx server-memory | **drop** | — | Settled: one memory system, file-based. Per-machine JSON cannot be shared. |
| github | npx server-github | **drop** | — | Settled: `gh --json --jq` is cheaper and already authenticated. |
| filesystem | npx server-filesystem | **drop** | — | Settled: built-in file tools; it cannot even see `~/Projects`. |

### Local scope under `~` (10)

| server | today | verdict | tier | reason |
|---|---|---|---|---|
| mcp-nixos | uvx, unpinned | **opt-in** | opt-in `nix` | Useful for option lookup on NixOS; keep the pinned project-scope copy in `/etc/nixos`, offer the same pin as an opt-in module. `mcp.nix` currently lists it as legacy, which is right for user scope. |
| sequential-thinking | npx | **drop** | — | The model reasons natively; the tool adds tokens and nothing else. Also registered under `/etc/nixos` — drop both. |
| eu-law | npx `@ansvar/eu-regulations-mcp`, no key | **opt-in** | opt-in `legal` | Free, keyless; only the compliance work needs it. |
| moneybird | npx, `MONEYBIRD_API_TOKEN=YOUR_TOKEN_HERE` | **fix** | blitsol | Dead today (placeholder). Token and administration id come from the agenix Blitsol secrets; this is the one server that justifies the secrets repo. |
| ollama | npx `ollama-mcp`, `OLLAMA_HOST=http://localhost:1…` | **drop** | — | `ollama` CLI does the same; the host value is a stub. |
| docker | uvx `mcp-server-docker` | **drop** | — | `docker` CLI. |
| tailscale | npx, `TAILSCALE_API_KEY=YOUR_TAILSCALE_API` | **drop** | — | Placeholder key; `tailscale` CLI covers status and serve. |
| firecrawl | npx, `FIRECRAWL_API_KEY=YOUR_KEY` | **fix** | opt-in `firecrawl` | Placeholder here, but `mcp.nix` already ships `firecrawl-mcp-agenix` with the key from agenix. Each person uses their own free account (1,000 credits/month); never keyless, which is per IP. |
| shopify | npx, `--accessToken YOUR_SHOPIFY_ACCESS_TOKEN` | **drop until needed** | project | No Shopify client today. When one appears it is a per-client token in that project's `.mcp.json`, never shared. |
| elevenlabs | uvx, `ELEVENLABS_API_KEY=YOUR_KEY` | **drop** | — | Placeholder, and the free plan has no commercial licence; whoever ships audio pays $6 and adds it locally. |

### Local scope under `/etc/nixos` (1)

| server | verdict | reason |
|---|---|---|
| sequential-thinking | **drop** | See above. |

### Local scope under `~/projects/fastsdcpu` (14)

These were an experiment bundle attached to one unrelated project. None belongs there.

| server | today | verdict | tier | reason |
|---|---|---|---|---|
| stripe | http `mcp.stripe.com` | **drop here** | blitsol (connector) | Duplicate of the Stripe connector, which is the Blitsol-tier path via account invite. |
| coingecko | `mcp-remote` to CoinGecko's public server | **opt-in** | opt-in `trading` | Keyless, free; only the trading-bot project. |
| gsc | npx `mcp-server-gsc`, needs a Google Cloud OAuth client | **opt-in, document setup** | opt-in `seo` | No official Google server; free API; each person needs a Cloud project. Fine for the website work, not base. |
| todoist | http | **drop** | personal | Not a crew tool; Jira is. |
| overheid-apis | npx, no key | **opt-in** | opt-in `legal` | Dutch government API register; free; pairs with eu-law. |
| figma-dev | `--figma-api-key=YOUR_FIGMA_PAT` | **drop** | — | Placeholder, and Figma allows 20 read calls a month on Starter; anyone who needs it pays for a seat and adds it locally. |
| shadcn-svelte | http | **drop** | — | Context7 and the Svelte plugin cover the docs. |
| gsap | npx | **drop** | — | Context7 covers the docs. |
| lighthouse | npx | **drop** | — | `lighthouse` CLI. |
| a11y | npx | **drop** | — | Playwright plus the `axe` CLI. |
| eslint | npx `@eslint/mcp` | **drop** | — | `eslint` CLI. |
| fonts | uvx google-fonts-mcp | **drop** | — | The Google Fonts site and CSS API. |
| lottie | npx | **drop** | — | Not used by any project. |
| inspiration | npx, `SERPER_API_KEY=YOUR_SERPER_KEY` | **drop** | — | Placeholder key; web search covers it. |

### Project scope (5)

| repo | server | verdict | reason |
|---|---|---|---|
| `/etc/nixos` | nixos (`mcp-nixos==3.1.0`) | **keep** | Pinned, scoped to the config repo; the nixadmin agent uses it. |
| `/etc/nixos` | Roblox_Studio | **keep, move** | Belongs in the Roblox opt-in module, not the system config. |
| `Roblox-Games` | Roblox_Studio | **keep** | Project that actually uses it; the wrapper `roblox-studio-mcp` comes from the Roblox module. |
| `Laya_And_CLM-MCPs` | laya-mcp-server | **promote** | Goes to user scope, base tier, with absolute paths (feature `laya-clm-userscope`). |
| `Laya_And_CLM-MCPs` | clm-mcp-server | **keep here only** | CLM is parked (16 Nov); the project-scope entry stays as the ready-made client for when a host exists. |

### Account-level: claude.ai connectors (12) and the Svelte plugin

These bind to each person's Claude account, not to the machine, so the flake cannot install them; the friend guide tells people which to connect.

| connector | verdict | reason |
|---|---|---|
| HubSpot | **blitsol** | Invite each friend as a HubSpot user; connector then uses their own login. |
| Stripe | **blitsol** | Invite as a Stripe team member; same pattern. |
| Cloudflare Developer Platform | **remove** | Deprecated upstream in favour of `mcp.cloudflare.com`, which is the user-scope `cloudflare` server. |
| Intuit QuickBooks | **remove** | Blitsol runs on Moneybird, not QuickBooks. |
| Indeed | **remove** | Needs authentication, no known use. |
| Clay | **personal** | Léon's prospecting; not a crew tool unless someone asks. |
| GoDaddy | **personal** | Domain checks; Cloudflare registrar is the Blitsol default. |
| Claude Docs, Excalidraw | **personal, recommended** | Free, useful, each person connects their own. |
| Gmail, Google Calendar, Google Drive | **personal** | Each person's own Google account; the Jira-to-Calendar link is a Jira setting, not a connector. |
| plugin: svelte | **base** | Official Svelte docs and autofixer; installed as a plugin, no account, no limit published. |

## What the base tier ends up as

context7 · playwright (nixpkgs) · svelte plugin · atlassian (`https://mcp.atlassian.com/v2/mcp`, OAuth, with an `ask` rule on writes) · laya (user scope) · vies-vat (Nix-built). Measured cost of the equivalent set today: under 1,000 tokens at session start.

**Blitsol tier adds:** cloudflare (own OAuth), moneybird (agenix token), and the HubSpot and Stripe connectors by invite.

**Opt-in modules:** `nix` (mcp-nixos), `roblox` (Roblox_Studio), `legal` (eu-law, overheid-apis), `trading` (coingecko), `seo` (gsc), `firecrawl` (own key via agenix), `sentry` (per project).

**Dropped:** 23 registrations, of which 8 were dead placeholders (moneybird and firecrawl are fixed rather than dropped; ollama, tailscale, shopify, elevenlabs, figma-dev, inspiration go).

## Dead-or-fix checklist

| server | token field | state |
|---|---|---|
| moneybird | `MONEYBIRD_API_TOKEN`, `MONEYBIRD_ADMINISTRATION_ID` | **fix** via agenix Blitsol secret |
| firecrawl | `FIRECRAWL_API_KEY` | **fix** — `mcp.nix` wrapper already reads it from agenix |
| tailscale | `TAILSCALE_API_KEY`, `TAILSCALE_TAILNET` | drop |
| shopify | `--accessToken`, `--domain` | drop until a Shopify project exists |
| elevenlabs | `ELEVENLABS_API_KEY` | drop |
| figma-dev | `--figma-api-key` | drop |
| inspiration | `SERPER_API_KEY` | drop |
| ollama | `OLLAMA_HOST` stub | drop |

## How this is applied

Not by hand. Feature `mcp-declarative` writes the `mcpServers` block of `~/.claude.json` from Nix on activation (merging, not replacing, so personal local-scope entries survive), and `mcp-consolidate` runs the prune once. The `legacy` list in `mcp.nix` grows by the dropped names above; `playwright` and `svelte` come off that list because they stay.
