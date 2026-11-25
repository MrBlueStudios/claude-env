# agent-reach
**Question:** How does Agent Reach read X, Reddit and LinkedIn without official APIs, which terms and ban risks come with that, and is it worth using in a share-to-Claude link inbox?
**Answer:** Don't use it for the inbox. For X, Reddit and LinkedIn it drives a logged-in, anti-detect browser (CloakBrowser plus the OpenCLI extension) that holds the crew member's real session. That breaks all three platforms' terms and puts a personal account at risk, for a job (one public URL to text) that logged-out fetchers do with no account. Use public, no-login routes instead: X oEmbed or fxtwitter, Jina Reader, and logged-out page fetches with a graceful "couldn't fetch" fallback. For Reddit, the free API path now needs approval.
**Confidence:** medium, because the source was read directly but X's ToS, the Reddit terms and the Reddit wiki could not be fetched, and the Reddit availability claims come from vendor blogs.
**What would change our decision:**
- If the crew wants X or Reddit content that is not public (protected accounts, login-walled threads), then a dedicated throwaway account in a separate browser profile becomes the only option. Whether that is worth the terms risk is a human decision.
- If Reddit grants us free non-commercial API approval, or X's pay-per-use API turns out to cost cents at a few reads a day, the official route replaces every scraping route.

## Findings

File:line references are to commit 8d9ecc1 (2026-11-24) of https://github.com/Panniantong/Agent-Reach, not to a local path.

1. **Vet gate result (`just vet`, run 25 Nov).** MIT licence. 1 skill, 0 agents, 0 commands, no hooks, about 64 always-on tokens. Process spawning and network calls are flagged mostly in tests/ and scripts/accept-search.py. Env reads: AGENT_REACH_CONFIG_FILE, GROQ_API_KEY, HTTP(S)_PROXY, PIPX_HOME, XIAOYUZHOU_URL. 96 distinct outbound addresses, many of them SSRF-test literals. No blocking findings.
   - The gate could NOT see what Agent Reach installs and runs at runtime. docs/cloakbrowser.md:5 says `agent-reach add` installs Node, OpenCLI, the browser and an extension.
   - CloakBrowser is a stealth Chromium binary downloaded into `~/.agent-reach/cloak-binaries`. Its binary licence is separate and is not MIT (docs/cloakbrowser.md:15).
   - OpenCLI is the npm package from jackwener/opencli, pinned to 2.0.3 for new installs (docs/cloakbrowser.md:13). It comes with a Chrome browser-bridge extension (id in agent_reach/backends/opencli.py:10) and a local daemon.
   - It also pulls yt-dlp, a private ffmpeg, and other CLIs, installed by `uv tool` (docs/troubleshooting.md:59).
   - Whatever those packages do is outside the gate's scan of this repo and was not audited (see Not checked).

2. **X: mechanism and whose account.** X goes through OpenCLI in the dedicated browser, marked "experimental" (agent_reach/channels/twitter.py:2,28). The actions are search, profile, tweets and thread (:38-72). Each shells out to `opencli twitter …` (agent_reach/backends/opencli.py:59-78).
   - The login hint tells the user to log in to x.com in the Agent Reach browser (twitter.py:10).
   - The account on the line is the user's own X account, logged in inside that browser.
   - No logged-out path or guest token is implemented. `public_web=("x.com/","twitter.com/")` (twitter.py:48) only tells the calling agent that its own web tools may try first.
   - A comment at twitter.py:26 says twitter-cli was dropped because it re-read browser cookies even when given explicit credentials.

3. **Reddit: mechanism and whose account.** Same OpenCLI route, with commands search, read and subreddit (agent_reach/channels/reddit.py:41-70). The docstring (:1-7) says public posts may be readable with the agent's own web tools without login, and that a blocked anonymous JSON endpoint does not mean login is required. The login hint (:15) points at the dedicated browser.
   - The account on the line is the user's own Reddit account, when a login is needed at all.
   - Repo issue #964 (Nov 13, 2026) reports `read` returning Reddit's block page as ok=true. The reporter suggests falling back to HTML when `.json` returns 403 (from the issue list page only; body not read).

4. **LinkedIn: mechanism and whose account.** Jobs only: `jobs` search and `read` for `/jobs/view/<id>` URLs (agent_reach/channels/linkedin.py:20-49). It does not read posts, profiles or articles. It uses OpenCLI in the shared browser, with `login_cookie = "li_at"` (:18), which is LinkedIn's session cookie. The account on the line is the user's own LinkedIn account. Issue #974 (Nov 15, 2026) reports failures for non-English LinkedIn accounts. For LinkedIn posts shared from a phone, Agent Reach has no capability.

