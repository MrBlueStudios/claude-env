# context-budget

**Question:** What does Léon's Claude Code environment cost in tokens at session start, which items are the expensive ones, and what would pruning save?

**Answer:** About 28,500 tokens before the first word is typed, measured by running one-shot sessions and reading the usage report; MCP servers account for only about 5,600 of that, because Claude Code lists their tool names and defers the schemas until a tool is needed. The ten most expensive items are not servers at all but the fixed system prompt plus the 124 skill descriptions (about 6,900 tokens); the servers marked for pruning save about 520 tokens together and the HyperFrames suite about 320. Prune for security and clarity, not for context.

**Re-measured 20 November 2026** (same method): **27,344 tokens with every server connected, 22,263 with none**, so the MCP share is 5,081 — one more server than on 19 November, and still nothing from the flake, because none of it is live yet (finding 14). On 19 November it was 26,825 and 22,155, a share of 4,670. Two things that were estimated on 16 November are now measured: tool deferral is real, and a skill costs about 64 tokens. One thing that was assumed is wrong — see finding 11, where two plugins counted in the 124 turned out never to have been enabled.

**Confidence:** high for the totals and, since 19 November, high for the per-skill cost too (finding 10 measures it instead of estimating it).

**What would change our decision:**
- A future Claude Code version that stops deferring MCP tool schemas. Then every server's full tool list lands in context and Sentry alone (70-odd tools) would cost several thousand tokens; re-measure after major updates.
- Skills growing past a few hundred. At roughly 55 tokens per skill description, 300 skills would cost 16k tokens, and tiering them becomes worth it.

## Findings

1. **Total at session start: 28,503 tokens with every server connected, 22,857 with none.** Measured with `claude -p "Reply with the single word ok." --output-format json` on Haiku, reading `usage.input_tokens + cache_creation_input_tokens + cache_read_input_tokens` of the first turn; the "none" run used `--strict-mcp-config --mcp-config '{"mcpServers":{}}'`. Difference attributable to MCP: 5,646 tokens, about 20 % of the start-up context. Source: local measurement, 16 November 2026; scripts in the session scratchpad.

2. **Per user-scope server, measured one at a time** (same method, each server alone, baseline 22,857):

   | server | extra tokens |
   |---|---|
   | sentry | 1,089 |
   | github | 274 |
   | playwright | 254 |
   | context7 | 239 |
   | obsidian | 214 |
   | filesystem | 140 |
   | memory | 107 |
   | vies-vat | 67 |
   | cloudflare | 63 |

   Sum 2,447; the remaining ~3,200 of the MCP share is the twelve claude.ai connectors (HubSpot, Stripe, Gmail, Calendar, Drive, QuickBooks, Clay, Excalidraw, GoDaddy, Claude Docs, Cloudflare Developer Platform, Indeed) and the Svelte plugin, which cannot be switched off from the command line and were not measured individually. Source: local measurement.

3. **Why servers are cheap: tool deferral.** Claude Code presents MCP tools as a list of names and loads a schema only on first use (the `ToolSearch` mechanism). The cost of a server is therefore roughly its name list plus its instructions block; Sentry is the outlier because it ships a long instructions text and about 70 tool names. Source: observed in this session's own context; Claude Code documentation on tool search — UNVERIFIED against the docs page, which was not opened.

4. **Skills: 124 installed, about 6,900 tokens of descriptions.** Counted from `SKILL.md` frontmatter (`name` + `description`) across `~/.claude/skills` and the plugin caches, 27,750 bytes at 4 characters per token. The ten largest descriptions (pstack's formal-verification and `why` skills, brag-slim, superpowers' diagnosing skill, two HyperFrames skills) are 350–520 bytes each, so no single skill matters; the count does. Source: local count; the 4-chars-per-token rule is an estimate, as the prompt allowed.

5. **Agents and instructions are small.** Eight agents, about 320 tokens of descriptions; the global `CLAUDE.md` is 1,770 bytes (about 440 tokens); this repository has no `CLAUDE.md`. Source: local count.

6. **What pruning saves.** Removing `github`, `filesystem` and `memory` (the CLI-first decision): about 520 tokens. Removing the four HyperFrames skills: about 320 tokens. Removing the deprecated Cloudflare Developer Platform connector: not measurable individually, likely a few hundred. None of these moves the 28.5k total by more than 3 %. Source: findings 2 and 4.

7. **The fixed cost is the system prompt.** With no MCP at all the session still starts at 22,857 tokens: Claude Code's own instructions, the tool definitions for its built-in tools, the skills list, memory index, and the user's `CLAUDE.md`. This is the same for every crew member with the same skills installed and cannot be tiered away. Source: finding 1.

8. **Where the base / opt-in line should fall, then.** Not on tokens. Base tier: whatever is useful on every project and holds no Blitsol secret (Context7, Playwright from nixpkgs, Svelte, Atlassian). Opt-in: anything with a paid cliff or a client-specific credential (Figma, ElevenLabs, Firecrawl keyed, Sentry per project, HyperFrames). The context cost of being generous with the base tier is a few hundred tokens.

