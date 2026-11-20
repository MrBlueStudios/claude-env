# Research track — claude-env and crew-memory

Sixteen questions that need looking up rather than deciding. Each one is self-contained: a friend
can paste its prompt into their own Claude — any model — and come back with a result Léon can act
on without a follow-up call. Owners are **suggestions**; Léon reassigns.

Updated 2026-11-15 after the hardware inventory and the account/key collection.

## The constraint on every item

**Free to use.** The only things the crew pays for are Claude subscriptions and things bought
deliberately for production — a domain, a VPS. A free tier that quietly turns paid at four people
is a finding, not a footnote. Everyone is on NixOS; two on 26.05 with KDE Plasma, Léon on 25.05
with Hyprland, Almar unknown.

## How to run one

1. Paste the item's prompt into your Claude. Add nothing else; the prompt carries the context.
2. Let it research. If it can search the web, good; if not, it should say what it could not check.
3. Make it use the deliverable format below. The format is what lets Léon merge sixteen answers
   from four people without re-reading sixteen essays.
4. Save as `<slug>.md` and send it to Léon. Once the `claude-env` repo exists, it goes in
   `research/<slug>.md` and the box below gets ticked.

### Deliverable format — paste this at the end of every prompt

```
Write the result in this exact shape:
# <slug>
**Question:** one sentence.
**Answer:** at most three sentences. Lead with the conclusion.
**Confidence:** high / medium / low, and why in one clause.
**What would change our decision:** one or two bullets.
## Findings
Numbered. Each finding gets its source as a link. Anything you could not verify
is marked UNVERIFIED in capitals. Prefer official documentation over blog posts.
## Not checked
What you did not look at and why.
```

---

## A. Blocks the flake — do these first

- [x] **nixos-version-matrix** — *Léon*
  Decides: whether the flake can ship one module for everyone, and whether Léon upgrades.
  Found by: the inventory. Léon is on NixOS 25.05, Ryan and Kish on 26.05.
  > We are four people on NixOS sharing one flake that exposes a home-manager module and a NixOS
  > module. One of us runs NixOS 25.05 with home-manager release-25.05; two run 26.05. Find out:
  > (1) whether a home-manager module written against release-25.05 is expected to evaluate
  > unchanged on release-26.05, and what typically breaks (renamed options, removed options,
  > stateVersion assumptions); (2) the recommended way for a shared flake to avoid pinning its
  > own home-manager — e.g. exposing only modules and letting each consumer's `inputs.*.follows`
  > supply nixpkgs and home-manager; (3) whether home-manager emits a warning or error when its
  > release does not match the consumer's nixpkgs release, and what the warning says; (4) the
  > practical cost for the 25.05 user of moving to 26.05. Constraint: free, NixOS only.
  > [paste the deliverable format]

- [x] **desktop-neutral-module** — *Kish*
  Decides: which parts of Léon's config must be stripped or guarded before the module ships.
  Found by: the inventory. Two of four run KDE Plasma on Wayland, Léon runs Hyprland.
  > A home-manager module built on a Hyprland + Kitty machine is about to be installed on KDE
  > Plasma 6 (Wayland) machines running NixOS 26.05. The module installs Claude Code hooks that
  > call `notify-send` from libnotify, a status-line script, and small CLI tools. Find out:
  > (1) whether `notify-send` from libnotify shows notifications correctly under KDE Plasma 6
  > Wayland without extra configuration, and what differs from Hyprland (icons, urgency, actions);
  > (2) which common home-manager assumptions break when moving from a tiling compositor to
  > Plasma — clipboard tools (wl-copy), terminal detection, `$TERMINAL`, XDG portals; (3) whether
  > anything in a typical Claude Code home-manager setup needs a Plasma-specific guard. Produce a
  > checklist a maintainer can run against the module. Constraint: free, NixOS only.
  > [paste the deliverable format]

- [x] **flake-pinning-strategy** — *Ryan*
  Decides: how four laptops stay on one revision without drifting, and whether a shared cache is worth it.
  > Four NixOS laptops will consume one shared flake (`github:MrBlueStudios/claude-env`) that
  > exposes a home-manager module and a NixOS module. Find out: (1) the trade-off between pinning
  > the input's rev and following a branch, for people who rebuild at different times; (2) a sane
  > update cadence and how the maintainer signals "update now" without a chat message — flake
  > registry, a tag, a release branch; (3) whether a free binary cache (Cachix free tier or an
  > alternative) is worth setting up so four people do not rebuild the same closure, including
  > its current free limits and whether a public cache is acceptable for a flake with no
  > secrets; (4) how consumers detect that they are behind. Constraint: free.
  > [paste the deliverable format]

