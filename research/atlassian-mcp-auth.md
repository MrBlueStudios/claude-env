# atlassian-mcp-auth

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Confirmed from Atlassian's own setup page:** the v2 URL `https://mcp.atlassian.com/v2/mcp`, the exact `claude mcp add --transport http atlassian …` command, the 1 March 2027 automatic v1 → v2 cut-over, and that `getTeamworkGraphContext`, `searchAtlassian` and `search` consume Rovo credits.
>
> **Could not confirm:** Free-plan inclusion and the 500-calls-an-hour figure. Atlassian's product page at `atlassian.com/platform/rovo-mcp` does not state either; one write-up says Atlassian publishes no numbers at all, and [issue #171 on Atlassian's own MCP repo](https://github.com/atlassian/atlassian-mcp-server/issues/171) reports HTTP 429 well below 1,000 an hour with no `retry-after`. Treat the hourly figure as UNVERIFIED and the failure mode as "429, then wait".
>
> **What this changes:** nothing in the decision (Atlassian MCP stays the one base-tier exception), two things in the runbook — add an `ask` permission rule for `mcp__atlassian__*` writes, and one person must open Atlassian Administration and turn Rovo extra usage off before 3 December 2026. Both are now on Léon's queue.

---

*Owner: Almar · researched 16 Nov 2026 · web research only; nobody connected a real Jira site.*

**Question:** Can four people, each with their own Atlassian account, use Atlassian's official remote MCP server from Claude Code against one Jira Cloud board without paying?

**Answer:** No paid plan is needed — the official server works on Jira Free, each person signs in with their own account over OAuth, and it can read and write issues, comments, transitions and sprints. The one shared limit is 500 calls an hour for the whole site on Free, which four people will not reach in normal use. The thing to watch is Rovo credits: plain Jira reads and writes are free, but "enriched" search tools cost credits, Free includes none, and paid extra usage starts on 3 December 2026 — so the exception to the CLI-first rule stands, provided someone confirms extra usage is off.

**Confidence:** medium — authentication, tools and setup are from Atlassian's own pages; the Free-plan availability and the 500/hour figure are from several third-party pages quoting Atlassian's product page, which I did not open directly.

**What would change our decision:**
- If the Rovo "extra usage" setting can bill a Free site (finding 6), Jira via MCP stops being reliably free until an admin switches it off.
- If the crew grows past 10 people, Jira Free itself ends, independent of MCP.

## Findings

1. **Authentication is per user, by OAuth 2.1.** Atlassian's setup guide names OAuth 2.1 as the main method and says actions respect each user's existing access controls and permissions; API tokens are an optional alternative. So each of the four connects their own account, and what Claude can do in Jira is exactly what that person can do in the Jira web UI. Comments and edits are attributed to the person, not to a shared bot. [Atlassian: Get started with the Atlassian MCP server (official)](https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/) · [Atlassian Rovo MCP overview (official)](https://developer.atlassian.com/cloud/rovo-mcp/)

2. **API tokens are not needed, and are off by default.** They exist for headless use (CI, bots) and only work once an organisation admin enables them under Atlassian Administration → Rovo → Rovo MCP server → Authentication. For four humans in Claude Code, ignore them. [setup guide](https://agenttaskatlas.com/guides/connect-atlassian-mcp-claude-code) (third-party; admin path not checked against Atlassian's own page)

3. **It works on the Free plan.** Several independent write-ups quote Atlassian's product page as saying all Atlassian Cloud customers have access, Free included, with no separate charge. Jira Free itself covers up to 10 users. I did not open Atlassian's product page directly, so treat as UNVERIFIED against the primary source, though five sources agree. [quote of Atlassian's page](https://sharkly.ai/blog/use-jira-with-ai-agents-free/) · [second source](https://titanapps.io/blog/jira-mcp) · [third](https://www.eesel.ai/blog/claude-for-jira-service-management)

4. **Rate limit: 500 calls an hour, shared by the whole site.** On Free the limit is 500 calls per hour; Standard is 1,000; Premium and Enterprise scale up to 10,000. The limit is per site, so the four of you draw from one budget — about 125 calls an hour each if everyone works at once. A typical "read ticket, comment, transition" exchange is three to five calls, so this bites only if someone runs a bulk job (for example, walking every issue on the board). What the failure looks like is not documented beyond "rate limited". [per-plan figures](https://getunblocked.com/blog/jira-mcp/) · [per-site wording](https://agentman.ai/agentskills/connections/mcp-server/atlassian) (both third-party, quoting Atlassian)

5. **What it can read and write today.** From Atlassian's supported-tools page, both OAuth and API token sessions get the same Jira groups:
   - **Read:** get an issue, list comments, list transitions, change history, worklogs, boards, board configuration, board issue data, sprints on a board, statuses, versions, filters, dashboards, assignable users, attachments (download).
   - **Write:** create, edit and transition issues; add or edit comments; add worklogs; link issues; **create, start, update and close sprints** (`manageJiraSprint`); create boards; upload attachments; watch an issue.
   - **Search:** JQL search (`searchJiraIssuesUsingJql`).

   So all four things the brief asked about — issues, comments, transitions, sprints — are covered. Board and sprint tools are recent: older articles (mid-2026) say sprints are not available, and they are now out of date. [Atlassian: Supported tools (official)](https://developer.atlassian.com/cloud/rovo-mcp/guides/supported-tools/) · [Atlassian release note on the new Jira tools](https://community.atlassian.com/release-notes/7mCPJKISpzXzaukb9zFv0v) · [example of an outdated article](https://www.scalekit.com/blog/jira-mcp-vs-api)

6. **Known gaps and the credits question.**
   - **Delete and admin tools are off by default.** Deleting issues/comments/attachments and project/workflow administration are separate permission groups that stay disabled until an admin enables them. Good default; leave it. [Supported tools (official)](https://developer.atlassian.com/cloud/rovo-mcp/guides/supported-tools/)
   - **Enriched search costs Rovo credits.** Atlassian's setup page says enriched Teamwork Graph calls — `searchAtlassian`, `search`, `getTeamworkGraphContext` — consume Rovo credits. Plain Jira tools, including JQL search, are not listed as costing credits. [Get started (official)](https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/)
   - **Free has no credits.** The Free plan does not include Rovo, so those enriched tools have no allowance to draw on. What happens when a Free site calls one — refused, or billed — is UNVERIFIED. [Free plan and Rovo](https://sharkly.ai/blog/use-jira-with-ai-agents-free/)
   - **Extra-usage billing starts 3 December 2026 and is reported as on by default**, at $0.01 per credit, with enriched calls typically costing 1 to 10 credits each. Admins can cap or disable it. Whether this can reach a Free site with no payment method is UNVERIFIED — but it is the one way this could quietly turn paid, so an org admin should open Atlassian Administration and turn extra usage off before that date. [usage-based pricing explainer](https://titanapps.io/blog/atlassian-usage-based-pricing) · [second source for the date](https://coworker.ai/blog/jira-mcp) (third-party)

7. **Exact URL and setup for Claude Code.** From Atlassian's own guide:

   ```
   claude mcp add --transport http atlassian https://mcp.atlassian.com/v2/mcp
   ```

   Then start a Claude Code session, run `/mcp`, pick `atlassian`, and complete the browser sign-in. Add `--scope user` to have it in every project. Each of the four does this once on their own laptop. [Get started (official)](https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/)

8. **Use the v2 URL; older guides are wrong.** Many tutorials still show `https://mcp.atlassian.com/v1/sse` or `/v1/mcp/authv2`. The `/v1/sse` endpoint has been deprecated since 30 June 2026, and Atlassian's page says existing v1 usage moves to v2 tools automatically on 1 March 2027. If the flake pins a URL, pin v2. [deprecation dates](https://getunblocked.com/blog/jira-mcp/) · [Get started (official)](https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/)

9. **Relevant to `context-budget`.** Atlassian's page describes v2 as using "discovery and execute" methods with a small set of primary tools listed directly, and an optional `?tools=all` URL that exposes everything. The default URL should therefore cost far fewer start-up tokens than a server that lists all its tools. Not measured — worth a line in the context-budget item. [Get started (official)](https://support.atlassian.com/atlassian-ai-gateway/docs/get-started-with-the-atlassian-remote-mcp-server/)

10. **Permissions in Claude Code.** One guide recommends an `ask` rule for `mcp__atlassian__*` so every Jira write waits for confirmation, rather than an `allow` rule. Sensible for a shared board. [setup guide](https://agenttaskatlas.com/guides/connect-atlassian-mcp-claude-code)

## Not checked

- **A real connection.** Nobody ran the command against the actual board. Ten minutes by one person would confirm findings 3, 4 and 7.
- **Atlassian's product page and rate-limit documentation** were not opened directly; the 500/hour and "all Cloud customers" statements are quoted through third parties.
- **Whether extra usage can bill a Free site** — the single open question that matters. Check in Atlassian Administration → billing / Rovo usage.
- **First-connection admin steps.** Whether an org admin must approve Claude Code as a client the first time, or whether there is a domain allowlist to edit, is covered on a separate Atlassian page I did not read.
- **Team-managed vs company-managed projects** — whether sprint tools behave the same on both.
- **Data handling** — what Atlassian logs about MCP calls, and whether issue content passing through Claude matters for any client work tracked on the board.
