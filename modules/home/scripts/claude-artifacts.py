#!/usr/bin/env python3
"""Browse files Claude created or edited. Defaults to the current project.

  claude-artifacts                 list artifacts for this project (newest first)
  claude-artifacts --all           every project
  claude-artifacts --kind doc      filter: doc|page|image|data|nix|code
  claude-artifacts --session ID    one session only
  claude-artifacts --prune         drop index rows whose file no longer exists
  claude-artifacts --paths         bare paths (pipe into fzf)
  claude-artifacts --json          JSON rows (for the AGS dashboard widget)
"""
import argparse
import datetime
import json
import os
import sqlite3
import subprocess
import sys

DB = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "claude-artifacts",
    "index.sqlite",
)


def project_root():
    try:
        out = subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, timeout=2)
        if out.returncode == 0:
            return out.stdout.strip()
    except OSError:
        pass
    return os.getcwd()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--kind")
    ap.add_argument("--session")
    ap.add_argument("--limit", type=int, default=50)
    ap.add_argument("--paths", action="store_true")
    ap.add_argument("--prune", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()

    if not os.path.exists(DB):
        sys.exit("No artifact index yet — it fills as Claude writes files.")
    con = sqlite3.connect(DB)

    if args.prune:
        gone = [p for (p,) in con.execute("SELECT DISTINCT path FROM events") if not os.path.exists(p)]
        con.executemany("DELETE FROM events WHERE path = ?", [(p,) for p in gone])
        con.commit()
        print(f"pruned {len(gone)} missing paths")
        return

    where, params = [], []
    if not args.all:
        where.append("project = ?")
        params.append(project_root())
    if args.kind:
        where.append("kind = ?")
        params.append(args.kind)
    if args.session:
        where.append("path IN (SELECT path FROM events WHERE session_id = ?)")
        params.append(args.session)
    sql = "SELECT path, kind, last_ts, edits, sessions FROM artifacts"
    if where:
        sql += " WHERE " + " AND ".join(where)
    sql += " ORDER BY last_ts DESC LIMIT ?"
    params.append(args.limit)

    rows = con.execute(sql, params).fetchall()
    if args.json:
        keys = ("path", "kind", "last_ts", "edits", "sessions")
        print(json.dumps([dict(zip(keys, r), exists=os.path.exists(r[0])) for r in rows]))
        return
    for path, kind, ts, edits, sessions in rows:
        if args.paths:
            print(path)
            continue
        when = datetime.datetime.fromtimestamp(ts).strftime("%Y-%m-%d %H:%M")
        mark = " " if os.path.exists(path) else "✗"
        shown = os.path.relpath(path) if not args.all else path.replace(os.path.expanduser("~"), "~")
        print(f"{mark} {when}  {kind:<5} {edits:>3}× {sessions}s  {shown}")


if __name__ == "__main__":
    main()
