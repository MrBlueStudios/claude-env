# context-budget

**Question:** What does Léon's Claude Code environment cost in tokens at session start, which items are the expensive ones, and what would pruning save?

**Answer:** About 28,500 tokens before the first word is typed, measured by running one-shot sessions and reading the usage report; MCP servers account for only about 5,600 of that, because Claude Code lists their tool names and defers the schemas until a tool is needed. The ten most expensive items are not servers at all but the fixed system prompt plus the 124 skill descriptions (about 6,900 tokens); the servers marked for pruning save about 520 tokens together and the HyperFrames suite about 320. Prune for security and clarity, not for context.

**Confidence:** high for the totals (measured, not estimated); medium for the attribution to skills, which is a 4-characters-per-token estimate of the frontmatter.

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

## Not checked

- Individual cost of each claude.ai connector; they are account-level and cannot be toggled per run.
- Interactive sessions versus `-p` mode; the start-up context may differ slightly (status line, hooks output). The `/context` command in an interactive session shows the same breakdown and is the easy cross-check.
- Token cost of skills that are *invoked* (their full body), which is per use, not per session.
- Whether skill descriptions are counted exactly or truncated by Claude Code; the 4-chars-per-token figure is an upper bound.