- [x] **agenix-multi-recipient** — *Léon*
  Decides: the shape of the enrolment runbook, and whether revocation really revokes.
  > We use agenix on NixOS. A private secrets repo will hold shared company credentials
  > encrypted to four people's SSH ed25519 public keys, each on their own laptop. Find out:
  > (1) the exact workflow to add a fifth recipient to existing `.age` files — which command
  > re-keys, whether every secret must be re-encrypted, and what the maintainer needs locally to
  > do it; (2) the workflow to remove a person, and whether removal protects against someone who
  > already pulled the old ciphertext (it should not — confirm what rotation is then needed);
  > (3) what fails, and how it looks, when one recipient key is malformed or has a line break;
  > (4) whether user SSH keys and host SSH keys can both be recipients of the same file, and the
  > caveat about `age1` vs raw `ssh-ed25519` recipients. Constraint: free, NixOS only.
  > [paste the deliverable format]

- [x] **atlassian-mcp-auth** — *Almar*
  Decides: whether Jira stays an MCP server at base tier, or reopens. This is our one exception to
  a CLI-first rule, so if it needs a paid plan the exception falls.
  > Four people share one Jira Cloud board, each with their own Atlassian account. We want to use
  > Atlassian's official remote MCP server from Claude Code. Find out: (1) how it authenticates —
  > per-user OAuth, an API token, or something workspace-level — and whether each of four people
  > can connect their own account to the same board; (2) whether it requires a paid Jira plan or
  > works on the Free plan, and any user-count limits that matter at four people; (3) what it can
  > read and write today — issues, comments, transitions, sprints — and known gaps; (4) rate
  > limits that would bite with four people using it daily. Give the exact URL and setup steps
  > for Claude Code. Constraint: free; if it needs a paid plan, say so in the first sentence.
  > [paste the deliverable format]

- [x] **mcp-free-tiers** — *Kish*
  Decides: which servers survive the audit, and which are quietly paid at four people.
  > We are four developers who will each run the same set of MCP servers from Claude Code, each
  > with their own account. For each of these, find the current free allowance, whether it is per
  > account or per workspace, what happens when it is hit, and whether four people doing daily
  > web work would hit it: firecrawl, elevenlabs, context7, figma (developer MCP), google search
  > console MCP, coingecko MCP, playwright MCP (local, should be free — confirm nothing phones
  > home), the official Svelte MCP. Produce one table: server → free limit → per account or
  > workspace → what happens at the limit → risk at four people (low / medium / high).
  > Constraint: free.
  > [paste the deliverable format]

- [x] **context-budget** — *Claude, in Léon's environment*
  Decides: where the base / opt-in line falls, with numbers instead of intuition.
  > Measure, on this machine, what the Claude Code environment costs in tokens at session start:
  > the descriptions of all installed skills, the tool lists of every connected MCP server, and
  > the agents. Use `claude mcp list` for servers, `~/.claude/skills/*/SKILL.md` frontmatter for
  > skills, and a tokenizer estimate (4 chars ≈ 1 token is acceptable, say so). Produce: total
  > tokens at startup, the ten most expensive items, and what the total becomes if the HyperFrames
  > video suite and the servers marked for pruning are removed. Local measurement only.
  > [paste the deliverable format]

## B. Decides the models

- [x] **clm-hosting-reality** — *Léon*
  Decides: whether CLM exists in this environment at all.
  Found by: the inventory. CLM-8B's bf16 encoder needs ~16 GB VRAM (clm-mcp-server README).
  The largest GPU in the crew is Ryan's 6 GB. Léon has a spare laptop or PC, unconfirmed.
  > A model server (`clm-serve`, from the `contrastive-lm` package) needs about 16 GB of GPU
  > memory for its bf16 Qwen3-8B encoder, or runs quantised on CPU via llama.cpp with a Q8_0
  > GGUF (~9 GB RAM, slow). The candidate host is a spare machine whose GPU is not yet known.
  > Find out: (1) the minimum NVIDIA GPU and VRAM for the bf16 path, and for a Q4 or Q5 GGUF
  > path with full GPU offload; (2) whether llama.cpp with Vulkan or SYCL on an Intel Arc
  > integrated GPU is a realistic middle option, with any benchmark numbers for an 8B model;
  > (3) how to expose such a service only on a Tailscale tailnet, bound to the tailnet IP, with
  > no public port, and whether `clm-serve` has any authentication of its own. Then: check the
  > spare machine's GPU (`nvidia-smi` or `lspci | grep -i vga`) and state plainly whether it
  > qualifies. Constraint: free.
  > [paste the deliverable format]

