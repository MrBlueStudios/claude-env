#!/usr/bin/env python3
"""brain-sync — mirror projects and their docs into an Obsidian vault.

The vault is Claude's project-brain: one note per git repo, its docs copied in beside it, and
wikilinks between them so Obsidian's graph view becomes the mindmap. The `cmode brain` pane reads
the same vault as a tree.

Generated notes carry `cmode_generated: true` in their frontmatter and are the only files this
script overwrites — anything you write by hand in the vault is left alone.

Usage: brain-sync [--dry-run] [--roots DIR[,DIR...]] [--vault DIR]
"""

import argparse
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
DEFAULT_ROOTS = [HOME / "Projects", HOME / "projects", HOME / "dev", Path("/etc/nixos")]
DEFAULT_VAULT = Path(os.environ.get("CMODE_VAULT", HOME / "project-brain"))

MARKER = "cmode_generated: true"
MAX_DOC_BYTES = 200_000
MAX_DOCS_PER_PROJECT = 25
MAX_DEPTH = 6  # how deep under a root to look for repos
# Directories that never hold a project worth indexing; also stops vendored repos exploding.
SKIP = {
    ".git",
    ".jj",
    "node_modules",
    ".direnv",
    "venv",
    ".venv",
    "__pycache__",
    "target",
    "dist",
    "build",
    ".next",
    ".svelte-kit",
    "result",
    ".cache",
    "vendor",
    ".trash",
    ".obsidian",
    "site-packages",
    ".pytest_cache",
    ".mypy_cache",
    ".ruff_cache",
}
DOC_NAMES = ("CLAUDE.md", "README.md", "README.MD", "Readme.md", "AGENTS.md")


def slug(text: str) -> str:
    """A filename Obsidian is happy with and a wikilink can address."""
    out = re.sub(r"[\\/:*?\"<>|#^\[\]]", "-", text).strip(" .-")
    return out or "untitled"


def note_name(repo: Path, root: Path) -> str:
    """A vault-unique note name: the repo's path under its root, as one readable segment.

    Directory names collide across roots (several repos here are `webshop-backend`), and a
    collision silently overwrites a note, so the path has to be part of the name.
    """
    if repo == root:
        return slug(repo.name)
    try:
        rel = repo.relative_to(root)
    except ValueError:
        return slug(repo.name)
    return slug(" · ".join(rel.parts))


def run(cmd, cwd=None, timeout: float = 5.0) -> str:
    try:
        res = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False
        )
        return res.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


def find_repos(roots):
    """Every git repo under the roots, skipping vendored and build directories.

    Walks manually rather than globbing so SKIP prunes whole subtrees — a node_modules with its
    own checkouts inside would otherwise dominate the scan.

    Finding a repo does NOT stop the walk: ~/Projects is itself a repo with submodules, so
    pruning there would hide every project inside it. MAX_DEPTH bounds the walk instead.
    """
    repos = []
    for root in roots:
        if not root.is_dir():
            continue
        base = len(root.parts)
        for dirpath, dirnames, _ in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP]
            here = Path(dirpath)
            if len(here.parts) - base >= MAX_DEPTH:
                dirnames[:] = []
            if (here / ".git").exists():
                repos.append(here)
    return sorted(set(repos))


def project_docs(repo: Path):
    """The docs worth mirroring: the agent/readme files, plus a shallow docs/ directory."""
    found = []
    for name in DOC_NAMES:
        f = repo / name
        if f.is_file():
            found.append(f)
    docs_dir = repo / "docs"
    if docs_dir.is_dir():
        for f in sorted(docs_dir.glob("*.md")):
            if f.is_file():
                found.append(f)
    out = []
    for f in found:
        try:
            if f.stat().st_size <= MAX_DOC_BYTES:
                out.append(f)
        except OSError:
            continue
    return out[:MAX_DOCS_PER_PROJECT]


def repo_meta(repo: Path):
    remote = run(["git", "remote", "get-url", "origin"], cwd=repo)
    last = run(["git", "log", "-1", "--format=%cs %s"], cwd=repo)
    branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=repo)
    return {
        "remote": remote,
        "last": last,
        "branch": branch,
        "jj": (repo / ".jj").exists(),
    }


def frontmatter(fields) -> str:
    lines = ["---", MARKER]
    for key, val in fields.items():
        if val in (None, "", []):
            continue
        if isinstance(val, list):
            lines.append(f"{key}:")
            lines += [f"  - {v}" for v in val]
        else:
            lines.append(f"{key}: {val}")
    lines.append("---")
    return "\n".join(lines) + "\n"


