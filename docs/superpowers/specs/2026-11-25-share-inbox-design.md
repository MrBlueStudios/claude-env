# Share inbox — design

2026-11-25 · research item `share-inbox` (research/PROGRESS.md §E) · status: draft for Léon's approval

## Why

The crew finds most of its leads on their phones: Instagram reels, TikToks, X posts, repos and
websites. Today those leads reach Claude by hand. Léon downloads the video, pastes the
transcript and ranks the items in a session. Round two of the research queue is exactly that.
Two of its claims turned out to be answered already before any research ran. Things seen on
the go get lost, and things that do arrive get re-researched.

The share inbox makes sending a lead one or two taps from any crew phone or laptop. Claude then
fetches it, checks it is safe, checks it is new, scores it, and files the good ones where the
crew already looks.

## Goals

- **Sending is one or two taps** from the share sheet. That means Android (Léon's Pixel 10,
  Kish), iPhone (Almar, Ryan) and the laptop. Nothing is asked at send time.
- **Shares are never lost when the laptop is off.** They wait in a queue that is always up.
- **Every share is recorded as the sharer's**, with a key per person that can be revoked on its
  own.
- **Every share ends with a verdict the sharer can see**: filed, skipped (with the reason), or
  unsafe.
- **"Already answered?" is part of judging**, checked against `research/`, crew-memory Ideas
  and Attempts.
- **A share worth it becomes two things**: an Ideas note in crew-memory and an open todo.

## Non-goals

- A dashboard. The GitHub Issues list is the view.
- Reading private or login-walled content: protected X accounts, Reddit or LinkedIn behind a
  login, Instagram stories.
- Voice capture. That is the separate `local-voice` research item.
- Routing between model tiers. Laya is deliberately not used; see "What we reuse".

## Anti-goals (a failure even if it works)

- **Using anyone's social-media cookies or logins** to fetch content, including Agent Reach and
  any copy of a personal session. See research/agent-reach.md.
- **Installing or running anything from a shared repo.** Repos are cloned shallow to a scratch
  dir and vetted only.
- **Treating fetched content as instructions.** Anything fetched is data for judging.
- **Running a service on blitsol-prod.** That box is Kōro's production host: 4 vCPU and 8 GB,
  capacity with Chromium unmeasured, and a Caddy config that has silently dropped vhosts before.
- **A share that ends without a verdict**, or a send that asks the sharer a question.

## Decisions Léon made (2026-11-25)