- [x] **dedup-without-clm** — *Ryan*
  Decides: whether idea-collision detection needs CLM at all, or a small embedding model does it.
  New. At four people and perhaps a few hundred recorded ideas, ranking by cosine similarity
  with a small sentence-embedding model may be enough — and runs on every laptop's CPU.
  > We want to detect when two of four people record a similar project idea — a few hundred
  > short paragraphs total. Compare two approaches: (A) an 8B contrastive ranking model that
  > needs a 16 GB GPU; (B) a small open sentence-embedding model (e.g. bge-small-en, e5-small,
  > all-MiniLM, nomic-embed) run on CPU with cosine similarity, followed by a separate
  > calibrated yes/no check for the top match. Find out: (1) the accuracy gap on
  > near-duplicate detection at this scale, with any published benchmark numbers; (2) CPU
  > latency for embedding one paragraph and comparing against 500 with each small model; (3)
  > disk and RAM footprint; (4) which models are Apache-2.0 or MIT and can be packaged for
  > NixOS. Recommend A, B, or B-now-A-later. If you have an NVIDIA GPU, also time B on GPU vs
  > CPU. Constraint: free.
  > [paste the deliverable format]

- [x] **roblox-on-nvidia-kde** — *Ryan (a guess, from the handle — reassign if wrong)*
  Decides: whether the Roblox toolchain ships as an opt-in module that actually works off Léon's machine.
  Found by: the inventory. Léon built it on Intel Arc + Hyprland; the Roblox friend is on NVIDIA + KDE.
  > A NixOS home-manager module runs Roblox Studio under Wine through Vinegar, with rojo,
  > selene, stylua and luau-lsp alongside. It was built and tested on an Intel integrated GPU
  > under Hyprland. It will next run on a Lenovo Legion with an NVIDIA RTX 2060 Mobile under
  > KDE Plasma 6 Wayland, NixOS 26.05. Find out: (1) the NixOS NVIDIA driver setup Vinegar
  > needs (proprietary vs open kernel module, PRIME offload on a hybrid laptop); (2) known
  > Vinegar or Wine issues on Wayland + KDE specifically, and whether Studio needs XWayland;
  > (3) whether 16 GB RAM is enough for Studio plus Claude Code plus a browser; (4) what the
  > first-launch download size is and whether it is cached across rebuilds. Produce a
  > pre-flight checklist. Constraint: free; the toolchain is deliberately all free software.
  > [paste the deliverable format]

## C. Products

- [x] **booking-stack-licences** — *Almar*
  Decides: build or adopt, for the booking system every hairdresser site needs. Licence first.
  > We build websites for hairdressers and sell them. Each needs appointment booking:
  > availability per staff member, services with durations, buffers, time zones and DST,
  > no double-booking, confirmations and reminders by email, cancellation and no-show handling,
  > and a calendar the salon owner can see. Compare: (A) self-hosting an open-source scheduler
  > such as Cal.com — state its licence (AGPL) and what that means legally for software we
  > sell to a client and host for them, in plain words; (B) a free-tier hosted scheduler and
  > where its free tier ends; (C) building it on SvelteKit + FastAPI + SQLite. For each: cost
  > at five client sites, licence risk, data-protection posture (the data is customers' names
  > and phone numbers in the EU), and lock-in. Recommend one. Constraint: free to run; a
  > licence that forbids or complicates selling is a disqualifier, say so in the first line.
  > [paste the deliverable format]

- [x] **trading-free-data** — *unassigned — whoever drives the trading bot*
  > We are building a trading bot and want free market data for research and paper trading.
  > State the asset classes we care about (fill in: crypto / equities / FX) and for each list
  > free data sources with: rate limits, history depth, whether automated access is allowed
  > by the terms of use, and real-time vs delayed. Then recommend one free, maintained Python
  > backtesting framework and say why. Finally, list the minimum safety conventions for a bot
  > that could ever touch real money: paper-by-default, an explicit live flag, position-size
  > ceilings, and where API keys live (we use agenix on NixOS, never `.env`). Constraint: free.
  > [paste the deliverable format]

- [x] **srs-algorithms** — *unassigned — whoever drives the learning app*
  > We are building a language-learning app with Duolingo-style interactive exercises. The
  > hardest thing to retrofit is the spaced-repetition scheduler. Compare FSRS (current
  > version) with SM-2: scheduling quality, data each needs per card, how each handles a user
  > who disappears for a month, and implementation complexity. List free, maintained
  > implementations in TypeScript and Python with licences. Then: what would a calibrated
  > yes/no classifier (we have one that runs in ~0.2 s on CPU) be good for in grading free-text
  > answers, and where would it be the wrong tool. Constraint: free, licences compatible with a
  > commercial app.
  > [paste the deliverable format]

