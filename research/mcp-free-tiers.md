# mcp-free-tiers

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Verified against the vendors' own pricing pages:** Firecrawl Free is 1,000 credits a month recurring, 10 requests a minute, 2 concurrent, no card. ElevenLabs Free is 10k credits a month with no commercial licence; Starter is $6 a month. Figma's rate-limit page lists View and Collab seats at 20 tool calls a month on every plan and leaves the Starter Full/Dev cell blank, exactly as read. Context7 is 1,000 calls a month, 20 bonus calls a day when blocked, Pro $10 a seat. The Playwright MCP README contains no telemetry statement either way; the source was not searched.
>
> **Measured here, relevant to the "base versus opt-in" line:** none of these servers costs meaningful context at startup (see `context-budget`): the most expensive user-scope server, Sentry, adds about 1,100 tokens; Playwright, Context7 and GitHub add 240–270 each. Tier placement should be decided on usefulness and secrets, not tokens.
>
> **What this changes:** the suggested disposition stands. Figma and ElevenLabs go to the audit as "opt-in, own paid seat if you ship with it".

---

*Owner: Kish · researched 15–16 Nov 2026 · free tiers change often; three of these changed during 2026.*

**Question:** Which of our eight MCP servers stay free when four developers each use their own account for daily web work?

**Answer:** Two are effectively paid: Figma (20 tool calls a month on the free plan) and ElevenLabs (the free plan has no commercial licence, so anything for a client needs the $6 plan). Firecrawl and Context7 are free but metered per account at 1,000 a month each, which a heavy user will exhaust in two to three weeks. Search Console, CoinGecko, Playwright and Svelte are free with no realistic ceiling for us.

**Confidence:** medium — Figma, Context7, Google and Svelte figures come from the vendors' own pages; Firecrawl and ElevenLabs figures come from third-party pages quoting the vendor pricing pages, which I did not open directly.

**What would change our decision:**
- If nobody actually needs to *read* Figma files through MCP more than a few times a month, Figma's 20 calls stop mattering and it can stay as an opt-in.
- If ElevenLabs audio is only ever used internally (never shipped to a client or published), the licence problem disappears and it is simply a small free quota.

## The table

| Server | Free limit | Per account or workspace | At the limit | Risk at four people |
|---|---|---|---|---|
| **Firecrawl** | 1,000 credits/month, no card. 1 credit per scraped page; 2 credits per 10 search results. 10 scrapes/min, 2 concurrent. Keyless mode (no account): 3 tools only, daily cap. | Per account. Keyless mode is **per IP address** — four people behind one router share it. | Stops until the monthly reset; no card on file so no bill. | **Medium** |
| **ElevenLabs** | 10,000 credits/month ≈ 10 minutes of speech. **No commercial licence; attribution required.** | Per account. | Generation stops until reset. | **High** for client work, low for internal use |
| **Context7** | 1,000 API calls/month. | Per account (the vendor page says "per seat" only for Pro; Free scope is not stated). | Blocked, then 20 bonus calls per day until the month resets. | **Medium** |
| **Figma** (official MCP) | **20 tool calls/month** on the Starter (free) plan. Was 6 until about September 2026. Write tools are exempt. | Per seat, but reportedly counted against the team that owns the file. | Read calls fail with a rate-limit error; no reset time published. | **High** — effectively paid |
| **Google Search Console** | No official Google server. Community servers use the free Search Console API: 1,200 queries/min per site and per user; 30,000,000/day per Cloud project. URL inspection: 2,000/day per site. | Per user, per site, and per Google Cloud project. | "Quota exceeded" error; wait and retry. | **Low** |
| **CoinGecko** | Public keyless MCP server: shared rate limits, unspecified, "may change". With a free Demo key: 10,000 calls/month, 100 calls/min. | Keyless: shared pool. Demo key: per account. | HTTP 429. | **Low** (see note 6) |
| **Playwright MCP** | No limit. Local, open source (Apache-2.0), no account. | n/a | n/a | **Low** |
| **Svelte MCP** (official) | No published limit. Remote server needs no account; or run locally with `npx @sveltejs/mcp`. | n/a | Not documented. | **Low** |

## Findings

