# memory-schema-prior-art

**Question:** How do others structure shared, agent-readable team memory, and what frontmatter, naming and query rules should each of our four stores (Attempts, Ideas, Components, State) use?

**Answer:** The published schemas agree on three things we should copy: frontmatter is the schema and a hook lints it on every write; one durable fact per file, superseded by linking rather than editing; and an always-loaded index under a few hundred lines that points at files loaded on demand. None of them has a first-class "attempt" or "dead end" type, so the four-store split is an extension of prior art, not a contradiction of it; the closest ancestors are MADR's `rejected` and `superseded by` statuses and obsidian-mind's `confidence` field. Below is a concrete schema per store and a query rule that never loads the whole vault.

**Confidence:** medium — the prior art is read from the projects' own READMEs and templates, but no schema was tested against real sessions; the field proposals are design, not findings.

**What would change our decision:**
- If a session-end hook cannot reliably fill `outcome` and `components` without a human, the Attempts store degrades into a log nobody queries; a two-week trial decides this.
- If the MCP memory server's graph (entities, relations, observations) turns out to be what people actually query, the four stores should be mirrored into it rather than replaced by it; today the graph lives per machine and is being pruned for that reason.

## Prior art

1. **obsidian-mind** (MIT, 5.5k stars, active) — an Obsidian vault for Claude Code, Codex and Gemini agents. Folders group by purpose (`work/active`, `brain/` for durable memory, `reference/`), links group by meaning. Memory notes carry `confidence: verified | inferred | unverified`, `verification`, `scope`, `projects`, `generality`; decision records carry `date, description, status (proposed/accepted/deprecated), owner, context`. A `PostToolUse` hook validates frontmatter and wikilinks and blocks misplaced files; "a note without links is a bug". Git-tracked by design. [README](https://github.com/breferrari/obsidian-mind)

2. **obsidian-memory-for-ai** (no licence file, 178 stars) — the most schema-heavy. Required frontmatter `type: fact | preference | rule | project | person | decision | insight`, `relevance: high | medium | low`, `last_reviewed: YYYY-MM-DD` ("when a note was actually validated, not touched"). Decisions as `DEC-###` with `status`, `date`, `scope`. A `supersedes` link verb ages facts without deleting them. A Tier-0 `CLAUDE.md`, a Tier-1 `index.md` with one-line summaries per page, a `triggers.md` mapping keywords to files to load, and a parseable `log.md`. [guide](https://github.com/jrcruciani/obsidian-memory-for-ai/blob/main/guide.md)

3. **MADR** (MIT or CC0) — the de-facto decision-record template. Frontmatter `status: proposed | rejected | accepted | deprecated | superseded by ADR-0123`, `date`, `decision-makers`, `consulted`, `informed`; sections "Considered Options", "Decision Outcome", "Consequences", "Confirmation". The `rejected` status and the "Considered Options" section are the nearest published thing to a dead end. [adr.github.io/madr](https://adr.github.io/madr/)

4. **The MCP memory server** — a knowledge graph of entities, relations and observations stored in one JSON file per machine. Good shape for "who worked with what", but no per-machine file can be shared, which is why it is being pruned from the user scope. Its vocabulary (entity, relation, observation) is worth keeping as the mental model for Components. [modelcontextprotocol/servers memory](https://github.com/modelcontextprotocol/servers/tree/main/src/memory) — UNVERIFIED that the current version still uses a single JSON file.

5. **Obsidian Bases and Dataview** — both read frontmatter only. Bases (core since 1.9) filters, sorts, groups and edits properties in place; a `.base` file is text and commits with the vault. Dataview adds scripting but is a community plugin. Anything a view needs must therefore be a property, never body text. [Obsidian Help: Bases](https://obsidian.md/help/bases); see also Kish's `memory-dashboard-options`.

6. **Team knowledge-base write-ups** (e.g. the claude-code-ultimate-guide) converge on: a versioned markdown vault, a root index the agent always reads, ADRs under `engineering/adr/`, and git underneath. None has attempts or dead ends as a type; AgentsRoom has "pitfalls" as a category. [team-knowledge-base](https://github.com/FlorianBruniaux/claude-code-ultimate-guide/blob/main/guide/ecosystem/team-knowledge-base.md)

7. **Karpathy's llm-wiki gist** (2026-04-04) — three layers: raw sources, an LLM-maintained wiki, and a schema file. Ingest updates an index and an append-only log; a periodic lint looks for contradictions, orphans and stale claims. The `outputs/` folder and the "RAG" label come from promoters, not from Karpathy. Reported failures: wrong pages that compound, index drift near 300 pages, ingest cost ([HN](https://news.ycombinator.com/item?id=47899844), [mpt.solutions](https://www.mpt.solutions/karpathys-llm-wiki-works-heres-what-broke-when-i-ran-it-at-real-scale/)). crew-memory maps on: four stores = wiki; inbox-files and `status: raw` = raw; INDEX = index; session-end spool = log; the dead-link warning in `lint` = the deterministic part of lint (no orphan check: store notes stand alone by design). [gist](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)

**Does anything contradict the four-store split?** No. Prior art splits by *kind* (decision, fact, person, project) and ages by `last_reviewed` or `supersedes`; we split by *decay rate* and add explicit outcomes. The two are compatible: our `type` field carries the kind, our store carries the decay rule.

## Proposed schema

Common to every note: `type`, `owner` (one of almar · ryan · kish · leon), `project` (slug), `created` (ISO date), `updated`, `source: session | human`, `session` (Claude Code session id when written by a hook), `tags` (list). Lint on every write with a hook, as obsidian-mind does; a note that fails lint goes to `Inbox/` instead of its store.

| Store | Extra frontmatter | File name | Decay rule |
|---|---|---|---|
| **Attempts** (append-only) | `goal`, `approach`, `outcome: worked \| failed \| abandoned \| superseded`, `why` (one line), `components: [slugs]`, `supersedes` (link) | `Attempts/YYYY-MM-DD-<owner>-<slug>.md`, one per session | Never edited after the session; a later attempt links `supersedes`. |
| **Ideas** | `status: raw \| shaping \| doing \| parked \| dropped`, `summary` (≤ 2 sentences, English), `similar_to: [links]` (written by the dedup pipeline), `embedding_hash` | `Ideas/<slug>.md`, slug from the summary | Edited in place; `status` moves; dropped ideas keep the note. |
| **Components** | `kind: library \| service \| snippet \| pattern`, `repo`, `path`, `used_by: [projects]`, `last_verified` | `Components/<slug>.md` | Reviewed quarterly by `last_verified`, as in obsidian-memory-for-ai. |
| **State** | `status: active \| blocked \| done`, `blocked_on` (link or text), `expires` (ISO date, default created + 14 days), `next` (one line) | `State/<owner>-<project>.md`, one per person per project | A view hides notes past `expires`; the hook refreshes `expires` when the person works on the project. |

Naming rules in one line each: dates first for anything append-only, slug-only for anything edited in place, owner-project for anything that is one-per-person.

## How a session queries without loading the vault

1. **Always loaded: one `INDEX.md` per store, generated, under 150 lines each** — one line per note: link, `owner`, `status` or `outcome`, `summary`. Regenerated by the session-end hook (it is the `index.md` of obsidian-memory-for-ai and the `log.md` of obsidian-mind). Four index files is roughly 2–3k tokens, less than the MCP servers measured in `context-budget`.
2. **On demand by property, not by grep:** `rg --files-with-matches '^project: booking' State/` style lookups by the hook or a tiny CLI, then read only those files. Frontmatter-only parsing (stop at the second `---`) keeps this at milliseconds for a few hundred notes.
3. **Similarity by the dedup pipeline:** embeddings cached next to the note (`embedding_hash` tells the pipeline when to recompute); a new Idea gets its top three `similar_to` links written in, so the human sees overlaps in Bases without any model call at read time.
4. **Expiry by a view, not by deletion:** State notes past `expires` drop out of the dashboard and the index but stay in git.

## Not checked

- The schema against real sessions; a two-week trial with the hook writing Attempts is the test.
- Whether Bases can group on a list property (`components`, `similar_to`) or only on scalars; if only scalars, the views use `project` and `status`.
- Mem0, Letta and other hosted "agent memory" products; they are servers, which the free-and-local constraint rules out for now.
- The current MCP memory server storage format.
