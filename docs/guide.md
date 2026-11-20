# The crew Claude Code environment: a guide for the person joining

You are getting the same Claude Code setup Léon runs, as a flake. This is what is in it, how to
install it, and what the first hour looks like.

Every command below says which directory to run it in. Where it says **your config**, that means
your own NixOS configuration — `/etc/nixos` on most machines, or wherever your flake lives.

---

## 1. Install

### What you need first

- NixOS with flakes and home-manager. Release 25.05 or 26.05 both work.
- Claude Code itself, from nixpkgs. This flake does not install it: it configures it.
- A Claude account you are signed in to (`claude` once, interactively).

The two releases are not identical. On 26.05 you get `playwright-mcp`, `mcp-nixos` and
`repomix 1.15.0` from nixpkgs; on 25.05 those first two fall back to a pinned npm fetch and
repomix is 0.3.3, which has neither of its token-counting flags. Nothing breaks on 25.05, and
26.05 is the better place to be.

### Add the flake

**Run in: your config**

```nix
# flake.nix
inputs.claude-env.url = "github:MrBlueStudios/claude-env";
```

```nix
# your home-manager module
{ inputs, ... }:
{
  imports = [ inputs.claude-env.homeManagerModules.default ];

  claude-env.user.name = "Kish";   # how Claude addresses you in ~/.claude/CLAUDE.md
  claude-env.tier = "base";        # see §2
  claude-env.user.notes = ''
    - Home directory: /home/kish
    - Lenovo Legion, KDE Plasma
  '';
}
```

```nix
# your NixOS module — the guardrails (§5). Separate from the home module on purpose:
# a managed policy has to be written by root to be a policy at all.
{ inputs, ... }:
{
  imports = [ inputs.claude-env.nixosModules.default ];
}
```

**Import both.** The home module on its own gives you the tools with none of the brakes: every
skill, agent and MCP server, and nothing stopping a `.env` read or an `rm -rf` of your home
directory. If you only want to try the tools on a machine you do not administer, that is a
reason to take the home module alone — but know that is what you are choosing, and say so, so
nobody assumes your sessions are guarded when they are not.

**Run in: your config**

```bash
nh os switch .
```

### Check it took

**Run in: anywhere**

```bash
claude mcp list              # context7, atlassian, playwright — all connected
claude plugin list           # superpowers, brag, svelte, frontend-design — all enabled
claude-plugins-check         # "no drift": what is installed matches what the repo declares
ls ~/.claude/skills          # links into /nix/store, not real directories
```

If `claude mcp list` is empty, you have not started Claude Code yet on this machine. The module
writes into `~/.claude.json`, which Claude Code creates on first run; start `claude` once, then
switch again.

---

## 2. The two tiers

`claude-env.tier` is one option with two values, and it decides exactly one thing: whether you
get the company server on top of the shared toolkit.

| | `base` (the default) | `blitsol` |
|---|---|---|
| Everything in §3 and §4 | yes | yes |
| `cloudflare` MCP server | no | yes, with your own OAuth login |
| HubSpot and Stripe connectors | no | by invite, in claude.ai — not from the flake |
| Shared Blitsol secrets | no | after [enrolment](./enrolment.md) |

Set `blitsol` only if you are actually doing Blitsol client work. It is cheap to grant later and
expensive to take back, because taking it back means re-keying secrets and removing account
invites one by one.

Nothing in the `blitsol` tier contains a credential of anyone else's. `cloudflare` authenticates
as you, and the connectors are invitations to real accounts you then log into yourself. If
someone offers you a copy of a token instead, that is the wrong path — say so.

### Opt-in modules

Six MCP servers are off for everybody until you turn them on, because every enabled server's
tool list costs tokens in every session whether you use it or not:

