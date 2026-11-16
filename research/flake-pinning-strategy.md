# flake-pinning-strategy

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Confirmed locally:** Nix 2.28.5 on Léon's machine accepts `nix flake update <input>`; the older `--update-input` form is deprecated as stated. The repository `MrBlueStudios/claude-env` does not exist yet (`gh repo view` → not found); the decision is a public repo, so a plain `github:` input works and finding 7 applies only to the private `blitsol-secrets` sibling, which is consumed over SSH anyway.
>
> **What this changes:** nothing; adopt the `stable` branch, the single-input update command in the runbook, and the staleness check in the status line (cached hourly, silent offline). No cache. Finding 9's reasoning is consistent with the modules-only flake confirmed in `nixos-version-matrix`.

---

*Owner: Ryan · researched 16 Nov 2026 · web research plus standard Nix behaviour; no flake was built or tested.*

**Question:** How do four laptops stay on the same revision of `github:MrBlueStudios/claude-env` without drifting, and is a shared binary cache worth setting up?

**Answer:** Point every consumer at a `stable` branch (or tags) of `claude-env` and let each laptop's own `flake.lock` do the pinning; the maintainer moves `stable` only when a revision is ready, and "update now" is simply that branch moving. Do not set up a binary cache yet: a modules-only flake is evaluated against each person's own nixpkgs, so there is almost nothing identical to share, and nearly everything already comes from the official cache. Detecting "I am behind" is a two-line comparison of the locked revision against the branch head, which belongs in the status line the module already ships.

**Confidence:** medium — lock-file behaviour and Cachix's limits are documented; the claim that a cache would rarely hit is reasoning about how modules are built, not a measurement.

**What would change our decision:**
- If the flake starts shipping something heavy that is built from source (the Roblox toolchain, `contrastive-lm`, a patched package), a cache becomes worth it — but only if all four also share one nixpkgs revision.
- If `claude-env` is a private repository, both the input URL and the cache choice change (finding 7).

## Findings

