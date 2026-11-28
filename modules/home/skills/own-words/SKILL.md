---
name: own-words
description: Restate a brain dump in your own words — goal, constraints, what was not asked for, open questions — then stop and wait for a yes.
disable-model-invocation: true
---

<!-- Written for this repo on 2026-11-28 (ct-own-words-skill). -->

# /own-words

The user has just poured out a messy request: a voice note, a long paste, half-formed ideas.
Your job in this skill is **comprehension only**. You prove you understood by restating it, and
you start nothing until the user confirms. The restatement is done when the user could answer it
with one word.

## 1. Read everything first

Read the whole dump and any files or links it names that are already local. Quote nothing back
verbatim; the point is to show the request survived translation into your words.

## 2. Restate, in this shape and this order

```
**Goal:** <one sentence: what is true when this is done>
**Constraints:** <the limits they stated: money, tools, deadlines, people, "free only", style>
**Not asked for:** <things a reader might assume are wanted but were not said — name each>
**Assumptions I'd make:** <the defaults you would pick where they were silent, each one line>
**Open questions:** <numbered; only questions whose answer changes what you would do>
**First step I'd take:** <one concrete action>
```

Keep it short enough to read on a phone: one line per item, at most five items per heading.
A heading with nothing under it says "none".

## 3. Stop

End with exactly: `Is this right? Say yes, or correct any line.`

Then wait. Run no commands, edit no files, and launch no agents until the user answers. A "yes"
hands the restatement to the normal workflow as the brief. A correction updates the restatement;
show the changed lines and ask again.
