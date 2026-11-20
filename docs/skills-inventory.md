# Every skill on Léon's laptop, and which of them the crew should have

Written 2026-11-20 to make `q-personal-skills` answerable in five minutes instead of by reading 27
`SKILL.md` files. Reproduce the whole thing with one command, in any directory:

```
claude-plugins-check
```

**The numbers in that report changed today, and the earlier ones were wrong.** It called a skill
"declared by the module" only when `~/.claude/skills/<name>` was itself a symlink into
`/nix/store`. But the module declares skills in two shapes:

- `home.file.".claude/skills/X".source = ./skills/X` links the **directory** — the four vendored
  packs and the two web-design skills;
- `home.file.".claude/skills/X/SKILL.md".text = ''…''` leaves `X` a **real directory** holding a
  store symlink — every skill written inline in `skills.nix` and `modes.nix`, eleven of them.

Only the first was recognised, so eleven declared skills were reported as personal. The report now
reads the directory's link or its `SKILL.md`'s, and two tests cover both shapes. The honest
summary of the correction: **the open question is 7 skills, not 27.**

| Group | Count | Always-on cost | Status |
|---|---|---|---|
| Declared by the module | 16 | ~550 tokens | nothing to decide |
| Real directories, this machine only | 9 | ~678 tokens | all HyperFrames; personal by their nature |
| Symlinks into `~/Projects/Claude_testing/skills/` | 7 | ~445 tokens | **this is the question** |
| Directories with no `SKILL.md` of their own | 3 | 0 tokens | 13.6 MB registering nothing |

Cost is the `name` plus `description` of each skill at 4 bytes per token, which is the part that
sits in every session's context whether the skill is used or not. The body is read only on use.

## 1. Declared by the module — 16, no decision needed

`council`, `dashboard`, `deploy`, `design`, `full-visual`, `normal`, `rapid`, `research`,
`review`, `roblox`, `ship`, `thermo-nuclear-code-quality-review`, `thermo-nuclear-review`,
`thermos`, `web-design-guidelines`, `web-design-playbook`.

Five of them — `council`, `dashboard`, `normal`, `rapid`, `roblox` — come from `modes.nix` and are
behind `claude-env.modes.enable`, which is off by default, so a friend's laptop does not get them.
The four skills adopted on 19 November (`writing-for-agents`, `domain-modeling`, `grilling`,
`performance-optimization`) are declared but not on disk yet, because the switch has not run.

## 2. This machine only, and personal by their nature — 9

Every one is part of the HyperFrames video toolchain, which needs a renderer, a Remotion
install and asset accounts that exist on one laptop.

| Skill | ~tokens | What it is |
|---|---|---|
| `hyperframes` | 75 | the render contract and work loop; the entry point for the rest |
| `hyperframes-cli` | 58 | the CLI by job — scaffold, preview, render, publish |
| `hyperframes-registry` | 82 | ~450 ready-made blocks and components |
| `media-use` | 81 | music, SFX, images, voiceover, HeyGen avatars, colour grades |
| `remotion-to-hyperframes` | 86 | porting Remotion, Lottie, Three.js and After Effects work in |
| `reverse-any-video` | 75 | rebuilding an existing video as an editable project |
| `style-sampling` | 75 | a new episode in one of five proven styles |
| `slideshow` | 72 | a presented deck rather than a rendered video |
| `figma` | 75 | Figma frames, tokens and logos into a video |

**Recommendation: leave all nine personal, and say so in the repo** rather than leaving them
undeclared. They are 678 tokens in every session on this machine — more than the 16 declared ones
put together — so the one thing worth doing is deciding whether that is a fair price on a day of
Nix work. If it is not, the fix is `claude-env.modes.enable`-style gating, not deletion.

## 3. The actual question — 7 skills that link off-store

These are symlinks into `~/Projects/Claude_testing/skills/`, so they load on this laptop and break
on any other. Each is Léon's own writing.

