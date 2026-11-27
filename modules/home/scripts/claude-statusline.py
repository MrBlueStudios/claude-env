#!/usr/bin/env python3
"""Claude Code status line.

    ◆ Opus · high │ nix-config@main │ ctx 42% of 1M · 420k │ cache 47m │ $1.23 · 512k tok │ today $4.56 · 2.1M tok

Reads the status-line JSON on stdin (https://code.claude.com/docs/en/statusline). A missing field
hides its segment; nothing here may crash the prompt, so every failure degrades to less output.

Session tokens are not in the stdin JSON (context_window.* is the *current* context), so they are
summed incrementally from the transcript: only bytes appended since the last refresh are parsed,
and repeated usage lines for one streamed message count once. Per-day totals live in
~/.local/state/claude-cost/YYYY-MM-DD.tsv (session, cost, tokens, project), rewritten under a lock.
Tokens counted = input + cache-creation + output; cache reads are left out (cheap, and they would
dwarf everything else).
"""

import datetime
import fcntl
import json
import os
import subprocess
import sys

STATE = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "claude-cost",
)


def rgb(hexcolor):
    r, g, b = (int(hexcolor[i : i + 2], 16) for i in (1, 3, 5))
    return f"\x1b[38;2;{r};{g};{b}m"


# Same neon accents as ~/.claude/themes/cyberpunk_dark.json
VIOLET, SKY, GREEN, RED, AMBER = (
    rgb("#a78bfa"),
    rgb("#38bdf8"),
    rgb("#50fa7b"),
    rgb("#ff5555"),
    rgb("#f1fa8c"),
)
DIM, RST = rgb("#6b7280"), "\x1b[0m"
SEP = f" {DIM}│{RST} "


def human(n):
    n = float(n)
    for unit, size in (("M", 1_000_000), ("k", 1_000)):
        if n >= size:
            value = n / size
            return (
                f"{value:.1f}{unit}".replace(".0" + unit, unit)
                if value < 10
                else f"{value:.0f}{unit}"
            )
    return f"{n:.0f}"


def get(data, *path):
    for key in path:
        if not isinstance(data, dict):
            return None
        data = data.get(key)
    return data


def session_tokens(transcript, sid):
    """Tokens used so far in this session, parsing only what was appended since last time."""
    if not transcript or not sid or not os.path.isfile(transcript):
        return None
    os.makedirs(os.path.join(STATE, "sessions"), exist_ok=True)
    state_path = os.path.join(STATE, "sessions", f"{sid}.json")
    try:
        with open(state_path) as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        st = {}
    st = {"offset": 0, "tokens": 0, "last_id": None, "last_amount": 0, **st}
    size = os.path.getsize(transcript)
    if size < st["offset"]:  # transcript replaced: start over
        st = {"offset": 0, "tokens": 0, "last_id": None, "last_amount": 0}
    with open(transcript, "rb") as fh:
        fh.seek(st["offset"])
        chunk = fh.read(size - st["offset"])
    complete = chunk.rfind(b"\n") + 1  # never parse a half-written last line
    for line in chunk[:complete].splitlines():
        try:
            msg = json.loads(line).get("message") or {}
        except ValueError:
            continue
        usage = msg.get("usage") if isinstance(msg, dict) else None
        if not isinstance(usage, dict):
            continue
        amount = sum(
            usage.get(k) or 0
            for k in ("input_tokens", "cache_creation_input_tokens", "output_tokens")
        )
        if msg.get("id") and msg.get("id") == st["last_id"]:
            st["tokens"] += (
                amount - st["last_amount"]
            )  # same streamed message: replace, don't add
        else:
            st["tokens"] += amount
        st["last_id"], st["last_amount"] = msg.get("id"), amount
    st["offset"] += complete
    tmp = f"{state_path}.tmp"
    with open(tmp, "w") as fh:
        json.dump(st, fh)
    os.replace(tmp, state_path)
    return st["tokens"]


def cache_left(transcript, now=None):
    """Seconds until the prompt cache goes cold, or None when the transcript says nothing.

    Every reply refreshes the cache, so the clock starts at the last assistant line. Its length is
    the bucket the latest cache write landed in (1 h or 5 min); with no write in the tail, 5 min.
    """
    if not transcript or not os.path.isfile(transcript):
        return None
    with open(transcript, "rb") as fh:
        start = max(0, os.path.getsize(transcript) - 262144)
        fh.seek(start)
        lines = fh.read().splitlines()[1 if start else 0 :]  # a tail read may cut the first line
    last, ttl = None, 300
    for line in reversed(lines):
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        msg = entry.get("message") if isinstance(entry, dict) else None
        usage = msg.get("usage") if isinstance(msg, dict) else None
        if entry.get("type") != "assistant" or not isinstance(usage, dict):
            continue
        if last is None:
            last = entry.get("timestamp")
        buckets = usage.get("cache_creation") or {}
        if buckets.get("ephemeral_1h_input_tokens") or buckets.get("ephemeral_5m_input_tokens"):
            ttl = 3600 if buckets.get("ephemeral_1h_input_tokens") else 300
            break
    if not last:
        return None
    try:
        sent = datetime.datetime.fromisoformat(last.replace("Z", "+00:00"))
    except ValueError:
        return None
    now = now or datetime.datetime.now(datetime.timezone.utc)
    return ttl - (now - sent).total_seconds()


