# obsidian-multi-person-sync

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Simulated with two clones of a bare repo** (16 November, git on Léon's machine): edits to different lines of one note rebase cleanly; edits to the same line produce conflict markers; two appends to a shared log conflict without `merge=union` and merge cleanly with it, both lines kept; one new file per session never conflicts. Every claim in the comparison table's git column is now reproduced, so confidence moves to high for option A.
>
> **What this changes:** nothing; adopt the recommended setup as written. The hook writes its own file and does its own `pull --rebase`, commit and push. The `.gitattributes` union rule is kept only for genuinely shared logs.

---

*Owner: Kish · researched 15–16 Nov 2026 · web research only, no test vault was built.*

**Question:** Which free mechanism should four NixOS laptops use to share one Obsidian vault that humans and Claude Code both write to, sometimes at the same moment?

**Answer:** Use a git-backed vault (option A) — it is the only one of the three that actually merges two people's edits to the same note instead of producing duplicate files or risking loss. It only holds up if Claude Code hooks write one file per session rather than appending to a shared note, and if the hook does its own commit and push instead of relying on the Obsidian plugin. Syncthing is a workable second choice with whole-file conflict copies; Taildrive is alpha and should be ruled out.

**Confidence:** medium — the conflict behaviour of git and Syncthing is from their official documentation, but the obsidian-git plugin's exact behaviour on conflict and the hook interaction are reasoned from partial sources and not tested.

**What would change our decision:**
- If people regularly edit the *same note at the same time* (live co-writing, not just overlapping within a few minutes), git's merge markers become a daily chore and a real-time tool is needed instead — not evaluated here.
- If the memory design ends up needing shared notes that many sessions append to, the "one file per session" rule fails and the append-only notes need the `merge=union` setting described in finding 5, with its ordering caveat.

## Comparison

| | A. Git + obsidian-git | B. Syncthing | C. Taildrive |
|---|---|---|---|
| Two edits to the same note within a minute | Different lines: merged automatically. Same lines: conflict markers in the note, sync pauses until resolved. | No merge. One version is renamed to a `.sync-conflict-…` copy, even if the edits were to different lines. | Not documented. Likely last write wins. |
| Silent loss? | No — everything is a commit. | Not by design; anecdotal reports of empty files with Obsidian. | Possible; UNVERIFIED. |
| One laptop asleep or offline | Fine. Commit locally, merge on next sync. | Fine locally, but changes only travel when two laptops are awake together. | The vault is unavailable to everyone if the host laptop sleeps. |
| Setup on NixOS | Git, an SSH key, a private remote, a community plugin. | Declarative via `services.syncthing` in NixOS or home-manager. | Policy-file change, `davfs2` mount, alpha feature. |
| Claude Code hook appending at session end | Works if the hook commits and pushes itself and writes its own file. | Works, but an append that collides goes into a conflict copy nobody queries. | Writes through a network mount; fails when the host is away. |
| Cost | Free | Free | Free |

## Findings

1. **Git merges; the other two do not.** The obsidian-git plugin's "commit-and-sync" is stage everything → commit → pull → push, run on a timer measured in minutes, with optional pull on startup. On desktop it shells out to the real `git` binary, so behaviour is ordinary git: edits to different parts of a note merge cleanly, edits to the same lines produce a conflict. [obsidian-git documentation](https://publish.obsidian.md/git-doc) · [plugin README](https://github.com/Vinzent03/obsidian-git) · [explanation of desktop behaviour](https://www.stephanmiller.com/obsidian-git-sync-mobile/)

2. **What a git conflict looks like in Obsidian.** The plugin now has in-editor conflict resolution: highlighted "ours" and "theirs" sections with buttons to keep either or both, and a Source Control list of conflicted files. Early plugin source shows it refuses to auto-commit while conflicted files exist. Whether the current version still pauses in exactly that way: UNVERIFIED — the plugin's conflict-resolution doc page could not be opened from this session. [plugin README](https://github.com/Vinzent03/obsidian-git) · [original conflict-handling commit](https://github.com/Vinzent03/obsidian-git/commit/358dc6e492e6ef8156687535d14a9070ebadfb30?branch=358dc6e492e6ef8156687535d14a9070ebadfb30)

3. **Git is not real-time.** Edits arrive only after a commit and a pull, so "within a minute" means the second person does not see the first person's change until the next sync interval. One source that sells an alternative puts it bluntly: two people editing the same note between pushes get a merge conflict, not a merged note. That is accurate for same-line edits and is the main cost of option A. [team-sharing write-up](https://baalda.com/blog/sync-obsidian-with-github) (vendor source, has an interest)

4. **The hook must not depend on the plugin.** The plugin only runs while Obsidian is open. A Claude Code session-end hook fires whether or not Obsidian is running, so the hook needs to do `git pull --rebase`, commit and push itself. This is inference from how the plugin works, not a documented statement. The same inference says the hook and the plugin can occasionally collide on git's index lock if both run in the same second; the hook should retry once.

5. **Appending to a shared note is the one pattern git handles badly — and there is a setting for it.** Two sessions that each add a line to the end of the same file have edited the same place, so git reports a conflict every time. Two ways out: (a) have each session write its own file, which matches the append-only "Attempts" store already planned; or (b) mark append-only logs with `merge=union` in `.gitattributes`, a built-in git merge driver that keeps the lines from both sides instead of leaving conflict markers. The git documentation warns that union merging can leave added lines in arbitrary order and that the result should be checked. Prefer (a); use (b) only for genuine shared logs. [gitattributes documentation](https://git-scm.com/docs/gitattributes)

6. **Keep per-device state out of the repo.** `.obsidian/workspace.json` changes whenever someone moves a pane or cursor and is the usual source of pointless conflicts. Ignore `workspace*.json`, `.obsidian/cache/`, `.trash/`; decide deliberately whether plugin and theme settings are shared or per person. [guide with a full .gitignore](https://glaforge.dev/posts/2026/09/13/sharing-a-git-backed-obsidian-vault-across-computers/)

7. **Syncthing detects conflicts but cannot merge them.** When a file changes on two devices before they sync and the content differs, the copy with the older modification time is renamed to `<name>.sync-conflict-<date>-<time>-<device>.<ext>`, and that conflict file is then synced to everyone as a normal file. Syncthing is not content-aware: edits to line 1 and line 2 of the same note still conflict. So nothing is lost, but the vault fills with near-duplicate notes that someone must merge by hand, and Claude's queries will not look in them. [Syncthing: Understanding Synchronization (official)](https://docs.syncthing.net/users/syncing) · [maintainer confirming it is not content-aware](https://forum.syncthing.net/t/how-does-conflict-resolution-work/15113)

8. **Syncthing timing.** The file watcher batches changes for 10 seconds before syncing, and a full rescan runs hourly by default. With no always-on device, a change made on laptop A reaches laptop B only when both are awake at the same time — with four laptops on different schedules, the windows in which two people hold different versions get long, and so do the conflicts. The 10-second and hourly figures are from the docs; the consequence for four laptops is inference. [Syncthing: Understanding Synchronization (official)](https://docs.syncthing.net/users/syncing)

9. **Syncthing and Obsidian have a known rough edge.** A Syncthing forum thread documents recurring conflict files, zero-filled files and an emptied original when Obsidian and Syncthing both rewrite the same file, particularly `.obsidian` config and auto-created notes. It involved Android devices in a triangle, so it may not reproduce on four Linux laptops, but it is the "silent loss" case the brief asked about. [forum thread](https://forum.syncthing.net/t/recurring-sync-conflicts/21665) (anecdotal)

10. **Syncthing on NixOS is the easiest setup of the three.** Devices and folders can be declared under `services.syncthing.settings` in NixOS, and home-manager has a matching module with the same declarative devices/folders options. Each laptop's device ID has to be collected once and put in the flake. [NixOS wiki: Syncthing](https://wiki.nixos.org/wiki/Syncthing) · [home-manager option list](https://mynixos.com/home-manager/options/services.syncthing)

11. **Taildrive is alpha and has no conflict story.** Tailscale's own page labels it alpha. It exposes shared folders over WebDAV at `100.100.100.100:8080`, mounted on Linux with `davfs2`, and needs a `nodeAttr` plus grants in the tailnet policy file. The page says nothing about locking or conflicts. Tailscale's own blog advises against putting irreplaceable things on it without backups, and there is an older bug where writes through a `davfs` mount never reached the remote. [Taildrive docs (official)](https://tailscale.com/docs/features/taildrive.md) · [Tailscale blog caution](https://tailscale.com/blog/tailscale-chromebook-taildrop-taildrive) · [davfs write bug, 2024](https://github.com/tailscale/tailscale/issues/12097)

12. **Taildrive puts the vault on one laptop.** It is a network share, not a sync: the files live on whichever machine shares them, and the docs say shares appear only while active. When that laptop is closed, the other three have no vault. That alone fails "works when one laptop is asleep". (The docs do not state this outright; it follows from the design.) [Taildrive docs (official)](https://tailscale.com/docs/features/taildrive.md)

13. **Obsidian itself is free for this use.** Since 20 February 2025 the commercial licence is optional; anyone can use Obsidian for work at no cost. In nixpkgs it is an unfree package, so each config needs `allowUnfree` (or a per-package allowance) — that last part is from memory, UNVERIFIED. [Obsidian: free for work (official)](https://obsidian.md/blog/free-for-work/)

## Recommended setup (option A)

1. One private repository for the vault, separate from `claude-env`. Everyone clones over SSH.
2. `.gitignore`: `.obsidian/workspace*.json`, `.obsidian/cache/`, `.trash/`.
3. obsidian-git on each laptop: pull on startup, auto commit-and-sync every few minutes, merge strategy "merge".
4. Claude Code hooks write **one new file per session** (for example `Attempts/2026-11-16-kish-<short-id>.md`), then pull, commit and push by themselves.
5. For any note that must be a shared append-only log: `path/to/log.md merge=union` in `.gitattributes`.
6. Agree one rule for humans: if you see conflict markers, resolve them before you close Obsidian.

## Not checked

- **Nothing was built.** The "two edits within a minute" outcomes come from documentation, not from two laptops editing a test note. A fifteen-minute test with two machines would turn medium confidence into high.
- **obsidian-git's current conflict behaviour** — its conflict-resolution documentation page was blocked from this session.
- **Real-time alternatives** such as Self-hosted LiveSync (CouchDB-based) were named by one source as the answer for genuinely simultaneous editing. They were outside the three options in the brief and were not evaluated; they need a server.
- **Free private repository limits** on GitHub or alternatives — assumed free for four collaborators, not re-checked. Vault size with attachments (images, PDFs) could matter.
- **Secrets.** Whether anything written by Claude Code into the vault could contain credentials, and so whether the remote host matters, was not considered.
- **Mobile.** Nobody mentioned phones; obsidian-git on mobile is described as experimental and was not looked at.
- **Taildrive's actual behaviour under concurrent writes** — not documented and not tested; "likely last write wins" is an assumption.
