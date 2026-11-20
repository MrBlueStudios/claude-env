# hook-precedence-and-the-guard

> **Done by Claude at Léon's, 20 November 2026**, from the official hooks documentation. One
> question at the end is deliberately **not** answered, and the reason is the point of the note.

**Question:** the 40-repo plan's trial list has one compressor — RTK or Headroom — and RTK works
through a `PreToolUse` hook that rewrites every Bash command. The managed guard is also a
`PreToolUse` hook. What happens when two of them look at the same command, and can the second
one weaken the first?

**Answer, for the parts the documentation settles:** a user-level hook cannot change what the
guard sees, and cannot switch the guard off. What is *not* documented is whether a rewritten
command is re-checked, which is the one thing worth knowing before any command-rewriting hook
goes on a crew laptop.

**Confidence:** high on the three established facts, all quoted from the docs. The open question
is open — not "probably fine".

## What is established

**1. Matching hooks run in parallel, each on the original input.** "When an event fires, its
matching hooks run in parallel." Nothing in the reference says one hook's output becomes
another's input. So a compressor's hook cannot pre-rewrite the command the guard inspects: both
see what Claude actually asked for. That closes the obvious attack and is the reassuring half.

**2. Managed hooks cannot be removed or disabled from below.** "Hook entries merge across
settings levels rather than replacing each other: user, project, and local settings add their own
hooks without removing managed ones." And: "If an administrator has configured hooks through
managed policy settings, `disableAllHooks` set in user, project, or local settings can't disable
those managed hooks. Only `disableAllHooks` set at the managed settings level can disable managed
hooks." The guard lives in `/etc/claude-code/managed-settings.json`, which the NixOS module owns
and no user setting outranks — so adding a plugin cannot quietly remove the brakes.

**3. A `PreToolUse` hook has two separate powers.** `hookSpecificOutput` carries
`permissionDecision` (`allow` / `deny` / `ask` / `defer`) with a reason, and separately
`updatedInput`, which rewrites the call's arguments. A compressor uses the second; the guard uses
the first.

## The open question, stated exactly

**Is a command rewritten by `updatedInput` re-evaluated — by the permission rules, and by the
other hooks that already ran?**

If it is not, then the shape of the risk is not "a hook sneaks a command past the guard" but
"the guard allows the command it was shown, and something else runs". Both hooks see
`cat notes.txt`, the guard allows it, and the rewriting hook returns an `updatedInput` that is no
longer that command. Nothing in the hooks page or the hooks reference says which way this goes:
the only sentence either page spends on `updatedInput` is about Monitor-tool matchers.

That is not a reason to assume the worst, and it is not evidence of a flaw. It is a reason not to
put a command-rewriting hook on four laptops that run a guard protecting `.env`, `/run/agenix`
and SSH keys, until the behaviour is known.

## Why this was not tested here

The experiment is easy to describe: a user-level `PreToolUse` hook that rewrites, or that answers
`allow` to something the managed guard denies, and then see which wins. **It was not run.** The
crew's own rule is that if the guard blocks something legitimate, the answer is to ask Léon
rather than route around it — and a hook written specifically to see whether `allow` beats the
guard's `deny` is a bypass, whatever the intent behind it, and it would be left behind on the
machine if it worked.

So it is Léon's to run if he wants it, knowingly, on a throwaway config directory rather than on
his own:

**Run in: any directory, with a scratch config so nothing touches `~/.claude`**

```bash
export CLAUDE_CONFIG_DIR=/tmp/hook-precedence-test
mkdir -p "$CLAUDE_CONFIG_DIR"
# then a PreToolUse hook in $CLAUDE_CONFIG_DIR/settings.json that returns
# {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}
# and one command the managed guard denies. Managed settings still apply: they are
# /etc/claude-code/managed-settings.json, which CLAUDE_CONFIG_DIR does not move.
```

If `allow` from a user hook beats a managed `deny`, that is worth knowing about the guard in
general, not only about compressors.

## What this means for the compressor decision

It does not change the recommendation already on the board — skip both — and it adds a reason
that is about safety rather than value. Re-checked on 20 November while writing this:

| | RTK (`rtk-ai/rtk`) | Headroom (`headroomlabs-ai/headroom`) |
|---|---|---|
| Licence, language | Apache-2.0, Rust | Apache-2.0, Python |
| In nixpkgs | **no** | **no** — the only `headroom` there is `haskellPackages.headroom` 0.4.3.0, a licence-header manager |
| How it installs | `brew install rtk`, or `curl -fsSL …/install.sh \| sh` | `pip install headroom-ai`, `uv tool install`, `npm install` |
| Stars / forks / watchers | 87,262 / 5,617 / 214 | 80,198 / 6,288 / 213 |

Two things follow. **The reproducibility argument that put them on the list is wrong** — the plan
said both were already in nixpkgs, and neither is, so each would have to be installed
imperatively, which is the drift this repo exists to stop. And both sit in the same
fork-to-star band as the rest of the hyped entries: 0.064 and 0.078 against the 0.10–0.24 typical
of organic projects, with star-to-watcher ratios of 408:1 and 376:1 against 171:1 for
`anthropics/claude-code` measured the same day.

If one is ever trialled anyway, the open question above decides the order: start with whichever
of them does **not** rewrite tool input through `updatedInput`. For RTK that is documented — its
`PreToolUse` hook rewrites Bash commands. For Headroom it was not re-checked here, and should be
before it is preferred on that ground.