9. **Deferral is confirmed, not inferred (19 November).** All servers together cost 4,670 tokens while QuickBooks alone exposes about 100 tools, Sentry about 70 and HubSpot about 45. Inlined schemas for those three would be tens of thousands of tokens on their own, so the schemas are demonstrably not in the prompt. This settles a claim made during the 40-repo review that per-project server scoping is the biggest lever available: it is not, because the thing it would save is not being paid. Re-check after major Claude Code updates, as finding 3 already said. Source: local measurement.

10. **A skill costs about 64 tokens, measured.** Disabling the superpowers plugin (15 skills) moved a no-MCP session from 22,155 to 21,192, a 963-token drop; re-enabling restored it. That is 64 tokens per skill against the 55 the 4-characters-per-token estimate predicted, so finding 4's method was sound and its total was slightly low. Source: local A/B, each arm one `claude -p` run.

11. **Installed is not enabled, and two plugins were only ever installed.** `ponytail` and `pstack` were installed on 5 November and never appeared in `enabledPlugins`, so neither was ever live. Three independent checks agree: removing both moved session start by zero tokens, on the same day that removing superpowers moved it by 963; no pstack skill fired in any of the 580 transcripts on this machine; and ponytail's ledger (`~/.config/ponytail/`, default on, written by a `UserPromptSubmit` hook) was never created, which it would have been on the first prompt of any session where its hooks ran. So the 124 skills in finding 4 included 64 that were never in context, and pstack's 58 skills never cost the ~4,800 tokens `claude plugin details` projects for them. Both were removed on 19 November anyway — dead weight, and ponytail was one settings edit from a live prompt-exfiltration path. Source: local measurement and transcript count.

12. **The claude.ai-synced plugins are large and free here.** 38 plugins sync from the claude.ai account (small-business 44 skills, sales 36, brightdata 21, a 90-skill legal suite, ~328 `SKILL.md` files in total), but `claude plugin list` reports "sync is off in this shell; these load only in a synced session" and a one-shot CLI session enumerates 75 skills with none of them present. They cost nothing in Claude Code on this machine. They would cost in a synced session (claude.ai, Claude Tag), where at 64 tokens each they would be roughly 21,000 tokens — worth knowing before anyone works there, but not a CLI problem and not something the flake can control. Source: local inventory and skill enumeration.

13. **Before and after the 40-repo adoption round (19 November).** Before: 26,825 with MCP,
    22,155 without. Removing ponytail and pstack changed neither, for the reason in finding 11.
    Four skills were then vendored in (`writing-for-agents`, `domain-modeling`, `grilling`,
    `performance-optimization`), which at the measured rate is **+256 tokens**, about 1 % of
    session start — confirm against a fresh measurement after the next `nixos-rebuild switch`,
    since nothing declared in the flake is live until then. What was turned down matters more
    than what was taken: the two packs those four came from hold 39 and 26 skills, so taking
    either whole would have cost ~2,500 or ~1,700 tokens for skills that largely duplicate
    superpowers. Léon's rule for this round was measure and report, not cap, and 1 % needs no
    decision from him. Source: local measurement plus the per-skill rate in finding 10.

14. **20 November, same method: 27,344 with every server connected, 22,263 with none.** The MCP
    share is 5,081, up 411 from 19 November, and the no-MCP arm moved 108, which is inside the
    noise of a changing `CLAUDE.md`. The 411 is one more server: user scope now holds ten
    registrations rather than nine. Nothing that landed in the flake on 20 November is in either
    number, because none of it is live — `/etc/nixos` is still locked to a commit from before the
    tier split, the declarative MCP block and the plugin channel. So this is the **before** figure
    for that switch, and the honest "after" is one `claude -p` run once it has happened. Deferral
    still holds: five thousand tokens for ten servers plus twelve connectors is not a prompt
    carrying their schemas. Source: local measurement, same command as finding 1.

    What to expect from the switch, as a prediction worth checking rather than a claim: the
    declared set is smaller than the live one (three at base tier, four on this laptop, plus
    whatever is declared as personal), so the MCP share should fall by a few hundred tokens,
    while the skills total rises by the 256 of finding 13. A move of more than about 10 % either
    way means something unintended landed, and is worth reading the activation output for.

## Not checked

- Individual cost of each claude.ai connector; they are account-level and cannot be toggled per run.
- Interactive sessions versus `-p` mode; the start-up context may differ slightly (status line, hooks output). The `/context` command in an interactive session shows the same breakdown and is the easy cross-check.
- Token cost of skills that are *invoked* (their full body), which is per use, not per session.
- Whether skill descriptions are counted exactly or truncated by Claude Code; the 4-chars-per-token figure is an upper bound.