def writable(path: Path) -> bool:
    """Only overwrite notes this script generated; never touch hand-written ones."""
    if not path.exists():
        return True
    try:
        return MARKER in path.read_text(errors="replace")[:400]
    except OSError:
        return False


class Writer:
    def __init__(self, dry: bool) -> None:
        self.dry = dry
        self.wrote = 0
        self.skipped = []

    def write(self, path: Path, text: str) -> None:
        if not writable(path):
            self.skipped.append(path)
            return
        if self.dry:
            self.wrote += 1
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        self.wrote += 1


OBSIDIAN_CONF = (
    Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    / "obsidian/obsidian.json"
)


def register_vault(vault: Path) -> str:
    """Tell Obsidian this folder is a vault, so `obsidian://open?vault=…` resolves.

    Obsidian only honours URIs for vaults listed in its own obsidian.json; an unregistered path
    fails with "can't find the vault for this URL", which is what the BRAIN pane's o and g keys
    were hitting. Adding the entry is what the "Open folder as vault" dialog does.

    Returns a message for the caller to print, or "" when nothing needed doing.
    """
    if not OBSIDIAN_CONF.is_file():
        return (
            f"Obsidian config not found at {OBSIDIAN_CONF}; open the vault once by hand"
        )
    try:
        conf = json.loads(OBSIDIAN_CONF.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return f"could not read {OBSIDIAN_CONF}: {exc}"
    vaults = conf.setdefault("vaults", {})
    if not isinstance(vaults, dict):
        return f"unexpected vaults block in {OBSIDIAN_CONF}; register the vault by hand"
    target = str(vault.resolve())
    for entry in vaults.values():
        if (
            isinstance(entry, dict)
            and str(Path(entry.get("path", "")).resolve()) == target
        ):
            return ""  # already known
    # Obsidian rewrites this file from its in-memory vault list when it exits, so an entry added
    # while it runs is silently dropped again. Refuse rather than report success and leave the
    # BRAIN keys still failing. It runs as Electron, so match the asar path, not a process name.
    if run(["pgrep", "-f", "share/obsidian"]):
        return (
            "Obsidian is running and would discard the change on exit — quit it and re-run "
            "brain-sync, or use its own File → Open folder as vault once"
        )
    vaults[os.urandom(8).hex()] = {
        "path": target,
        "ts": int(datetime.now(timezone.utc).timestamp() * 1000),
    }
    try:
        tmp = OBSIDIAN_CONF.with_suffix(".json.tmp")
        tmp.write_text(json.dumps(conf, indent=2))
        tmp.replace(OBSIDIAN_CONF)
    except OSError as exc:
        return f"could not register the vault with Obsidian: {exc}"
    return f"registered '{vault.name}' as a vault — the BRAIN o and g keys work now"


def sync(roots, vault: Path, dry: bool) -> int:
    repos = find_repos(roots)
    w = Writer(dry)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M")
    index_rows = {}

    for repo in repos:
        # Deepest matching root wins, and a repo that *is* a root groups under its own name.
        owning = [r for r in roots if repo == r or r in repo.parents]
        root = max(owning, key=lambda r: len(r.parts)) if owning else repo.parent
        group = slug(root.name)
        # Name by path under the root, not by directory name: several repos here are called
        # webshop-backend, and a bare name would make them overwrite each other.
        name = note_name(repo, root)
        meta = repo_meta(repo)
        docs = project_docs(repo)

        # Mirror each doc, with a backlink to its project note.
        doc_links = []
        for src in docs:
            rel = src.relative_to(repo)
            title = slug(str(rel).replace("/", " · ").removesuffix(".md"))
            dest = vault / "Projects" / name / f"{title}.md"
            body = frontmatter(
                {
                    "project": f"[[{name}]]",
                    "source": str(src),
                    "synced": now,
                }
            )
            body += f"\n> part of [[{name}]] — mirrored from `{rel}`\n\n"
            try:
                body += src.read_text(errors="replace")
            except OSError:
                continue
            w.write(dest, body)
            doc_links.append(f"Projects/{name}/{title}")

        note = frontmatter(
            {
                "type": "project",
                "path": str(repo),
                "group": group,
                "branch": meta["branch"],
                "vcs": "jj + git" if meta["jj"] else "git",
                "remote": meta["remote"],
                "synced": now,
                "tags": ["project", f"group/{group}"],
            }
        )
        note += f"\n# {repo.name}\n\n"
        note += f"- **path** `{repo}`\n"
        if meta["branch"]:
            note += f"- **branch** `{meta['branch']}`\n"
        if meta["remote"]:
            note += f"- **remote** {meta['remote']}\n"
        if meta["last"]:
            note += f"- **last commit** {meta['last']}\n"
        note += f"- **group** [[{group} (group)]]\n"
        note += "\n## Documentation\n\n"
        if doc_links:
            note += "\n".join(
                f"- [[{link}|{link.rsplit('/', 1)[-1]}]]" for link in doc_links
            )
            note += "\n"
        else:
            note += "_no CLAUDE.md, README or docs/ found_\n"
        w.write(vault / "Projects" / f"{name}.md", note)
        index_rows.setdefault(group, []).append(name)

    # One note per group, so the graph clusters instead of becoming a hairball.
    for group, names in index_rows.items():
        body = frontmatter({"type": "group", "synced": now, "tags": ["group"]})
        body += f"\n# {group}\n\n{len(names)} projects\n\n"
        body += "\n".join(f"- [[{n}]]" for n in sorted(names)) + "\n"
        w.write(vault / "Groups" / f"{group} (group).md", body)

    # Root index.
    body = frontmatter({"type": "index", "synced": now})
    body += f"\n# Project brain\n\n{len(repos)} projects across {len(index_rows)} groups.\n\n"
    for group in sorted(index_rows):
        body += f"\n## {group}\n\n"
        body += "\n".join(f"- [[{n}]]" for n in sorted(index_rows[group])) + "\n"
    w.write(vault / "Index.md", body)

    # The personal todo list the todo pane edits. Created once, then left alone — it is yours.
    todo = vault / "Inbox" / "My Todos.md"
    if not todo.exists() and not dry:
        todo.parent.mkdir(parents=True, exist_ok=True)
        todo.write_text(
            "# My Todos\n\nClaude adds steps here; the MY TODO pane toggles them with space.\n\n"
            "- [ ] Open the dashboard with /dashboard\n"
            "- [ ] Press Enter on a note in BRAIN to read it in GUIDE\n"
        )

    # Make the folder a real vault, and have it open *on the graph view* — that graph is the
    # actual radial mindmap over these notes. Written only when absent, so a layout you arrange
    # yourself is never clobbered. Graph is a core plugin, so this needs nothing installed.
    if not dry:
        conf = vault / ".obsidian"
        conf.mkdir(parents=True, exist_ok=True)
        workspace = conf / "workspace.json"
        if not workspace.exists():
            workspace.write_text(
                json.dumps(
                    {
                        "main": {
                            "id": "cmode-main",
                            "type": "split",
                            "direction": "vertical",
                            "children": [
                                {
                                    "id": "cmode-graph",
                                    "type": "leaf",
                                    "state": {"type": "graph", "state": {}},
                                }
                            ],
                        },
                        "active": "cmode-graph",
                        "lastOpenFiles": [],
                    },
                    indent=2,
                )
            )

    print(
        f"brain-sync: {len(repos)} projects, {w.wrote} notes {'planned' if dry else 'written'}"
    )
    print(f"            vault: {vault}")
    if not dry:
        note = register_vault(vault)
        if note:
            print(f"            obsidian: {note}")
    for group in sorted(index_rows):
        print(f"            {group:<24} {len(index_rows[group])} projects")
    if w.skipped:
        print(f"            left alone (hand-written): {len(w.skipped)}")
        for p in w.skipped[:10]:
            print(f"              {p}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(prog="brain-sync", description=__doc__.split("\n")[0])
    ap.add_argument(
        "--dry-run", action="store_true", help="report what would change, write nothing"
    )
    ap.add_argument("--roots", help="comma-separated project roots to scan")
    ap.add_argument("--vault", help="vault directory (default ~/project-brain)")
    args = ap.parse_args()

    roots = (
        [Path(p).expanduser() for p in args.roots.split(",")]
        if args.roots
        else [p for p in DEFAULT_ROOTS]
    )
    vault = Path(args.vault).expanduser() if args.vault else DEFAULT_VAULT
    if vault in roots or any(vault == r or r in vault.parents for r in roots):
        print(
            f"brain-sync: vault {vault} sits inside a scanned root; choose another",
            file=sys.stderr,
        )
        return 2
    return sync(roots, vault, args.dry_run)


if __name__ == "__main__":
    sys.exit(main())
