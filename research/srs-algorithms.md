# srs-algorithms

**Question:** Which spaced-repetition scheduler should the language-learning app use, and under what licence?

**Answer:** FSRS, through the official `ts-fsrs` (MIT) library in the SvelteKit front end or `py-fsrs` (MIT) in FastAPI; both are maintained by the Open Spaced Repetition group and had commits this week. FSRS-6 with default parameters already beats every SM-2 variant on the public benchmark of 350 million reviews, and per-user optimisation of its 21 parameters is optional. SM-2 is only worth considering as a fallback for a first demo, and there is no licence reason to prefer it.

**Confidence:** high on licences and maintenance (read from the repositories); medium on the benchmark figures, which come from the benchmark README and summaries of it.

**What would change our decision:**
- If the app must run fully offline on a phone with no JavaScript, SM-2's handful of lines is simpler to port; FSRS needs a small library.
- FSRS-7 shipping as the default in the libraries (it is already in the benchmark with better log loss); then adopt it with the same code.

## Findings

1. **Licences and activity** (from the GitHub API, 16 November 2026): `open-spaced-repetition/py-fsrs` MIT, 531 stars, pushed 2026-11-13; `ts-fsrs` MIT, 875 stars, pushed 2026-11-13; `fsrs-rs` BSD-3-Clause, 462 stars, pushed 2026-11-10. All permit commercial use without copyleft. Anki itself is AGPL-3.0, so copy the algorithm libraries, never Anki's code. Source: `gh api repos/...`.

2. **Benchmark.** The `srs-benchmark` repository evaluates on 349,923,850 reviews (519 million with same-day reviews). FSRS-6: log loss 0.346, RMSE(bins) 0.065, AUC 0.703. FSRS-7 (recency): 0.337 / 0.059 / 0.722, and 0.318 with same-day reviews. SM-2 has been dropped from the live tables; earlier snapshots put Anki's SM-2 at log loss about 0.62 and plain SM-2 at about 0.72, so FSRS halves the error. Source: [srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark); SM-2 rows from secondary summaries — UNVERIFIED against a current table.

3. **Practical effect.** Secondary sources consistently report 20–30 % fewer reviews for the same retention versus SM-2, and FSRS-6 predicting recall better than SM-2 in about 99.6 % of collections. Anki has shipped FSRS since 23.10 as opt-in; RemNote and Mochi offer it as an option. Source: [FSRS vs SM-2 (Fulin Labs)](https://fulinlabs.com/blog/fsrs-vs-sm2-spaced-repetition-2026/), [Cadence Deck](https://cadencedeck.com/learn/fsrs-vs-sm-2) — third-party.

4. **What the app stores.** FSRS needs per card: `stability`, `difficulty`, `due`, `last_review`, `reps`, `lapses`, `state`, plus the review log (rating 1–4 and timestamp) if parameters are ever optimised. That is one SQLite table for cards and one for reviews; `desired_retention` (default 0.9) is a per-user setting. Source: the `ts-fsrs` and `py-fsrs` READMEs — field names UNVERIFIED letter for letter.

5. **Where to run it.** The scheduler is pure arithmetic and runs in either tier. Running it in the SvelteKit client keeps reviews working offline and syncs the review log later; running it in FastAPI keeps one implementation. Pick client-side (`ts-fsrs`) if offline review matters, which it usually does for a language app.

## Not checked

- Real review data; the figures are Anki users', not language learners on this app.
- FSRS-7 parameter count and whether `ts-fsrs` exposes it yet.
- Optimiser cost: fitting parameters per user needs the Rust or Python optimiser and some hundreds of reviews; not needed at launch.
