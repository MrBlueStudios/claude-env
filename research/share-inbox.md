# share-inbox
**Question:** How does anything a crew member sees on a phone or laptop reach Claude in one or two taps, get fetched, checked for safety and novelty, scored, and filed where the crew looks — including when the laptop is off?
**Answer:** Share targets post straight to GitHub Issues on a private crew repo (a web app in the Android share sheet, a Shortcut on iPhone, `just share` on the laptop), each person with their own fine-grained token, so there is no server of our own and nothing on the Kōro box. A `/inbox` skill fetches each link with a no-login recipe per type, judges safety, "already known?" and a 12-point score, and files the worth-it ones as crew-memory Ideas notes (`source: inbox`) while the issue stays open as the todo. v0 is Léon only with manual `/inbox` runs; v1 adds the org, the other three, the iPhone Shortcut, and an hourly cloud routine.
**Confidence:** medium, because the pieces are verified or come from the two sub-results, but three things are unconfirmed until they are built: cloud-routine capabilities, how often Instagram walls off a logged-out laptop, and GitHub's fine-grained token rules for collaborators.
**What would change our decision:**
- If a cloud routine cannot comment on issues or push to the vault repo, v1 processing while laptops are off shrinks to a routine that only comments, and filing waits for a laptop.
- If more than about one Instagram reel in five ends at the last fallback (`needs-you`), decide on a throwaway Instagram account then, with numbers.

## Findings
1. **The full design** is [docs/superpowers/specs/2026-11-25-share-inbox-design.md](../docs/superpowers/specs/2026-11-25-share-inbox-design.md), approved by Léon on 25 Nov. It holds the decisions, the calls Claude made, the fetch recipes, the rubric and the v0/v1 split. This note is its summary in the research format.
2. **Queue = GitHub Issues in a private crew repo; the VPS receiver is rejected.**
   - blitsol-prod is Kōro's production host, at 4 vCPU and 8 GB. Its capacity with Chromium is unmeasured, and its Caddy config has silently dropped vhosts before.
   - Sources: `Blitsol/blitsol-prod-config/SERVER-CONTEXT.md` §1 and §9a, and `cloudflare-only.nix`.
   - Issues give per-person identity (the author), revocation, and feedback through GitHub notifications, with no code to write.
3. **A free GitHub org is needed for Kish, Almar and Ryan.**
   - Fine-grained tokens can only target repos owned by the token holder or by an org they belong to. Collaborators on a repo Léon owns would need classic tokens, which reach all their repos.
   - No existing org holds all four (`gh api user/orgs`, 25 Nov).
   - The token rule itself is UNVERIFIED until the first person makes a token.
4. **Fetch never uses anyone's cookies.** Agent Reach is ruled out because it puts the crew's personal X, Reddit and LinkedIn sessions into a stealth browser ([agent-reach.md](agent-reach.md)). X uses the official oEmbed endpoint, websites use defuddle with Jina Reader as the fallback, and Reddit and LinkedIn degrade to the page's meta tags.
5. **Video is transcribed on the laptop:** `yt-dlp` from nixos-unstable, then `whisper-ctranslate2` with the `small` model at int8 on the CPU ([reel-transcription.md](reel-transcription.md)). nixos-25.05's yt-dlp is a year old, and CTranslate2 cannot use the Arc iGPU.
6. **Instagram's login wall gets a four-step chain with no cookies.** In order:
   - L1: yt-dlp, logged out.
   - L2: the caption from the public page or embed.
   - L3: silent retries for 24 h.
   - L4: an ignorable `needs-you` comment that expires after 7 days.

   Every verdict records its level, so v0 measures how often each one is needed.
7. **Laya is not used.** It is reliable only at ruling things out (0.474 on a true duplicate), it needs 3.3 GB of RAM, it is laptop-only, and the job is one Claude call per share anyway. Sources: crew-memory `skills/crew-memory/SKILL.md`, and `Laya_And_CLM-MCPs/laya-mcp-server/README.md`.
8. **The schema needs a small change.** Ideas allow only `source: session|human` and reject unknown fields (crew-memory `tools/crew_memory/schema.py:18,143`), so `inbox`, `link` and `issue` have to be added. Also, crew-memory's `vault/Inbox/` already means "quarantined malformed notes", so the share inbox must not reuse that name.
9. **Round two of this queue (§E) was this pipeline done by hand,** and two of its claims were already answered before any research ran. That is why "already known?" is a judging step: it greps `research/` and `~/project-brain` and runs `just collide`.

## Not checked
- What a cloud routine can do: network access, issue comments, pushing to main. The v1 spike covers it.
- Chrome's current installability rules for a web app on Android. The v0 build finds out by installing it on the Pixel.
- Whether GitHub silently drops labels on issues created by users without push access. v0 avoids depending on it (see the v0 plan's Review Focus).
- `gallery-dl` in nixpkgs, for TikTok photo slideshows, which are v1.