1. **A branch in the URL is already a pin, once locked.** The lock file records both what you wrote (for example a branch name) and the exact commit it resolved to. Rebuilding never moves that commit; only an explicit update does. So "pin a rev" versus "follow a branch" is not a choice between safe and drifting — both are fixed until someone runs an update. The difference is what an update moves to. [notes on lock-file structure](https://edmondo-vault.pages.dev/2---Areas/Tech/Operating-Systems/NixOS/Nix-Flakes) · [Nix book: using flakes](https://ekala-project.github.io/nix-book/ch10-01-using-flakes.html)

2. **The real trade-off.**
   - *Commit hash in the URL:* nobody can move by accident, but every update means hand-editing `flake.nix` on four laptops. People rebuild at different times, so this guarantees drift through laziness.
   - *Default branch (`main`) in the URL:* `nix flake update` pulls whatever was pushed last, including work in progress. Two people updating an hour apart get different revisions.
   - *A `stable` branch or tags:* `nix flake update claude-env` moves to the last revision the maintainer blessed. Two people updating a day apart get the same thing unless `stable` moved in between.

   The third is the recommendation. Consumers write `claude-env.url = "github:MrBlueStudios/claude-env/stable";`. (This is a judgement built on finding 1, not a sourced rule.)

3. **Update one input, not everything.** `nix flake update claude-env` updates only that input; plain `nix flake update` re-resolves every input including nixpkgs, which is a much bigger change than intended. Put the single-input form in the runbook. The older spelling `nix flake lock --update-input` is deprecated. [Nix book](https://ekala-project.github.io/nix-book/ch10-01-using-flakes.html) · [a centralised-pins project describing the same workflow](https://gh.r-mj.com/firefly-engineering/nix-pins) · [deprecation mention](https://discourse.nixos.org/t/cenralizing-control-over-polyrepo-with-follows/67545)

4. **Signalling "update now" without a chat message.** Options, cheapest first:
   - **The `stable` branch moving is the signal**, surfaced by the staleness check in finding 5. Nothing else to maintain.
   - **Tags or GitHub releases** (`v2026.11.2`) give a changelog and let each person subscribe to release notifications. Costs the maintainer one command per release.
   - **The flake registry is the wrong tool.** Registry entries live per machine and resolve at use time rather than being locked in the consumer's repo, which undoes the pinning. One Discourse write-up on centralising pins notes it deliberately avoided the registry. I found no authoritative recommendation either way: UNVERIFIED beyond that. [Discourse](https://discourse.nixos.org/t/cenralizing-control-over-polyrepo-with-follows/67545)

5. **How a consumer detects they are behind.** Compare the commit in the lock file with the head of `stable`:

   ```
   locked=$(jq -r '.nodes["claude-env"].locked.rev' flake.lock)
   latest=$(git ls-remote https://github.com/MrBlueStudios/claude-env refs/heads/stable | cut -f1)
   [ "$locked" = "$latest" ] || echo "claude-env: update available"
   ```

   This is standard tooling but untested here. Run it from the status-line script (cached, at most once an hour, so it never slows a prompt) or from a session-start hook. It needs network; fail silently when offline.

6. **Cadence.** No source prescribes one. A reasonable default: the maintainer moves `stable` at most weekly, plus immediately for a fix that unblocks someone; consumers update when the status line says so. Breaking changes get a tag and a line in the changelog. The maintainer can test a candidate against a consumer config before moving `stable` using `--override-input`, which does not touch the consumer's lock file. [pre-flight validation pattern](https://gh.r-mj.com/firefly-engineering/nix-pins)

7. **If the repository is private, say so now.** A `github:` input fetches anonymously unless the machine has an access token configured for Nix; a private repo is usually consumed as `git+ssh://git@github.com/MrBlueStudios/claude-env?ref=stable` instead, relying on each person's SSH key. This is from general Nix knowledge, not checked against current docs: UNVERIFIED. It matters because the agenda also plans a private secrets repo — keep the two separate.

8. **Cachix free tier: 5 GB, public caches.** Cachix's pricing page gives a free 5 GB limit for open-source projects; private caches need a paid plan. When the limit is reached, least-recently-used entries are removed, and paths already in `cache.nixos.org` are not stored at all. Paid tiers start at 50 GiB. [Cachix pricing (official)](https://www.cachix.org/pricing) · [free = public caches](https://wiki.nixos.org/wiki/Binary_Cache)

9. **Why a cache would rarely help here.** Two reasons, both reasoning rather than measurement:
   - The planned design (see `nixos-version-matrix`) is a flake that exposes modules and lets each consumer supply nixpkgs. Anything the module builds is then built against *that person's* nixpkgs revision, giving different store paths on each laptop — so one person's upload is not what the next person needs, unless all four lock the same nixpkgs commit.
   - What the module installs — hook scripts, a status line, small CLI tools, packages from nixpkgs — is either trivially small or already in the official cache.

   A cache pays off for long source builds shared across identical inputs. That is not this flake today.

10. **Is a public cache acceptable?** For a flake with no secrets, yes in principle: a cache holds build outputs, and agenix secrets are decrypted at activation time, not stored in the Nix store in clear text. But a public cache does publish every built artefact, including your scripts. If the repo is public anyway, nothing new is exposed; if it is private, a public cache leaks it. (Reasoning; no source.)

11. **Alternatives to Cachix, if this is revisited.**
    - **Attic** — open source, self-hosted; needs a server and storage. Fits if the spare machine from `clm-hosting-reality` ends up always-on. [listed here](https://github.com/nix-community/cache-nix-action)
    - **A tiny self-hosted cache on Cloudflare's free tier** (Workers + R2, about 10 GB) — a community project aimed at exactly "personal NixOS configs kept private". Unvetted. [nix-cache-rs](https://github.com/plaflamme/nix-cache-rs)
    - **FlakeHub Cache** — paid only. **Garnix** — listed as discontinued by one October 2026 benchmark. **Magic Nix Cache** — its free tier ended in February 2025. [benchmark README](https://github.com/nhooey/nix-github-actions-cache-bench) · [Determinate Systems announcement](https://determinate.systems/blog/magic-nix-cache-free-tier-eol/)
    - **Any laptop can serve as a cache for another** over the tailnet, per the NixOS wiki — free, but only while that laptop is awake. [NixOS wiki: Binary Cache](https://wiki.nixos.org/wiki/Binary_Cache)

## Not checked

- **Nothing was built.** No timing of a real rebuild of `claude-env`, so "nothing worth caching" is an expectation. One `nixos-rebuild` with `--print-build-logs` on a second laptop would show what is actually built locally versus downloaded.
- **Whether `claude-env` is public or private** — changes findings 7 and 10.
- **Official Nix manual pages** for `nix flake update` and the registry were not opened; behaviour is taken from secondary write-ups and general knowledge.
- **Automated update PRs** (a scheduled job that bumps each person's lock file) — plausible later, not explored.
- **How the 25.05 / 26.05 split interacts with pinning** — that is `nixos-version-matrix`.