5. **Cookie sourcing: the docs contradict the code.** `docs/troubleshooting.md:45` says "Personal Chrome sessions are never imported." But `docs/cloakbrowser.md:7` and agent_reach/runtime/session_reuse.py:54-78 do reuse existing local site cookies.
   - `_source_cookies` asks the OpenCLI Browser Bridge in the user's other, non-dedicated browser profiles for that site's cookies (`export_site_cookies`, backends/opencli.py:120-140).
   - It then copies them into the dedicated browser with CDP `Storage.setCookies` (session_reuse.py:125).
   - Cookies are scoped to the requested site and the copy is read-only. If several profiles have cookies it refuses to guess (:76-78).
   - Reading browser cookies directly (browser_cookie3 and similar) is blocked. The stub at agent_reach/runtime/no_browser_cookies/browser_cookie3.py:1-7 raises ImportError for third-party tools.
   - Net effect: a real personal session can be copied into a stealth browser automatically. On a phone-share inbox server, that is a crew member's cookie sitting on the server.

6. **Stealth and anti-detect.** The dedicated browser prefers CloakBrowser through its persistent-context launcher (agent_reach/runtime/browser.py:4,329-354; browser_watcher.py:75). It opens a CDP port on 127.0.0.1, default 9222 (browser.py:38,367-368). It falls back to system Chrome if the download fails. Anti-bot evasion is what CloakBrowser exists for. That makes bot-detection intent clearer under the terms below.

7. **Do third parties see cookies or content?** No Agent Reach-run server was found in the paths read. Cookies stay on the local machine, in `~/.agent-reach/browser/profile` and `~/.agent-reach/config.yaml`. The channel code only shells out to local `opencli` (backends/opencli.py:65).
   - UNVERIFIED: whether OpenCLI or the extension phones home. OpenCLI's code was not read.
   - Content goes to the platform itself, which sees a stealth browser behind a real account.
   - The web channel sends URLs to r.jina.ai (agent_reach/channels/web.py:184), with Exa as a second backend (:173). Those services see the URL and the fetched content, not the cookies.
   - Jina's own docs state: cookie-bearing requests are never cached, the `DNT` header disables caching and logging, and inputs are not used for training ([jina.ai/reader](https://jina.ai/reader/)).

8. **Transcription (GROQ_API_KEY), relevant to reel-transcription.md.** agent_reach/transcribe.py downloads audio with yt-dlp, with an SSRF guard against private IPs (:211-244, :247-284). It then compresses to mono 16 kHz 32 kbps m4a, chunks into 10-minute pieces (:287-355), and POSTs each chunk to Groq's `https://api.groq.com/openai/v1/audio/transcriptions` with `whisper-large-v3` (:45-50, :385-391). OpenAI `whisper-1` is the second provider.
   - Auto mode uses only the first configured provider (Groq, then OpenAI). It falls back to the other only if `allow_provider_fallback=True` (:438-439).
   - Limits: 512 MiB source, 4 hours of audio, 24 chunks, 96 MiB total (:36-43).
   - The audio leaves the machine for Groq. This part has no account-ban or cookie issue.
   - It is generic and easy to copy; a reel pipeline could call Groq directly with ffmpeg and yt-dlp, with no need for Agent Reach. UNVERIFIED: Groq's current free-tier limits and data-retention terms (not fetched).

