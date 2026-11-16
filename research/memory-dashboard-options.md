# memory-dashboard-options

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Checked locally:** Léon runs Obsidian 1.15.1, so Bases (core since 1.9) is available; nothing else in this write-up is testable without the vault. The four-store design's expiring `State` store maps onto a Bases date filter, which is what finding 2 describes.
>
> **What this changes:** nothing; A first, B when overlap views are wanted. With CLM parked, the `similar_to` property in finding 5 is written by the bge-small pipeline from `dedup-without-clm`. The `.base` files are plain text, so Claude Code can generate the first three views from the schema in `memory-schema-prior-art`.

---

*Owner: Almar · researched 16 Nov 2026 · web research only; no dashboard was built. Depends on `obsidian-multi-person-sync`, which recommends a git-backed vault.*

**Question:** How should four people see who is working on what, open blockers, recent dead ends and idea overlaps from a shared Obsidian vault of structured notes?

**Answer:** For the first month use Obsidian Bases inside the vault (option A): it is built in, free, needs no code, and can edit a note's status from the table. Later, if people want it outside Obsidian or want computed things Bases cannot do, build the small SvelteKit app that reads a local clone of the vault (option B). A hosted page (option C) is the weakest fit: free hosting is easy, but keeping it private, current and writable is not.

**Confidence:** medium — Bases' capabilities are from Obsidian's own help pages; the SvelteKit and hosted options are reasoned from how the pieces work, not from a build.

**What would change our decision:**
- If "idea overlaps" is the view people care about most, Bases cannot produce it (it only filters and sorts properties) and option B moves up — it depends on the outcome of `dedup-without-clm`.
- If the vault does *not* end up on every laptop (that is, if the sync decision is not git or Syncthing), option A stops working for anyone who does not hold the files.

## Comparison

| | A. Obsidian Bases | B. SvelteKit app reading the vault | C. Hosted page |
|---|---|---|---|
| Who can open it, from where | Anyone with the vault on their machine and Obsidian. Not from a browser. | Whoever runs it locally, or anyone on the tailnet if one machine serves it. | Anyone with the link and a sign-in, from anywhere including a phone. |
| Can it write back | Yes — editing a cell changes the note's frontmatter. | Yes, if we write it: edit the file, then commit and push. | No, not without building a backend. |
| Vault lives on someone else's laptop | Works only if you also have a copy. With git sync, everyone does. | Same: reads its own clone. A served copy is only as fresh as that machine's last pull. | Unaffected, but shows the vault as of the last build. |
| Build effort | Minutes per view. A few small text files. | Days for a first version; ongoing upkeep. | Hours to set up, plus access control and a build pipeline. |
| Cost | Free | Free | Free at our size |

## Findings