```nix
claude-env.mcp.modules.nix = true;        # NixOS options and packages
claude-env.mcp.modules.legal = true;      # EU regulations lookup
claude-env.mcp.modules.trading = true;    # CoinGecko market data
claude-env.mcp.modules.seo = true;        # Google Search Console (needs your own Cloud project)
claude-env.mcp.modules.sentry = true;     # 1,089 tokens — the most expensive one measured
claude-env.mcp.modules.firecrawl = true;  # web scrape/crawl, needs your own key via agenix
```

Turn one on when a project needs it; turn it off when that project is done. `sentry` is worth
singling out: it costs more than every other server put together, so enable it in the week you
are chasing a production error and not as a habit.

---

## 3. What is in the box

### MCP servers

| Server | Tier | What it is for | Why not a CLI |
|---|---|---|---|
| `context7` | base | Current docs for libraries and frameworks | There is no CLI for "what does Svelte 5 say about runes today" |
| `atlassian` | base | Jira and Confluence on the shared site | Writes to the shared board are worth a prompt (§5) |
| `playwright` | base | Driving a real browser: screenshots, clicks, console | The design skills need a page, not a description of one |
| `cloudflare` | blitsol | Everything `wrangler` does not: DNS, Workers, R2, D1 | `wrangler` covers deploys; this covers the rest |

**The ones deliberately absent matter as much.** There is no GitHub server, because `gh --json
--jq` is cheaper and already authenticated. No filesystem server, because the built-in file tools
are better and it could not see `~/Projects` anyway. No memory server, because the crew keeps one
memory system and it is file-based. Twenty-three registrations were dropped for reasons like
these; `docs/mcp-audit.md` has one line per server.

### CLIs you now have

These are on your PATH and cost nothing until you run them, which is why they are CLIs:

| Command | What it does |
|---|---|
| `claude-artifacts` | Index of every file Claude has written on this machine, searchable |
| `claude-artifacts-pick` | Fuzzy-pick one of those files, preview it, open it |
| `claude-vet` | What a plugin or skill tree would bring onto your machine, *before* you install it (§6) |
| `claude-plugins-check` | Where your machine has drifted from what the repo declares |
| `compliance-scan` | Legal red flags on a website: cookie banners, privacy text, tracking |
| `playwright-cli` | Browser automation whose output goes to `./.playwright-cli/` instead of your context |
| `repomix` | Measure what is expensive in a repo, and scan it for credentials before sharing |
| `hyperframes` | HTML → MP4, the renderer `/brag` drives |

### Skills

Typed as `/name` in a session. These are the crew's own:

| Skill | What it does |
|---|---|
| `/ship` | Lint, test, commit, push, open a PR |
| `/review` | Deep review of staged changes or a PR, with security, GDPR and stack checks |
| `/deploy` | Deploy a project to the Blitsol Contabo server |
| `/research` | Web search plus library docs plus the local codebase, reported with sources |
| `/design` | Design iteration validated in a real browser |
| `/full-visual` | Explain a thing as a full-screen interactive page instead of paragraphs |

Plus `web-design-playbook` and `web-design-guidelines` (the stack's own SvelteKit, Tailwind and
WCAG rules), three `thermo-nuclear` review skills, and four vendored from other people's MIT
packs: `writing-for-agents`, `domain-modeling`, `grilling`, `performance-optimization`.

If you run Kitty, `claude-env.modes.enable = true` adds five terminal-layout skills —
`/dashboard`, `/council`, `/rapid`, `/roblox` and `/normal` to collapse them. They do nothing
useful in another terminal, which is why they are opt-in.

### Agents

Claude hands work to these itself; you can also ask for one by name.

`frontend` (Svelte 5), `backend` (FastAPI and SQLite), `nixadmin`, `reviewer` (read-only,
security-focused), `researcher`, `doc-writer`, and two thermo-nuclear review subagents.

### Plugins

