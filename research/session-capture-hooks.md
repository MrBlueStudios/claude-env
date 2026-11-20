# session-capture-hooks

> **Read, not installed.** The plan's Phase 4 says crew-memory's Attempts capture should reuse
> `claude-mem`'s hook payload handling *as a reference* — it is Apache-2.0 and session-lifecycle
> wiring is the fiddly part worth not reinventing — and that the same project stays on the
> do-not-adopt list, because it defaults to a hosted provider and has telemetry on. Both halves
> held up. Nothing was installed and nothing was cloned; the files below were fetched read-only
> through `gh api`. **Done by Claude at Léon's, 20 November 2026.**

**Question:** if crew-memory captures at session end, what does the hook actually have to get
right, and which event should it be on?

**Answer:** `SessionEnd`, and the hook must do almost nothing. Three constraints decide the
design, and all three are documented or measured rather than guessed: a **1.5 second shared
budget**, transcripts that reach **100 MB on this machine**, and the fact that a `Stop` hook
exiting non-zero *prevents Claude from stopping*. So the hook appends one pointer per session and
a second command triages the pointers later. That is what shipped as `crew-memory session-end`
and `crew-memory pending` (45 ms per invocation, measured, including interpreter start).

**Confidence:** high on the event semantics (official docs) and on the local measurements; medium
on claude-mem's reasons, which are read from its comments and issue references rather than
reproduced.

## The findings

**1. `SessionEnd` cannot block; `Stop` can.** From the hooks reference: for `SessionEnd`, exit 2
"shows stderr to user only" and blocks nothing. For `Stop`, exit 2 "prevents Claude from
stopping, continues the conversation". claude-mem's own code carries the scar — the comment on
`src/cli/hook-command.ts:178` records that an unexpected error used to exit 2, which "Claude
Code reads as 'block': UserPromptSubmit dropped the prompt, PreToolUse denied the tool, and Stop
re-woke the agent in a loop" (their issue #3161). Every event in their code now returns exit 0.
This is the same failure the 40-repo review flagged in Codex Plugin CC, whose README admits its
`Stop` gate "can create a long-running loop and may drain usage limits quickly". For a memory
system the choice is therefore free: `SessionEnd` gives the same information and cannot do that.
Source: <https://code.claude.com/docs/en/hooks>, and
<https://github.com/thedotmack/claude-mem/blob/main/src/cli/hook-command.ts>.

**2. `SessionEnd` hooks share a 1.5 second budget** across all of them, raisable only by setting
a longer per-hook `timeout` (up to 60 s). Anything that embeds text, calls a model or touches git
does not fit, and a laptop being closed is the worst moment to find that out. This is the single
constraint that forces "spool now, decide later".
Source: <https://code.claude.com/docs/en/hooks>.

**3. The payload is small and sufficient.** `SessionEnd` receives `session_id`, `prompt_id`,
`transcript_path`, `cwd`, `scratchpad_dir`, `permission_mode`, `hook_event_name`, plus the reason
the session ended. The matcher values are `clear`, `resume`, `logout`, `prompt_input_exit`,
`other` — note that `clear` and `resume` mean one session id can produce two `SessionEnd` events,
so a spool keyed by session id has to collapse duplicates or it will show the same session twice.

**4. Never read the transcript in a hook.** claude-mem's `src/shared/transcript-parser.ts` reads
transcripts backwards in growing chunks (256 KB first, ×4 per step, capped at 64 MB) because
`readFileSync` on a big one "hits JavaScriptCore's 2^31-1 cap (Bun reports ENOMEM) and V8's
0x1fffffe8 cap (ERR_STRING_TOO_LONG); a 2.16 GB session lost every Stop-hook summary that way".
**Measured here:** `~/.claude/projects` holds 588 transcripts totalling 617 MB, the largest
100 MB, this session's own 18.4 MB. So the problem is real on this machine at this scale, not
only at 2 GB. crew-memory's hook records the path and `st_size` and reads nothing.

**5. Their one transferable idea is the split.** A write hook spools the event, nudges a worker,
and waits ≤250 ms for the drain to start (`settleHookSpoolNudges`). Everything expensive happens
outside the hook. crew-memory needs none of the worker, the port reclaim or the spool drain —
`src/shared/` has a 105 KB `worker-utils.ts` and a 56 KB `port-reclaim.ts` — but the shape is
right, and it is the shape, not the code, that was worth reading.

**6. Two smaller lessons worth copying.** They buffer stderr for the duration of the hook, so that
"unsolicited writes from third-party libraries don't leak into model context", and they treat a
missing transcript path and malformed stdin JSON as non-blocking skips rather than errors. Both
are one line each in a Python hook: quiet on success, and return None rather than raise.

**7. Their stdin reader has a safety timeout** (`readJsonFromStdin({ safetyTimeoutMs })`) and
parses after each chunk rather than waiting for EOF. A hook that blocks on a pipe the host never
closes spends the whole budget doing nothing. crew-memory's `read_json_fd` does the same with
`select` and a 1.0 s default.

## Why none of this is installed

The 40-repo review's do-not-adopt reasoning was about defaults, and reading the code confirms it:
the hook's error path calls `captureCliEvent('hook_failed', …)`, so telemetry is in the
*failure* handler of a hook that runs on every session. The repo is also 900 MB and ships
installers for Cursor, Codex, Gemini, Windsurf, Devin, Kimi and Antigravity — a surface the crew
has no use for.

Worth recording for the plan's star-count finding, since the numbers land in exactly the suspect
band: **118,563 stars, 10,315 forks, 365 watchers** (20 Nov 2026). Fork-to-star 0.087, below the
0.10–0.24 organic band; star-to-watcher 325:1 against 171:1 for `anthropics/claude-code` measured
the same day. That is not evidence of anything by itself, and it is not why the project was
rejected — the defaults are — but it is one more datapoint for "the listicle's only selection
criterion selected badly".

## What would change the decision

- If `SessionEnd`'s budget is ever raised or removed, the spool could do a little more — but not
  much more, because the judgement still needs a model.
- If Claude Code ever gives hooks the session's own structured summary, finding 4 stops mattering
  and the pointer could carry content instead of a path.
- If the spool is full of untriaged sessions after a fortnight, the hook was the wrong answer and
  the honest conclusion is that nobody wants to triage. That is the trial, and it is in
  crew-memory's `Attempts/`.