## D. crew-memory — the shared memory system

> **All three are filed, and this section is now history rather than a track.** crew-memory
> became a real project on 2026-11-19 (`~/Projects/crew-memory`), and it consumed these: the
> git-backed vault from `obsidian-multi-person-sync`, the per-store frontmatter from
> `memory-schema-prior-art`, and the still-open dashboard question from
> `memory-dashboard-options`. Follow-ups live in that project's README, not here.

- [x] **obsidian-multi-person-sync** — *Kish*
  Decides: the foundation of the memory system. Everything else sits on this.
  > Four people on NixOS laptops will share one Obsidian vault that both humans and Claude
  > Code write to, sometimes at the same time. Obsidian Sync is paid, so excluded. Compare:
  > (A) a git-backed vault with the obsidian-git plugin, auto-commit and pull; (B) Syncthing
  > between the four machines; (C) a shared folder over Tailscale (Taildrive or similar). For
  > each: what happens when two people edit the same note within a minute — is there a merge, a
  > conflict file, or silent loss; whether it works when one laptop is asleep or offline; setup
  > effort on NixOS; and how a Claude Code hook that appends to a note at session end interacts
  > with it. Recommend one. Constraint: free, NixOS, must survive simultaneous edits.
  > [paste the deliverable format]

- [x] **memory-schema-prior-art** — *Claude, in Léon's environment*
  > Survey how others structure "shared team context for AI assistants": the MCP memory
  > server's knowledge graph (entities, relations, observations), Obsidian Bases and Dataview
  > conventions, frontmatter-driven notes, and any published "team memory" or "second brain"
  > schemas for coding agents. We have already decided on four stores with different decay
  > rates — Attempts (append-only), Ideas, Components, State (expires). For each store propose:
  > the frontmatter fields, the note naming rule, and how a session would query it without
  > loading the whole vault. Flag any prior art that contradicts the four-store split.
  > [paste the deliverable format]

- [x] **memory-dashboard-options** — *Almar*
  > Four people share an Obsidian vault that holds structured notes (frontmatter: owner,
  > type, status, updated). We want a dashboard: who is working on what, open blockers, recent
  > dead ends, idea overlaps. Compare: (A) Obsidian Bases views inside the vault; (B) a small
  > SvelteKit app that reads the vault from disk; (C) a hosted page that the vault is pushed
  > to. For each: who can open it and from where, whether it can write back, what happens when
  > the vault lives on another person's laptop, and build effort. Recommend one for the first
  > month and one for later. Constraint: free; SvelteKit is our stack if it comes to building.
  > [paste the deliverable format]

---

## Per person, if the suggested owners stand

| | Items |
|---|---|
| **Léon** | nixos-version-matrix · agenix-multi-recipient · clm-hosting-reality |
| **Ryan** | flake-pinning-strategy · dedup-without-clm · roblox-on-nvidia-kde |
| **Kish** | desktop-neutral-module · mcp-free-tiers · obsidian-multi-person-sync |
| **Almar** | atlassian-mcp-auth · booking-stack-licences · memory-dashboard-options |
| **Claude, here** | context-budget · memory-schema-prior-art |
| **Unassigned** | trading-free-data · srs-algorithms |

## Written after the track closed

The sixteen above are the track, and it is finished. `research/` has since gained notes that came
out of building rather than out of a question somebody was handed. They are listed here so the
folder does not accumulate items nobody can account for.

- **hook-precedence-and-the-guard** — 20 Nov, Claude here. Whether a second `PreToolUse` hook can
  weaken the managed guard. It cannot change what the guard sees (matching hooks run in parallel
  on the original input) and cannot disable it (managed hooks merge and outrank), but whether a
  command rewritten with `updatedInput` is re-checked is undocumented — stated as open rather
  than assumed, and deliberately not tested, because the test is a bypass. Also corrects the
  40-repo plan: neither compressor is in nixpkgs.
- **session-capture-hooks** — 20 Nov, Claude here. What a session-end capture hook has to get
  right, read out of `claude-mem` (Apache-2.0) without installing it, which is what the 40-repo
  plan's Phase 4 asked for. Picks `SessionEnd` over `Stop` and is the reason `crew-memory` spools
  a pointer rather than writing a note inside the hook.