9. **X terms.** X's [Terms of Service](https://x.com/en/tos) could not be fetched (HTTP 402). A search summary quotes: "crawling or scraping the Services in any form, for any purpose without our prior written consent is expressly prohibited." It also bars accessing the Services by automated means other than X's published interfaces. The scraping ban dates from Sept 29, 2023 ([Yahoo Finance coverage](https://finance.yahoo.com/news/x-updates-terms-ban-crawling-133548839.html)). Automating a logged-in session through a stealth browser breaks this. The clause wording is second-hand until someone reads the live page.
   - Official route: X API v2 is pay-per-use. Post lookup (`GET /2/tweets`) is billed per successful read, with no monthly minimum and no free tier mentioned ([X docs](https://docs.x.com/x-api/fundamentals/post-cap)). Per-endpoint prices are only in the Developer Console (UNVERIFIED).

10. **Reddit terms.** The Reddit User Agreement and the Data API wiki could not be fetched. A search for the wording of its automated-access clause returned no Reddit source. Do not assert clause text until someone reads [redditinc.com/policies/user-agreement](https://www.redditinc.com/policies/user-agreement) and [Reddit's Data API terms](https://www.redditinc.com/policies/data-api-terms). Third-party summaries (vendor blogs, so treat with caution):
    - The official Data API was historically free for non-commercial use at 100 queries per minute per OAuth client ([summary](https://www.redditcommentscraper.com/article-reddit-data-api.html)).
    - Reddit's Responsible Builder Policy (Nov 2025, updated Jun 5, 2026) puts new API access behind manual approval, reportedly 2 to 4 weeks. Sources disagree on whether non-business users are exempt ([summary](https://prowlo.com/blog/reddit-data-api)).
    - Unauthenticated `.json` was reportedly shut down from May 28, 2026 and returns 403 ([DEV article](https://dev.to/tonywangca/why-reddit-blocked-unauthenticated-json-in-2026-and-how-to-still-get-reddit-data-58b9)).
    - One source says the public Data API closes in March 2027 (single-source, UNVERIFIED).
    - So the `.json` suffix is likely dead, and the free API tier exists but needs approval.
    - The Data API terms reportedly forbid using the data to train AI models without permission (UNVERIFIED).

11. **LinkedIn terms.** [User Agreement §8.2](https://www.linkedin.com/legal/user-agreement) (fetched live) says don't "use bots or other unauthorized automated methods to access the Services". It also says don't build or use "crawlers, scripts, or other tools to scrape or copy the Services, including profiles", and don't bypass access controls. It prohibits using another's account, "such as sharing log-in credentials or copying cookies."
    - A copied li_at session fits that last clause. LinkedIn's [account restrictions help page](https://www.linkedin.com/help/linkedin/answer/a1340522) says automated activity can cause temporary or permanent restriction.
    - hiQ history: the Ninth Circuit held CFAA likely did not bar scraping public pages. In Nov 2022 the district court still found hiQ breached the User Agreement, and a consent judgment with a permanent injunction and $500k followed on Dec 8, 2022 ([ZwillGen](https://www.zwillgen.com/alternative-data/hiq-v-linkedin-wrapped-up-web-scraping-lessons-learned/), [Privacy World](https://www.privacyworld.blog/2022/12/linkedins-data-scraping-battle-with-hiq-labs-ends-with-proposed-judgment/)). The lesson is that a user agreement binds you once you accepted it, even where criminal law doesn't apply.

12. **Ban risk at a few links a day.**
    - Agent Reach's own docs treat blocks as real. A `PLATFORM_BLOCKED` error says stop and "do not switch accounts or backends" (agent_reach/skill/SKILL_en.md:50). `RATE_LIMITED` says the same (docs/troubleshooting.md:20). The error handler matches "account_risk" and captcha text (backends/opencli.py:47).
    - No ban reports were seen in the repo issues. A listing filtered for ban, suspended, locked, risk or cookie returned only #974, #964 and #938, all about reading failures, not accounts. Titles and previews only, not issue bodies.
    - Practical read, an assessment and not a measured rate: a handful of reads a day through a real, logged-in, stealth browser is low volume, so a permanent ban is unlikely. Session challenges, forced logouts or a LinkedIn identity check are plausible. LinkedIn is the most aggressive.
    - Vendor blogs describe LinkedIn escalating from session friction to an ID check, a restriction, then closure. They say cookie-based tools are the riskiest category ([Clawnify](https://www.clawnify.com/resources/linkedin-account-restricted), [contentin.io](https://contentin.io/blog/linkedin-mcp-terms-of-service/)). These authors sell alternatives, so they are not neutral.
    - The downside is asymmetric. The crew's personal accounts carry the risk, to save a few seconds on a link.

13. **Safer alternatives for our use case (single public URL to text).**
    - **X:** `https://publish.x.com/oembed?url=<post url>` is official, needs no auth, and returns JSON with an HTML blockquote containing the post text ([X docs](https://docs.x.com/x-for-websites/embedded-posts/overview)). Text only, no media or thread. Check the Developer Terms before bulk use. fxtwitter/vxtwitter-style JSON (the FxEmbed project, [MIT](https://github.com/FxEmbed/FxEmbed)) is community-run and unaffiliated with X. Its hosted API terms and limits are UNVERIFIED.
    - **Reddit:** `.json` and RSS are reportedly blocked (finding 10), so don't build on them. Options are the approved official API, or logged-out HTML via Jina Reader, which may also be blocked by Reddit. Degrade to "link saved, text unavailable."
    - **LinkedIn:** try the logged-out public post page, and fall back to link plus the page's og:title and og:description. Jina Reader works on publicly accessible pages only. LinkedIn's terms still bar scraping even logged-out, so treat this as tolerated rather than permitted. The hiQ outcome shows the exposure for a company, though a few personal links a day is very low risk.
    - **Jina Reader:** `r.jina.ai/<url>` is free for basic use, 20 requests per minute without a key. It does not bypass anti-bot systems and respects blocks, only processes public URLs, and puts compliance with each site's terms on the caller. It caches content for 5 minutes. Setting the `DNT` header skips caching and logging ([jina.ai/reader](https://jina.ai/reader/)). It is a third party that sees every URL we send, so don't send private links.
    - **Cheapest design:** a plain fetch plus Jina, a short per-platform fallback, and Claude reading whatever text comes back. Do not hold crew cookies on the server.

## Not checked
- OpenCLI, CloakBrowser and the Chrome extension code, and whether they phone home. Third-party and out of scope for the clone.
- The live X ToS and Reddit User Agreement/Data API terms (fetch blocked). Reddit's `.json` and API availability is from vendor blogs, not Reddit's primary pages.
- Issue bodies in the repo (titles only), closed issues, and external reports of bans specific to Agent Reach or OpenCLI.
- X pay-per-use prices, fxtwitter's hosted API terms and rate limits, and Groq's free-tier limits and retention terms.
- scripts/, tests/, install paths, and how `agent-reach add` fetches and verifies binaries (supply-chain integrity).
- LinkedIn public post page behaviour logged-out (not tested; running anything was out of scope).