| Skill | ~tokens | What it does | Verdict |
|---|---|---|---|
| `legal-audit` | 63 | GDPR, cookie, AI Act and accessibility audit of a site, and what still needs a lawyer | **crew** — client work, and the one thing a friend cannot improvise |
| `security-audit` | 68 | secrets, CVEs, site and Roblox-exploit checks, plus what a scan may point at | **crew** — same reason |
| `site-analytics` | 60 | traffic and visitor numbers for the Blitsol domains | **crew, but it names three domains** |
| `design-review` | 70 | several design variants side by side, annotated in the browser | **crew** — overlaps `design`; worth merging rather than adding |
| `project-status` | 56 | the status board shape these two HTML boards are built from | personal — it is how Léon reports, not how the crew works |
| `my-todo` | 60 | the todo-board shape, writing to `~/project-brain/Inbox/` | personal — that path is one vault on one laptop |
| `prompt-optimizer` | 68 | which skill, MCP tool or CLI actually fits a task on *this* machine | personal — its value is being machine-specific |

**Three facts that decide how, not whether.**

1. `~/Projects/Claude_testing` is a git repo whose remote is
   **`MrBlueStudios/claude-lab`, and it is private**. A `flake = false` input pointing at a private
   repo makes `claude-env` unbuildable for anyone without access, so the `claude-web-stack` pattern
   does not transfer as-is.
2. The local checkout is **8 commits ahead of that remote and on a detached HEAD**, and one of the
   seven — `legal-audit` — has been edited since the last push. The current version of a skill the
   crew would depend on exists nowhere but this laptop.
3. `claude-env` is **public**. Vendoring `site-analytics` publishes `blitsol.com`, `blitsol.nl` and
   `blitsolhq.com` as the domains being measured. That is not a secret, but it is a choice.

**Recommendation: vendor four, keep three.** Vendor `legal-audit`, `security-audit`,
`design-review` and `site-analytics` into `modules/home/skills/`, the same way the four adopted
skills landed, with `site-analytics` edited to take its domains from an option rather than
hard-coding them. Leave `project-status`, `my-todo` and `prompt-optimizer` personal and declare
them as personal. That is ~261 tokens added to every crew session and ~184 kept on this laptop,
and it needs no new repo and no private input.

The alternative worth naming: split those four into their own small **public** repo and pin it as
an input, which is cleaner if the set grows past a handful and is the only option that keeps one
copy of each skill. It costs a repo to maintain and a push whenever a skill changes, which is
exactly the thing the detached HEAD above suggests does not reliably happen.

## 4. Registering nothing — 3 directories, 13.6 MB

A skill registers only when `SKILL.md` sits **directly** inside `~/.claude/skills/<name>/`. These
three hold their skills one level deeper, in `<name>/skills/<skill>/SKILL.md`, so Claude Code has
never loaded any of them.

| Directory | Size | Holds | What to do |
|---|---|---|---|
| `anthropic-skills` | 12.6 MB | 17 of Anthropic's own skills plus a template — `pdf`, `docx`, `xlsx`, `pptx`, `mcp-builder`, `skill-creator`, `frontend-design`… | **delete.** `frontend-design` is already an enabled plugin, and the account pushes 38 more plugins and 331 skills under `plugins/synced/`. Its repo also carries only `THIRD_PARTY_NOTICES.md`, so vendoring it into a public repo is not clean. |
| `superpowers` | 0.9 MB | 14 superpowers skills | **delete.** A second copy of a plugin that is installed, enabled and pinned. Nothing reads it. |
| `obsidian-skills` | 0.1 MB | `defuddle`, `json-canvas`, `obsidian-bases`, `obsidian-cli`, `obsidian-markdown` | **wire up, selectively.** Not a duplicate of anything, and two are directly useful: `defuddle` is the reason the Firecrawl server was dropped, and `obsidian-bases` is one of the three candidates for crew-memory's parked dashboard question. |

Deleting the first two recovers 13.5 MB and changes nothing in context, because none of it was
loading. Separately, `claude-plugins-check` reports 20.6 MB of marketplace caches from the ponytail
and cursor-plugins uninstalls and 7.9 MB in Claude Code's own `.trash`, which are also free to
remove.

## What this does not answer

Whether the 678 tokens of HyperFrames descriptions are worth paying on a day of Nix work. That is
a measurement question — `research/context-budget.md` has the method — and Léon's standing
decision is to measure and report rather than cap, so it is reported here and not acted on.
