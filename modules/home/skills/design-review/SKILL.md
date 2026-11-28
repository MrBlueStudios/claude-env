---
name: design-review
description: Use when asked for several design versions or variants to choose between, a side-by-side comparison of layouts, a page you can drag elements around in or draw notes on, or when iterating on a design from feedback marked directly on it rather than described in prose
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill, Artifact
---

<!-- Léon's own skill, written for this repo's crew: copied from Claude_testing (claude-lab) skills/design-review on 2026-11-28. -->

Design variants for $ARGUMENTS.

This skill drives one published page — the review surface — that holds the variants, takes his
edits, and hands them back. The page is at `artifacts/design-review.html`; its URL lives in
`docs/project-state.yaml` under `artifacts.design_review`.

## 1. Variants differ on one named axis

Default to **three**. Use five only when the direction is genuinely open; use two when he is
choosing between two things he has already named.

**Every variant must differ from the others on one axis you can name in a sentence**, and that
sentence goes in its `label`. Three variants that differ in everything teach nothing: when he
picks one you cannot tell what he picked, so the next round is another guess. Vary the thing the
decision actually turns on — density, hierarchy, how much the hero commits, where the eye lands
first — and hold everything else still.

Write the axis down before writing any HTML. If you cannot name it, you are about to generate
noise.

## 2. Each variant is a standalone document

The surface renders each variant in an isolated frame, so each one is a complete HTML document
with its own `<style>`. No class names are shared and nothing cascades between them — that
isolation is the point, because two variants of the same page would otherwise collide on every
selector.

Load the `artifact-design` skill and apply it to each variant. They are real designs, not
sketches; a variant built as a wireframe loses to a variant built properly for reasons that have
nothing to do with the axis.

**Mark what he may drag:**

```html
<h1 data-movable="hero-heading">…</h1>
<a class="cta" data-movable="hero-cta">Start</a>
```

Only elements carrying `data-movable` can be dragged, and the value is the handle you will get
back, so name it for what the element *is* — `hero-cta`, not `div-3`. Mark the few things whose
position is genuinely in question: everything draggable is nothing emphasised.

## 3. Seed, never hardcode

The page ships empty and reads its content from its own database. Publish or reuse it first,
then seed with one `write_db` **batch**:

- `review/meta` → `{project, brief, updatedAt}` — `brief` is one line naming the axis, so the
  page says what he is choosing between.
- `versions/<vid>` → `{label, html, order}` — `vid` short and stable (`v1`, `v2`, `v3`),
  `order` controlling left-to-right.

Each document holds a whole variant and caps at 256 KiB, which is generous for a page but not
for an embedded image — reference images by URL or keep them as CSS.

Replacing a round means `set` over the same `v1`/`v2`/`v3` ids. **Never delete the `notes`
collection** — his marks on an earlier round are the record of why this round looks like it does.

## 4. Read his edits back, and read them as intent

`read_db` on `notes` returns three kinds, each tagged `kind`:

| kind | Carries | Read it as |
| --- | --- | --- |
| `pin` | `version`, `x`, `y` as 0–1 fractions, `text` | a note about whatever is at that point in that variant |
| `move` | `version`, `target`, `dx`, `dy` in CSS pixels | a direction, not a specification |
| `stroke` | `version`, `path` as 0–1 point pairs | a region he circled; read the nearby pin for why |

`review/choice` holds `{version, at}` or a null version if he has not chosen.

**A `move` is intent.** `dx: -8, dy: 120` under a heading means "put the button below the
heading", not "translate it 120px". Apply the intent in the layout — change the flow, the order,
the grid — and never ship a `transform` copied from his drag. He dragged it to show you where it
belongs, in a frame whose width is not the width he will read it at.

A pin with no obvious target is a question, not a failure. Say what you think it points at and
what you changed; do not silently guess.

## 5. Then iterate

The chosen variant becomes the next round's `v1` unchanged, so he can see whether the change
helped. The other slots vary from it along a **new** axis, named in the brief again. Re-running
the same axis after he has chosen on it is how iteration stalls.

Stop when he picks a version and leaves no notes. That is the signal; asking for another round
after it wastes his time.

## 6. Order of operations

1. Name the axis. Write the variants, each a full document, movables marked.
2. If `artifacts.design_review` holds a URL, Artifact `action: "read"` it first — a publish to a
   URL this conversation has not read is refused — then publish with that `url`. Otherwise
   publish fresh and record the URL.
3. Seed `review/meta` and the `versions/*` documents in one batch.
4. Give him the link and say what the axis is, in one line.
5. On the next turn, `read_db` `notes` and `review/choice` before doing anything else.

Report the link, the axis, and — once he has marked it up — every note you acted on and every
note you could not place.