1. **Bases is a core plugin and does most of what was asked.** Obsidian describes Bases as a core plugin for database-like views of notes, where you can view, edit, sort and filter files by their properties, with several views per base. Each row is a note and each column a frontmatter property. That maps directly onto notes with `owner`, `type`, `status` and `updated`. [Obsidian Help: Introduction to Bases (official)](https://obsidian.md/help/bases)

2. **Three of the four views are one filter each.**
   - *Who is working on what:* filter `type` = state, group by `owner`.
   - *Open blockers:* filter `status` = blocked.
   - *Recent dead ends:* filter `type` = attempt, with a date condition — Bases supports date arithmetic such as "modified within the last week" in a filter.

   Filters can apply to all views in a base or only the current one, and formulas add computed columns. [Bases views and filters](https://obsidianmd-obsidian-help.mintlify.app/bases/views) (mirror of Obsidian's help) · [date-filter example](https://danholloran.me/posts/obsidian-bases-native-database-views-without-dataview)

3. **Bases writes back.** Editing a value in a table view updates the note's frontmatter. So "mark this unblocked" can happen from the dashboard. With a git-backed vault that edit is just another change to be committed, with the same conflict rules as any other. [walkthrough](https://danholloran.me/posts/obsidian-bases-native-database-views-without-dataview) · [Obsidian Help (official)](https://obsidian.md/help/bases)

4. **A base is a small text file, so the dashboard syncs with the vault.** A `.base` file holds only filters, formulas and view settings; the data stays in the notes. It can also be embedded in a note as a code block. Commit the `.base` files and all four people get the same dashboard. This also means Claude Code can write or adjust a base as plain text. [complete guide](https://obsidianmate.com/article/obsidian-bases-complete-guide)

5. **What Bases cannot do.**
   - **Idea overlaps.** Bases filters and computes on properties; it has no notion of two notes being about the same thing. That needs the similarity work in `dedup-without-clm`. A workaround: have that tool write a `similar_to` property into each idea note, and let Bases display it. (Inference; not from a source.)
   - **Frontmatter only.** Bases reads YAML properties, not fields written in the note body. The schema has to keep everything the dashboard needs in frontmatter. [guide noting this limit](https://www.obsibrain.com/blog/obsidian-bases-guide/)
   - **No scripting.** Formulas are expressions; there is nothing like DataviewJS for custom output. [Bases vs Dataview](https://obsidianmate.com/article/obsidian-bases-complete-guide)
   - **Obsidian only.** There is no way to open a base from a browser or share it with someone who does not have the vault.

6. **View types.** Guides list table, cards, list and map views, and one says a Kanban board view arrived in Obsidian 1.14. A board grouped by status would suit "who is working on what". The Kanban claim is from a single third-party tutorial: UNVERIFIED. [tutorial](https://vaultpicks.net/obsidian-bases-tutorial/)

7. **Option B — a SvelteKit app that reads the vault from disk.** No source to cite; this is how it would work. The app parses frontmatter from a local clone of the vault and renders whatever views we want, including things Bases cannot (overlaps, charts, a combined "today" page). Two ways to run it:
   - *Everyone runs it locally* against their own clone. Simple, always as fresh as their last pull, no access control needed.
   - *One machine serves it on the tailnet.* One URL for everyone, but stale whenever that machine has not pulled, and gone when that laptop sleeps.

   Writing back means editing the markdown file and committing — the app becomes one more writer alongside humans and hooks, so it must follow the same "pull, commit, push" discipline. Since SvelteKit is already the crew's stack, the cost is time, not learning.

8. **Option C — a hosted page. Free hosting is not the problem; privacy is.**
   - **GitHub Pages cannot do this for free.** On GitHub Free, Pages only publishes from public repositories; and even on paid plans the published site is public unless the organisation is on Enterprise Cloud. A vault of internal notes cannot go there. [GitHub Pages and private repos](https://hostsmith.net/blog/github-pages-private/) · [comparison](https://speedvitals.com/blog/github-pages-vs-cloudflare/)
   - **Cloudflare Pages plus Cloudflare Access can.** Pages builds from a private repository on the free plan, and Access puts a sign-in (email one-time code) in front of it, free for up to 50 users. One guide warns that enabling Access from the Pages project covers only preview deployments, and that protecting the main address takes extra setup in the Zero Trust dashboard — easy to get wrong and leave the site open. [Pages vs Pages for internal docs](https://display.dev/blog/github-pages-vs-cloudflare-pages-internal-docs) · [Access setup caveat](https://stacktr.ee/password-protect-website)
   - **It is read-only and delayed.** A static build shows the vault as of the last push and cannot change a note.
   - **The vault's contents leave our machines** for a third party's servers, which the other two options avoid.

9. **Quartz is not a shortcut to a hosted dashboard.** Quartz is the usual free, MIT-licensed way to publish an Obsidian vault as a website, but it does not render Bases, so the views from option A would not carry over; one site owner reports forking a plugin to work around this. A hosted dashboard would mean writing the views again. [Quartz licence](https://www.mintlify.com/JaegerStein/Siebenlande/quartz/introduction) · [Bases not supported in Quartz](https://github.com/alaycock/quartz-website)

## Recommendation

- **First month — A.** Create `Dashboard.base` with three views (by owner, blockers, recent dead ends), commit it, and see which view people actually open. Effort: under an hour, and it tests whether the frontmatter schema is good enough.
- **Later — B, run locally by each person.** Build it when a concrete need appears that Bases cannot meet — most likely idea overlaps. Reuse the same frontmatter fields so both keep working.
- **C only if** someone needs to check status from a phone or without the repo, and then with Cloudflare Access verified by trying the URL in a private window.

## Not checked

- **Nothing was built.** No `.base` file was written against a real vault; the three filters in finding 2 are described, not tested.
- **Bases performance** on a vault that Claude Code writes to many times a day, and how quickly views refresh after a git pull changes files underneath Obsidian. One guide lists "results stay wrong after edits made outside Obsidian" as a troubleshooting topic, which suggests this is worth testing.
- **The schema itself** — that is `memory-schema-prior-art`. This item assumes `owner`, `type`, `status`, `updated` exist in frontmatter.
- **Serving on the tailnet** (option B, second mode) — how to expose it safely is covered by the Tailscale part of `clm-hosting-reality`, not here.
- **Cloudflare's own documentation** for Pages limits and Access was not opened; figures are from third-party comparisons.
- **Mobile.** Whether anyone wants the dashboard on a phone was not asked; it is the main reason to consider C.