1. **Queue = GitHub Issues** on a private crew repo in a **new free GitHub org**. No receiver of
   our own; the VPS starting position is rejected (reasons under anti-goals). The org is needed
   because fine-grained tokens can only target repos owned by the token holder or by an org
   they belong to. As collaborators on a repo owned by MrBlueStudios, Kish, Almar and Ryan
   could only use classic tokens, which reach all their repos. (This is Claude's understanding
   of GitHub's rules; the first person to make a token confirms it.)
2. **Filed shares go in crew-memory's Ideas store, marked `source: inbox`.** That needs a schema
   change.
3. **The todo is the GitHub issue itself**, left open with the label `todo`. Closing the issue
   means done.
4. **Instagram gets no cookies.** When Instagram walls off a reel, use the fallback chain below.
   Ask the sharer only as the last step, and never block on it. Decide on a throwaway account
   only if the v0 numbers show more than about one reel in five ends at the last step.

## Calls Claude made (check these while reading)

- **Drop Laya** from the inbox path.
- **The scoring rubric.** Four axes of 0–3, worth it at 7 of 12.
- **The vault lives at `~/Projects/crew-vault`**, and each `/inbox` run commits and pushes it
  (v0 step 1).
- **What `unsafe` means for repos.** The general checks apply to the README and install steps,
  and only vet's blocking findings count. Vet's notes lower the score.
- **Where `fit` and `project` slugs come from.** Never invent a slug; use `inbox` when nothing
  fits.
- **"Already known?" also searches `~/project-brain`.**
- **The skill ships from claude-env**, `modules/home/skills/inbox/`.
- **v0 processing is manual**; the cloud routine waits for v1 and its spike.
- **The Instagram retry window is 24 hours**, and `needs-you` expires after 7 days.

## What we reuse (mapped against the reference slides)

| Slide | Ours | Use |
|---|---|---|
| Front doors (Jarvis app, Obsidian plugin) | — | new: share targets |
| The bridge | — | GitHub Issues |
| Jev, the router | Laya | **Not used.** It is reliable only at ruling things out (0.474 on a true duplicate), needs 3.3 GB of RAM, runs on the laptop only, and the job is one Claude call per share anyway. Revisit only if volume reaches dozens a day. |
| Tier 3 skills | `just vet` (claude-env) | the safety check for shared repos |
| Obsidian vault | crew-memory | Ideas store, `just collide` for duplicates |
| Scheduled skills | the `schedule` skill (cloud routines) | v1: processing while laptops are off |
| Whisper | research/reel-transcription.md | `whisper-ctranslate2`, model `small`, int8, on CPU |

Two names are already taken. crew-memory's `vault/Inbox/` is the folder lint quarantines
malformed notes into. The share inbox must not use it, and must not be called "Inbox" anywhere
in crew-memory. In GitHub, the label name `inbox` is fine.

## How it works

```
phone / laptop ──share──▶ GitHub issue (label: inbox, author = sharer)
                                │
          /inbox skill on Léon's laptop (v0) · cloud routine (v1)
                                │
        fetch ─▶ judge ─▶ file: Ideas note + issue stays open as `todo`
                              or: issue closed `skipped` / `unsafe`, reason in a comment
```

### 1. Capture: share targets that post a GitHub issue

Each person makes their own fine-grained token, scoped to the one repo with **Issues:
read/write** and nothing else. The token lives only on that person's devices. The issue author
is the sharer, so identity and revocation come for free.

An issue the share targets create looks like this:

- **title:** the shared page title if the share sheet gives one, otherwise the URL.
- **body:** the raw shared text and URL, unedited, then a line `via: android|ios|laptop`.
- **label:** `inbox`.

Instagram and TikTok share only a URL inside text, so the processor pulls the first URL out of
the body. The targets don't parse anything.

| Device | Target | Notes |
|---|---|---|
| Android | An installable web app with a Web Share Target (`method: GET`). It is one static HTML page, a manifest and an icon on Cloudflare Pages (free). The page calls `POST /repos/{org}/{repo}/issues` with the token from `localStorage`, shows "sent", and closes. | The first visit asks for the token once. No secrets in the deployed files. api.github.com allows CORS. Zero-code fallback if the web app is blocked: the HTTP Shortcuts app with an exported config. |
| iPhone | A Shortcut with "Show in Share Sheet" that takes URLs and text and makes one "Get Contents of URL" POST to the same endpoint. It is shared as an iCloud link, and an import question asks for the token. | v1. |
| Laptop | `just share <url> [note]` in claude-env, which wraps `gh issue create -R <repo> -l inbox`. | Uses each person's existing `gh` login. |

### 2. Fetch: a recipe per link type, always failing soft

Every recipe produces the URL, the title and description from the page meta tags, whatever text
it got, and a `fetch:` line saying which path worked and what was missing. A failed fetch is
still judged on what there is.

| Type | Recipe |
|---|---|
| GitHub repo | `gh repo view --json` (description, stars, licence, last push) and the README, then `git clone --depth 1` into a scratch dir and `just vet <dir>`. Never install, build or run it. |
| Website or article | defuddle; Jina Reader (`r.jina.ai`, `DNT: 1` header) as the fallback. Public URLs only. |
| X post | `https://publish.x.com/oembed?url=…`, the official endpoint, no auth. Text only. |
| Reddit, LinkedIn | Meta tags plus Jina Reader. When blocked, degrade to "link kept, text unavailable". `.json` is reportedly dead (research/agent-reach.md #10). |
| TikTok video | `yt-dlp` for the caption and description (`--write-info-json --skip-download`) and the audio (`-x`), then `whisper-ctranslate2 --model small --compute_type int8`. |
| TikTok photo slideshow | Caption from the page. Images via `gallery-dl`, which Claude reads directly; cap at about 10 images. (v1. gallery-dl's nixpkgs status is unverified.) |
| Instagram reel | The fallback chain below. |
| Anything else | Treat it as a website. |

**Instagram fallback chain.** The levels are recorded on the verdict as `fetch: L1`–`L4`, which
is how v0 measures how often each one is needed.

1. **L1: `yt-dlp`, logged out, from the laptop.** Audio is transcribed, plus the caption.
2. **L2: the public reel page and its embed page, logged out.** Caption only. The verdict says
   "judged on the caption, no transcript".
3. **L3: retry on later runs**, for up to 24 hours. Label `retry`, no comment, nobody pinged.
4. **L4: label `needs-you`** and post one comment: "Instagram blocked this one. Paste the
   caption or attach the video if you want it judged." Ignorable. After 7 days the issue is
   closed as `expired`.

**Versions.** yt-dlp must be current: nixos-25.05 ships 2025.11.12, which is a year old. Take it
from unstable or nixos-26.05. whisper-ctranslate2 is in nixpkgs on both releases. Video work
runs only on a laptop: datacenter IPs fare worse with Instagram, and CTranslate2 has no Intel
GPU backend, so it runs on the CPU. Expect seconds to tens of seconds per reel.

### 3. Judge: the `/inbox` skill

For each issue labelled `inbox` or `retry`, oldest first:

1. **Safety.** For every share, look for scam or phishing signals, malware-style instructions,
   and prompt-injection text aimed at the judge. For repos, also do two more things:
   - Apply the same checks to the README and to the install instructions it gives. `curl | sh`,
     binaries from unknown hosts, and scripts the README says to run all count.
   - Run `just vet`. Its blocking findings mean unsafe. Its `[NOTE]`s, such as a large code
     surface or many outbound addresses, lower `trustworthy` but don't make a share unsafe on
     their own. Vet only blocks on hook shapes, so on its own it would rate almost every repo
     safe.

   Unsafe shares are closed `unsafe` with the reason, and nothing else happens.
2. **Already known?** grep `research/` in claude-env and grep `~/project-brain` (that covers
   blitsol-ideas and the catalog; laptop only). Run `just collide "<summary>"` in crew-memory,
   and query Attempts for the matching project. If the share is already answered, say where
   (file paths), and that counts against "new".
3. **Score (Claude's call).** Four axes, 0–3 each:
   - **fit:** does it touch a live crew project or stated goal?
   - **new:** is it not already answered or filed?
   - **actionable:** is there a concrete next step?
   - **trustworthy:** is the source credible and the claim checkable?

   **Worth it** means safe and a total of 7 or more out of 12.

   "Live crew projects" means the `project` slugs already in the vault (State, Ideas,
   Attempts), the items in claude-env's `research/PROGRESS.md` and `docs/project-state.yaml`,
   and the notes in `~/project-brain/Projects`. Score `fit` against all of them. A note's
   `project` slug must be one the vault already uses. If none fits, use `inbox`. Never invent
   a slug: the vault holds one project today, and invented slugs would never match later notes.

### 4. File: crew-memory plus the issue

**Worth it:**
- **Ideas note.** Write one with `type: idea`, `owner` = the sharer's crew name (map GitHub login
  to name using crew-memory/docs/crew.md), `project` = the matched crew project (or `inbox` when
  none fits), `source: inbox`, `status: raw`, a two-sentence `summary`, and `link` and `issue`.
  Then run `just lint` and `just index`.
- **The issue.** Comment the verdict, swap `inbox` for `todo`, and leave it open.

**Not worth it:** comment the verdict, close the issue, and label it `skipped`.

**Verdict comment.** Six lines:
- score per axis and total;
- the safety result;
- "already known" with paths, or "new";
- a one-line summary;
- the next step (for `todo` only);
- the `fetch:` line.

**Schema change in crew-memory** (`tools/crew_memory/schema.py`), with a test:
- add `"inbox"` to `SOURCES`;
- add `"link"` and `"issue"` to the Ideas `optional` fields. Unknown fields are rejected today
  (schema.py:143).

**Labels:** `inbox`, `retry`, `needs-you`, `needs-laptop` (v1), `todo`, `skipped`, `unsafe`,
`expired`.

### Who runs it

- **v0:** Léon runs `/inbox` in a Claude Code session on his laptop whenever he likes. He's in
  the loop, which matters while the rubric is untested.
- **v1:** a cloud routine (the `schedule` skill) runs the same skill hourly on Anthropic's
  cloud. It handles everything except video and labels video `needs-laptop`. The laptop picks up
  `needs-laptop` and `retry` on its next run. The routine needs a spike before it is designed
  further. Verify that a routine can:
  1. fetch arbitrary public websites (environment network access);
  2. list, comment on and label issues in the queue repo;
  3. commit to the vault repo's main branch, or say how its branch gets merged;
  4. run `just vet`, which means having claude-env checked out.

  If 2 or 3 fail, the routine is only a judge that comments, and filing waits for a laptop.

## v0: usable this week, Léon only

Done when Léon shares a TikTok, a repo and a website from his Pixel, runs `/inbox`, and gets
the following: three verdict comments on GitHub, at least one Ideas note that passes
`just lint`, and the `fetch:` line on each.

1. **Create the private vault repo under MrBlueStudios.** This is crew-memory's open item 1;
   seed it from `crew-memory/vault/`. Moving the repo to the org later keeps its issues. Create
   the labels. Clone it to `~/Projects/crew-vault`. From then on, the clone is the vault, and
   `crew-memory/vault/` stays the skeleton and templates, as crew-memory's README already
   intends. Two consequences:
   - The justfile hard-sets `CREW_MEMORY_VAULT` to `crew-memory/vault`. So every
     crew-memory call the skill makes (lint, index, collide, query, writing a note) must point
     at the clone, through the CLI's `--vault` flag or by overriding that variable. Otherwise
     lint checks the stale copy.
   - Each `/inbox` run ends with one commit and push to the vault repo's `main`, so filed notes
     are where the others will pull them.
2. **Léon makes his fine-grained token** with Issues read/write on that repo.
3. **Build the Android share web app** and deploy it to Cloudflare Pages. Léon installs it on
   the Pixel.
4. **Make the crew-memory schema change** with a test (`just test` green).
5. **Write the `/inbox` skill.** It ships as a skill in claude-env `modules/home/skills/inbox/`,
   because that is how skills reach `~/.claude` today. It calls crew-memory through
   `just -f ~/Projects/crew-memory/justfile`. Recipes in v0: repo, website, X oEmbed, TikTok
   video, and Instagram L1–L4.
6. **Add `just share <url>`** in claude-env.

**Not in v0:** the org and the other three people, the iPhone Shortcut, the cloud routine, the
TikTok slideshow and gallery-dl, dedicated Reddit and LinkedIn handling beyond the website
recipe, on-screen text from video frames, and a standalone fetch script.

## v1, in order

1. **Org and people.** Create the free org and move the repo into it. Kish, Almar and Ryan make
   tokens. Kish installs the Android web app.
2. **iPhone.** Build the Shortcut for Almar and Ryan.
3. **Cloud routine.** Do the spike above, then the routine.
4. **Fetch script.** Pull the fetch recipes out of the skill into a script, once both the laptop
   and the cloud run them and the recipes have stopped changing.
5. **Review after two weeks.** Count `fetch: L1–L4` for Instagram (more than 1 in 5 at L4 means
   decide on the throwaway account). Count the share between `skipped` and `todo`. Ask whether
   the rubric threshold should move.

## Left to the builder

- Names of the org, the vault repo and the Cloudflare Pages project. The org and repo are Léon's
  to create.
- The web app's look and its token-entry screen. Keep it plain and accessible.
- Exact wording of the verdict comment within the six lines above.
- Whether `just sweep` should skip `source: inbox` notes. `just collide` must include them.
- How the 24-hour retry window is tracked: the label's timestamp, or the issue's creation time.
- How yt-dlp gets onto the laptop (a home-manager package from unstable, or `nix run`), as long
  as it is current.