Four, pinned in the flake: `superpowers` (the process skills Claude uses most), `brag` (turns a
project into a launch video), `svelte` (the Svelte team's own docs server and file editor), and
`frontend-design`. You do not install these; they arrive with the switch.

`/plugin` will show you many more than four, and that is not drift. Your claude.ai account
downloads Anthropic's own plugin marketplaces onto the machine — on Léon's laptop that is 38
plugins, 331 skills and 17 MB under `~/.claude/plugins/synced/`, from `knowledge-work-plugins`,
`claude-for-legal` and four others. They sit there **offered rather than installed**, which is
the distinction that matters: a skill costs tokens in every session only once its plugin is
enabled, and none of these is. No flake can declare or remove them, because that is account
state rather than machine state. `claude-plugins-check` counts them in a section of their own so
the number is not a mystery, and turns it into a finding if one ever flips to installed.

### Hooks

Three, and it is worth knowing what runs without being asked:

- **after every edit** — `prettier` runs, but only if the project has a prettier config.
- **after every edit, in the background** — the file is recorded in your artifact index.
- **when Claude stops** — a desktop notification.

Nothing runs at session start, and nothing runs on your prompts. That is a deliberate line: a
hook on `SessionStart` or `UserPromptSubmit` sees everything you type, so the flake does not
have one and `claude-vet` blocks adding one without a written reason (§6).

---

## 4. Your own machine, your own additions

The repo owns `enabledPlugins`, `extraKnownMarketplaces` and the user-scope `mcpServers` block.
Anything you add by hand with `claude plugin install` or `claude mcp add` is removed at your next
switch — and named on the way out, with MCP servers saved to
`~/.claude/removed-mcp-servers.json` so you can get them back.

This is the point rather than a side effect: it is how four laptops stay the same. To keep
something, declare it.

**Run in: your config**

```nix
# a plugin only you want
claude-env.plugins.personal."my-plugin@my-marketplace" = true;
claude-env.plugins.personalMarketplaces.my-marketplace = {
  repo = "someone/their-plugins";
  rev = null;   # or a full 40-character commit SHA to pin it
};

# an MCP server only you want
claude-env.mcp.personal.obsidian = {
  type = "stdio";
  command = "npx";
  args = [ "-y" "@bitbonsai/mcpvault" "/home/you/Obsidian/Vault" ];
};
```

Never put a secret in `claude-env.mcp.personal`. It lands in the Nix store, which is
world-readable on your machine. Read the key from agenix in a wrapper instead — the `firecrawl`
module is the worked example.

If something the crew would all use ends up in your personal block, that is a signal: say so, and
it moves into the flake for everyone.

---

## 5. The guardrails

Two layers, and neither is advisory.

### Deny: the command never runs

A PreToolUse hook, delivered as a NixOS managed policy, so no project setting and no "don't ask
again" can switch it off. It stops:

- Reading `.env`, `.env.local`, `.env.production`, anything under `/run/agenix`, and your SSH
  private keys — through the file tools *and* through `cat`, `grep` or `cp` in a shell.
- `rm -rf` of `/`, your home directory, or a system directory.
- Piping a download into a shell (`curl … | sh`), and running a downloaded script.
- `mkfs`, `dd of=/dev/…`, a fork bomb, `chmod -R 777 /`.
- Force-pushing to `main` or `master`.

### Ask: you get a prompt

- Activating a new NixOS generation (`nh os switch`, `nixos-rebuild switch`).
- Force-pushing anywhere else.
- A recursive `rm` that is outside the current project, built from a variable, or contains `..`.
- Every Atlassian **write**: creating or editing an issue, transitioning one, commenting,
  editing a Confluence page. Reads stay silent, because everyone touches the board daily. Writes
  land in front of the whole crew, so they are worth one keystroke of confirmation.

If the guard blocks something legitimate, **say so and ask** — do not work around it. A rule that
gets bypassed is worse than no rule, because everyone still believes it is there. The rules are
`modules/system/claude-code/guard.sh` and they have 58 tests; if one is wrong, it is a pull
request, not a local exception.

---

## 6. Before you install anything new

`claude-vet` looks at a plugin or skill tree before any of its code runs. It reports who wrote
it, under what licence, which hooks it declares and on which events, every place it spawns a
process or reaches the network, every environment variable it reads, and the tokens it would
cost in every session from then on.

**Run in: anywhere**

```bash
git clone --depth 1 https://github.com/someone/their-plugin /tmp/vet-me
claude-vet /tmp/vet-me
```

It exits non-zero on a hook bound to `SessionStart`, `UserPromptSubmit` or `SubagentStart` —
the three that run without you asking — unless there is a written exemption with a reason in
`docs/vet-exemptions.md`. Two things worth knowing about the output:

- **The star count is not evidence.** Several of the most-starred Claude Code repos have
  fork-to-star ratios well below what organic projects show, and AI tooling is the largest
  recipient category in the published research on purchased stars. Read the code.
- **A long list of outbound hosts is usually harmless** — it is a brand or icon table. A short
  list with one host you do not recognise is the one to look at.

---

## 7. The first hour

Do these in order. Each one proves a different part works.

**1. Say hello, and look at what loaded.**

**Run in: any project directory**

```bash
claude
```

Then `/status` in the session. The `Setting sources` line should name your user settings and the
managed policy. If the managed policy is missing, the NixOS module is not imported.

**2. Ask it something about your own code.** Anything real. Watch where it looks: it should reach
for `rg` and the file tools, not for a server.

**3. Prove a hook fires.** Edit a file through Claude in a project that has a `.prettierrc`. The
file comes back formatted, and the edit appears in your artifact index:

**Run in: anywhere**

```bash
claude-artifacts | head
```

**4. Prove the guard bites.** In a session, ask Claude to read a `.env` file in a project that
has one. It gets denied, and tells you why. That is the whole demonstration: the policy is not a
document, it is a running hook.

**5. Try a skill end to end.** `/review` on a branch with staged changes is the most useful
first one, because it shows you the house style on security, GDPR and the stack conventions in
one pass.

**6. Look at the board.** `docs/project-state.yaml` in this repo is the source of truth for what
is built, what is next and what is still an open question. The two rendered views are linked from
its `artifacts:` block.

**7. Read `~/.claude/CLAUDE.md`.** It is generated from your `claude-env.user.*` settings plus
the crew conventions, and it is what Claude reads at the start of every session in every project.
If a convention in there is wrong for you, that is a conversation, not a local edit — the file is
regenerated on every switch, so a hand edit disappears.

---

## 8. When something is wrong

| Symptom | Almost always |
|---|---|
| `claude mcp list` is empty | Claude Code has never run on this machine; start it once and switch again |
| A server is listed but will not connect | Its key is missing or expired. `firecrawl` says so at startup; OAuth ones need a browser login |
| A plugin vanished after a switch | It was installed by hand and not declared (§4) |
| A skill vanished after a switch | Same, for `~/.claude/skills`. `claude-plugins-check` names them |
| A marketplace is not on its declared commit | Your Claude Code is older than 2.1.324, which is the first version that can load a commit pin. The switch says so. `nix flake update` |
| Hand-edited `~/.claude/CLAUDE.md` or `settings.json` keys reverted | Both are generated. Change them in your config |
| The guard blocked something reasonable | Ask. Do not route around it (§5) |

For anything else, `claude doctor` reports what Claude Code itself rejected, and `/status`
reports what it loaded.

---

## 9. The house rules

Four, and they are the ones that actually come up:

1. **English in the repos.** Code, comments, commit messages, CLI output, notifications. Dutch
   only in copy that ships to a Dutch customer, and only when it was asked for.
2. **Prefer a CLI to an MCP server** when the CLI does the job. `gh --json --jq`, `rg`, `fd`,
   `jq`, `sqlite-utils`, `nix search`, `just`. Ask for compact output rather than full dumps.
3. **`just test` before committing.** Never commit failing tests. Conventional commit prefixes:
   `feat`, `fix`, `chore`, `docs`.
4. **Nothing personal in the flake.** Your name, your machine and any company credential stay in
   your own config or in agenix. The flake is a public repo.