def update_ledger(sid, cost, tokens, project):
    """Upsert this session's line in today's ledger; return (cost, tokens, sessions) for today."""
    os.makedirs(STATE, exist_ok=True)
    ledger = os.path.join(STATE, f"{datetime.date.today():%Y-%m-%d}.tsv")
    with open(os.path.join(STATE, ".lock"), "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        rows = {}
        try:
            with open(ledger) as fh:
                for line in fh:
                    parts = line.rstrip("\n").split("\t")
                    if len(parts) >= 3:
                        rows[parts[0]] = parts
        except OSError:
            pass
        rows[sid] = [sid, f"{cost or 0:.4f}", str(tokens or 0), project or ""]
        with open(f"{ledger}.tmp", "w") as fh:
            fh.writelines("\t".join(r) + "\n" for r in rows.values())
        os.replace(f"{ledger}.tmp", ledger)
    total_cost = sum(float(r[1]) for r in rows.values())
    total_tokens = sum(int(r[2]) for r in rows.values() if r[2].isdigit())
    return total_cost, total_tokens, len(rows)


def git(cwd, *args):
    try:
        out = subprocess.run(
            ["git", "-C", cwd, *args], capture_output=True, text=True, timeout=1
        )
        return out.stdout.strip() if out.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


def save_limits(data, sid, cost, tokens):
    """Persist the limit, context and session figures for the dashboard's STATUS pane.

    Claude's real 5-hour and 7-day limits arrive only here, in the status-line payload, and are
    written nowhere else on disk — so this is the single point where anything outside the CLI can
    learn them. Best effort: the prompt must never fail because this did.
    """
    limits = data.get("rate_limits")
    window = data.get("context_window")
    if not isinstance(limits, dict) and not isinstance(window, dict):
        return
    try:
        os.makedirs(STATE, exist_ok=True)
        payload = {
            "rate_limits": limits if isinstance(limits, dict) else {},
            "context_window": window if isinstance(window, dict) else {},
            "session_id": sid,
            "session_tokens": tokens,
            "cost_usd": cost,
            "model": get(data, "model", "display_name"),
            "written_at": int(datetime.datetime.now().timestamp()),
        }
        tmp = os.path.join(STATE, "limits.json.tmp")
        with open(tmp, "w") as fh:
            json.dump(payload, fh)
        os.replace(tmp, os.path.join(STATE, "limits.json"))
    except OSError:
        pass


def main():
    try:
        data = json.load(sys.stdin)
    except ValueError:
        data = {}

    # Computed before anything is printed so the dashboard's mirror gets the session figures too.
    sid = data.get("session_id")
    cost = get(data, "cost", "total_cost_usd")
    try:
        tokens = session_tokens(data.get("transcript_path"), sid)
    except OSError:
        tokens = None
    save_limits(data, sid, cost, tokens)

    segments = []

    model = get(data, "model", "display_name")
    effort = get(data, "effort", "level")
    if model:
        segments.append(
            f"{VIOLET}◆ {model}{RST}"
            + (f" {DIM}·{RST} {SKY}{effort}{RST}" if effort else "")
        )

    cwd = get(data, "workspace", "current_dir") or data.get("cwd")
    project = None
    if cwd and os.path.isdir(cwd):
        top = git(cwd, "rev-parse", "--show-toplevel")
        project = os.path.basename(top or cwd)
        branch = git(cwd, "branch", "--show-current")
        if not branch:  # detached HEAD, which is normal in a jj-colocated repo
            sha = git(cwd, "rev-parse", "--short", "HEAD")
            branch = f"⎇{sha}" if sha else ""
        segments.append(
            f"{GREEN}{project}{RST}"
            + (f"{DIM}@{RST}{SKY}{branch}{RST}" if branch else "")
        )

    pct = get(data, "context_window", "used_percentage")
    window = get(data, "context_window", "context_window_size")
    in_ctx = get(data, "context_window", "total_input_tokens")
    if pct is not None:
        colour = GREEN if pct < 60 else AMBER if pct < 80 else RED
        text = f"{colour}ctx {pct:.0f}%{RST}"
        if window:
            text += f"{DIM} of {human(window)}{RST}"
        if in_ctx:
            text += f" {DIM}·{RST} {human(in_ctx)}"
        segments.append(text)

    try:
        left = cache_left(data.get("transcript_path"))
    except OSError:
        left = None
    if left is not None:
        if left <= 0:
            segments.append(f"{DIM}cache cold{RST}")
        else:
            colour = GREEN if left >= 600 else AMBER if left >= 60 else RED
            segments.append(f"{colour}cache {max(1, int(left // 60 + 1))}m{RST}")

    if cost is not None or tokens:
        parts = [f"{SKY}${cost:.2f}{RST}"] if cost is not None else []
        if tokens:
            parts.append(f"{human(tokens)} tok")
        segments.append(f" {DIM}·{RST} ".join(parts))

    if sid and (cost is not None or tokens):
        try:
            day_cost, day_tokens, n = update_ledger(sid, cost, tokens, project)
            tok = f" · {human(day_tokens)} tok" if day_tokens else ""
            segments.append(
                f"{VIOLET}today ${day_cost:.2f}{RST} {DIM}{tok} · {n} sess{RST}"
            )
        except OSError:
            pass

    print(SEP.join(segments))


if __name__ == "__main__":
    try:
        main()
    except Exception:  # a status line must never take the prompt down
        print("")
