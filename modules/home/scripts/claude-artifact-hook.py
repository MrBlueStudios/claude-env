#!/usr/bin/env python3
"""PostToolUse hook: record files Claude creates or edits in a local SQLite index.

Reads the hook payload on stdin. Never blocks Claude: every failure exits 0.
"""
import hashlib
import json
import os
import sqlite3
import subprocess
import sys
import time

DB = os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")),
    "claude-artifacts",
    "index.sqlite",
)
SKIP_PARTS = ("/node_modules/", "/.git/", "/.venv/", "/__pycache__/", "/.svelte-kit/", "/dist/", "/build/")
KINDS = {
    "doc": (".md", ".mdx", ".txt", ".rst", ".pdf", ".docx"),
    "page": (".html", ".htm", ".svg"),
    "image": (".png", ".jpg", ".jpeg", ".webp", ".gif"),
    "data": (".json", ".csv", ".sqlite", ".db", ".yaml", ".yml", ".toml", ".xlsx"),
    "nix": (".nix",),
}
SCHEMA = """
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY,
  ts INTEGER NOT NULL,
  session_id TEXT,
  project TEXT NOT NULL,
  path TEXT NOT NULL,
  tool TEXT NOT NULL,
  op TEXT NOT NULL,
  kind TEXT NOT NULL,
  bytes INTEGER,
  sha256 TEXT,
  branch TEXT
);
CREATE INDEX IF NOT EXISTS events_project ON events(project, ts);
CREATE INDEX IF NOT EXISTS events_path ON events(path, ts);
CREATE VIEW IF NOT EXISTS artifacts AS
  SELECT path, project, kind, MAX(ts) AS last_ts, MIN(ts) AS first_ts,
         COUNT(*) AS edits, COUNT(DISTINCT session_id) AS sessions
  FROM events GROUP BY path;
"""


def kind_of(path):
    ext = os.path.splitext(path)[1].lower()
    for kind, exts in KINDS.items():
        if ext in exts:
            return kind
    return "code"


def git(cwd, *args):
    try:
        out = subprocess.run(["git", "-C", cwd, *args], capture_output=True, text=True, timeout=1)
        return out.stdout.strip() or None
    except (OSError, subprocess.SubprocessError):
        return None


def main():
    payload = json.load(sys.stdin)
    tool = payload.get("tool_name", "")
    tin = payload.get("tool_input") or {}
    path = tin.get("file_path") or tin.get("notebook_path")
    if not path or not os.path.isfile(path) or any(p in path for p in SKIP_PARTS):
        return
    path = os.path.realpath(path)
    cwd = payload.get("cwd") or os.path.dirname(path)
    project = git(os.path.dirname(path), "rev-parse", "--show-toplevel") or cwd
    size = os.path.getsize(path)
    digest = None
    if size <= 5 * 1024 * 1024:
        with open(path, "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()

    os.makedirs(os.path.dirname(DB), exist_ok=True)
    con = sqlite3.connect(DB, timeout=2)
    con.execute("PRAGMA journal_mode=WAL")
    con.executescript(SCHEMA)
    seen = con.execute("SELECT 1 FROM events WHERE path = ? LIMIT 1", (path,)).fetchone()
    op = "edit" if seen or tool in ("Edit", "MultiEdit", "NotebookEdit") else "create"
    con.execute(
        "INSERT INTO events (ts, session_id, project, path, tool, op, kind, bytes, sha256, branch)"
        " VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        (int(time.time()), payload.get("session_id"), project, path, tool, op,
         kind_of(path), size, digest, git(project, "branch", "--show-current")),
    )
    con.commit()
    con.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # a broken index must never break a Claude session
        print(f"claude-artifact-hook: {exc}", file=sys.stderr)
    sys.exit(0)