1. **Firecrawl — free, but 1,000 credits is about 45 pages per working day.** Multiple independent pricing trackers that quote `firecrawl.dev/pricing` (checked between 31 Aug and 14 Nov 2026) agree: Free is 1,000 credits a month with no card, 2 concurrent requests, 10 scrapes a minute. The free tier was a one-time 500 credits earlier in 2026, so this number has already moved once this year. Add-ons multiply cost: JSON extraction adds 4 credits per page. [Pricing breakdown, checked 14 Nov 2026](https://websearchapi.space/blog/firecrawl-pricing) · [second tracker](https://scrapegraphai.com/blog/firecrawl-pricing). Official pricing page not opened directly.

2. **Firecrawl keyless mode is per IP, not per person.** The hosted endpoint `https://mcp.firecrawl.dev/v2/mcp` works with no account but exposes only search, scrape and parse, and is capped per IP address per day. If the four of you are ever on the same network, you share one cap. Each person should sign in with their own free account instead. [Firecrawl launch post](https://www.firecrawl.dev/blog/firecrawl-keyless-launch) · [Firecrawl MCP docs](https://docs.firecrawl.dev/mcp-server) · [server README](https://github.com/firecrawl/firecrawl-mcp-server). The exact daily number is not published: UNVERIFIED.

3. **ElevenLabs — the quota is small, the licence is the real cost.** Free is 10,000 credits a month (one credit ≈ one character, so roughly ten minutes of audio), per account, with API access drawing from the same pool. The free plan carries no commercial licence and requires attribution; commercial use starts at Starter, $6/month. Since you sell websites, any voice-over that reaches a client is outside the free plan. [Plan table, as of 2 Oct 2026](https://www.cartesia.ai/learn/elevenlabs-pricing) · [CloudZero breakdown](https://www.cloudzero.com/blog/elevenlabs-pricing/). One source dated 5 Nov 2026 says "500 AI credits a month" for Free, which contradicts the others; I could not resolve this without the official page, so treat the 10,000 figure as UNVERIFIED against the primary source. [conflicting source](https://bigvu.tv/blog/elevenlabs-pricing-2026-plan-worth/)

4. **Context7 — 1,000 calls a month, then a 20-a-day trickle.** From the vendor's own plans page: Free includes 1,000 API calls a month; at the limit you are blocked and granted 20 bonus calls a day until the month resets. Pro is $10 per seat with 2,000 calls per seat and $5 per extra 1,000. A typical documentation lookup is two calls (resolve the library, then query it), so 1,000 calls is roughly 500 lookups, or about 23 per working day. The free tier has changed three times in twelve months (200/day → 500/month → 1,000/month), so re-check before relying on it. [Context7 plans (official)](https://context7.com/plans) · [price history](https://pricetimeline.com/data/price/context7)

5. **Figma — 20 read calls a month is one session.** Figma's own rate-limits page lists View and Collab seats at up to 20 tool calls a month on every plan, and Full/Dev seats on Professional at 200 a day. It lists no figure for Full/Dev seats on Starter; third-party write-ups citing Figma staff on the forum say every file in a Starter team gets 20 a month and that the count attaches to the team that owns the file rather than to the caller. If that is right, four people reading one Starter team's file share 20 calls between them — UNVERIFIED, forum-sourced. Tools that write to Figma (`create_new_file`, `generate_figma_design`, `whoami`, `add_code_connect_map`) are exempt. The paid route is a Full seat on Professional, about $16 per person per month. [Figma rate limits & access (official)](https://developers.figma.com/docs/figma-mcp-server/rate-limits-access/) · [write-up citing the forum](https://modeinspect.com/blog/figma-mcp) · [seat pricing mention](https://sharkly.ai/blog/use-figma-with-ai-agents-free/)

6. **Google Search Console — there is no official MCP server.** As of early November 2026 Google publishes MCP servers for Analytics and many other products but not Search Console. Every "GSC MCP" is community code (for example `mcp-gsc`, MIT) wrapping the public API, and each needs a Google Cloud project with an OAuth desktop client or a service account. The API is free; the quotas (1,200 queries/min per site and per user, 30 million/day per project) are far beyond four people. Cost is setup time, not money. [Google usage limits (official)](https://developers.google.com/webmaster-tools/limits) · [no official server, checked 4 Nov 2026](https://windsor.ai/google-search-console-mcp/) · [server comparison](https://rybbit.com/blog/google-search-console-mcp). One thing to check during setup: Google OAuth clients left in "testing" mode issue refresh tokens that expire after a week — this is from memory, UNVERIFIED.

7. **CoinGecko — free, with a trading-bot caveat.** CoinGecko runs a public MCP server that needs no key, with shared rate limits it describes as beta and subject to change. A free Demo account gives 10,000 calls a month at 100 calls a minute (another tracker lists roughly 30 a minute for Demo; the pricing page says 100). Interactive questions from four people will not approach this. A trading bot that polls prices will — at one call a minute, a single bot uses about 43,000 calls a month — so that belongs in `trading-free-data`, not here. Whether the hosted MCP server accepts a Demo key or only a paid Pro key: UNVERIFIED. [CoinGecko MCP server (official)](https://mcp.api.coingecko.com/) · [CoinGecko API pricing (official)](https://www.coingecko.com/en/api/pricing)

8. **Playwright MCP — free and local; "nothing phones home" is not confirmed.** It is Microsoft's official server, Apache-2.0, runs on your machine, and needs no account. Two network touches are documented: `npx @playwright/mcp@latest` asks the npm registry on every start, and Playwright downloads a browser on first use. Whether the server sends telemetry of its own: UNVERIFIED — I could not open the repository README from this session. On NixOS the downloaded browser will not run anyway; nixpkgs has a `playwright-mcp` package already wrapped to use the browsers from `playwright-driver.browsers`, which removes both the download and the `@latest` lookup. Use that in the flake. [Playwright MCP install docs (official)](https://playwright.dev/mcp/installation) · [NixOS wiki: Playwright](https://wiki.nixos.org/wiki/Playwright) · [nixpkgs package source (mirror)](https://tangled.org/tjh.dev/nixpkgs/blob/devShellTools-shell/pkgs/by-name/pl/playwright-mcp/package.nix)

9. **Svelte MCP — free, no account.** The remote server is at `https://mcp.svelte.dev/mcp`; the Svelte docs say the team does not log, store or inspect code sent to it. A registry listing describes it as needing no account or authentication and having no upsells. For Claude Code: `claude mcp add -t http -s user svelte https://mcp.svelte.dev/mcp`, or locally `claude mcp add -t stdio -s user svelte -- npx -y @sveltejs/mcp`. No rate limit is published: UNVERIFIED. [Svelte remote setup (official)](https://svelte.dev/docs/ai/remote-setup) · [registry listing](https://www.pulsemcp.com/servers/svelte)

10. **Per account, so four people do not pool — with two exceptions.** Every metered quota above is tied to an individual account, so four accounts means four allowances and no "quietly paid at four people" cliff. The exceptions are Firecrawl keyless (per IP, finding 2) and possibly Figma (per owning team, finding 5). The cliffs here are per person, not per team.

## Suggested disposition for the audit

- **Base tier:** Playwright (from nixpkgs), Svelte, Context7 with each person's own free key.
- **Opt-in, own account:** Firecrawl (signed in, not keyless), CoinGecko, Search Console (needs a Cloud project — decide whether one shared project or four).
- **Reopen:** Figma — decide whether anyone needs it enough to pay for one Full seat. ElevenLabs — keep only if output stays internal, or accept $6/month for whoever ships audio.

## Not checked

- **Official pricing pages for Firecrawl and ElevenLabs** were not opened directly; figures are from third-party pages that cite them. Open both before the audit closes.
- **Our real usage.** "Would four people hit it" is estimated from arithmetic on the limits, not from anyone's logs. `context-budget` or a week of real use would settle it.
- **Playwright MCP telemetry.** The repository could not be opened from this session. Someone should read the README and search the source for "telemetry".
- **Figma's per-team counting** and the Starter Full/Dev figure — forum-sourced only.
- **Which Search Console community server to use** — several exist; I did not compare their code quality or permissions.
- **Terms of service** for automated use of each service were not read.
