#!/usr/bin/env python3
"""cmode — the dashboard panes for Claude Code modes.

One binary, one subcommand per pane, so every pane shares a single palette and reads as one
system. Each pane is a Textual app sized to a Kitty split created by `claude-mode`.

Panes: tasks (what Claude is doing), brain (project/doc map), todo (my list + guide viewer),
status (spend, repo, tips), council (agent roster), roblox (Studio/MCP/Rojo + the source tree).

Design brief: clear, uncluttered, well-structured. One accent per pane, one thin rule under the
header, generous left padding, no nested boxes.

Note on mounting: Textual's remove_children() and mount() are both awaitable and deferred, so
every rebuild awaits them in order. Mounting straight after a non-awaited remove raises
DuplicateIds, which is why dynamic widgets carry classes rather than ids.
"""

import argparse
import calendar
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
import traceback
from pathlib import Path
from urllib.parse import quote

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Vertical, VerticalScroll
from textual.screen import ModalScreen
from textual.widgets import Label, ListItem, ListView, Markdown, Static, Tree

HOME = Path.home()
CLAUDE_DIR = HOME / ".claude"
TASKS_DIR = CLAUDE_DIR / "tasks"
VAULT = Path(os.environ.get("CMODE_VAULT", HOME / "project-brain"))
STATE_DIR = Path(os.environ.get("XDG_RUNTIME_DIR", "/tmp"))
COST_DIR = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "claude-cost"
OBSIDIAN_CONF = (
    Path(os.environ.get("XDG_CONFIG_HOME", HOME / ".config")) / "obsidian/obsidian.json"
)


# The kitty window running the session these panes belong to, handed over by claude-mode.
CLAUDE_WIN = os.environ.get("CMODE_CLAUDE_WIN", "")


def send_to_claude(text: str) -> bool:
    """Type `text` into the Claude Code prompt, without submitting it.

    This is the panes' half of the conversation: Claude reads what they write to disk, and they
    write into its prompt. Deliberately no trailing newline — a pane should never send a prompt
    on Léon's behalf, only compose one for him to edit and send.
    """
    if not CLAUDE_WIN:
        return False
    try:
        subprocess.run(
            ["kitten", "@", "send-text", "--match", f"id:{CLAUDE_WIN}", "--", text],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=3,
            check=False,
        )
        return True
    except (OSError, subprocess.SubprocessError):
        return False


def vault_registered() -> bool:
    """Whether Obsidian knows VAULT, which is what makes an obsidian:// URI resolve."""
    try:
        conf = json.loads(OBSIDIAN_CONF.read_text())
        target = str(VAULT.resolve())
        return any(
            str(Path(v.get("path", "")).resolve()) == target
            for v in (conf.get("vaults") or {}).values()
            if isinstance(v, dict)
        )
    except (OSError, json.JSONDecodeError, AttributeError, RuntimeError):
        return False


# --- palette -----------------------------------------------------------------
# JARVIS: near-black with a blue cast, one cyan primary, lavender for "mine", muted everything
# else. Deliberately few colours — colour carries meaning here, not decoration.
BG = "#070b10"
PANEL = "#0d1319"
EDGE = "#1b2733"
TEXT = "#c6d4e1"
DIM = "#5b6b7c"
CYAN = "#38bdf8"
LAV = "#a78bfa"
OK = "#50fa7b"
WARN = "#f1fa8c"
ERR = "#ff5555"

CSS = f"""
Screen {{ background: {BG}; color: {TEXT}; }}
#head {{ height: 1; padding: 0 1; color: {CYAN}; text-style: bold; background: {BG}; }}
#rule {{ height: 1; padding: 0 1; color: {EDGE}; }}
#body {{ padding: 0 1; background: {BG}; }}
VerticalScroll {{ scrollbar-size: 1 1; scrollbar-background: {BG}; scrollbar-color: {EDGE}; }}
/* 1fr, not auto: the list must fill the pane and scroll inside it, however many tasks there are. */
ListView {{ background: {BG}; border: none; height: 1fr; }}
ListView > ListItem {{ background: {BG}; }}
ListView > ListItem.--highlight {{ background: {PANEL}; }}
ListView:focus > ListItem.--highlight {{ background: {PANEL}; }}
Tree {{ background: {BG}; height: 1fr; }}
#body {{ height: 1fr; }}
Tree > .tree--cursor {{ background: {PANEL}; color: {CYAN}; }}
Tree > .tree--guides {{ color: {EDGE}; }}
Tree > .tree--guides-selected {{ color: {CYAN}; }}
Markdown {{ background: {BG}; }}
.empty {{ padding: 1 1; color: {DIM}; }}
#card {{
  width: 90%; max-width: 100; height: auto; max-height: 80%;
  background: {PANEL}; border: round {CYAN}; padding: 1 2;
}}
"""


def rule(width: int = 160) -> str:
    return f"[{EDGE}]{'─' * width}[/]"


def tool(name: str) -> str:
    """Absolute path of one of Léon's commands, or "" if it is not installed.

    Panes are started by `kitten @ launch`, i.e. from the Kitty *server's* environment, so PATH
    can be thinner here than in his shell. claude-mode passes its own PATH through, but fall back
    to the profile directories so a pane still works if that ever stops being true.
    """
    found = shutil.which(name)
    if found:
        return found
    for d in (
        HOME / ".nix-profile/bin",
        Path("/etc/profiles/per-user") / os.environ.get("USER", "nobody") / "bin",
        Path("/run/current-system/sw/bin"),
    ):
        p = d / name
        if p.is_file() and os.access(p, os.X_OK):
            return str(p)
    return ""


def run(cmd, cwd=None, timeout: float = 2.0) -> str:
    """Shell out defensively: a pane must never die because a command is missing."""
    try:
        out = subprocess.run(
            cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout, check=False
        )
        return out.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return ""


class PaneApp(App):
    """Shared chrome: a header, a rule, a body, and a poll loop driven by a cheap signature."""

    CSS = CSS
    TITLE_TEXT = "PANE"
    POLL = 2.0
    BINDINGS = [
        Binding("q", "quit", "quit", show=False),
        Binding("r", "force", "refresh", show=False),
    ]

    def compose(self) -> ComposeResult:
        yield Static(self.TITLE_TEXT, id="head")
        yield Static(rule(), id="rule")
        yield Vertical(id="body")

    async def on_mount(self) -> None:
        self._sig = None
        await self.refresh_pane(force=True)
        self.set_interval(self.POLL, self.refresh_pane)

    async def action_force(self) -> None:
        await self.refresh_pane(force=True)

    def set_head(self, title: str, meta: str = "") -> None:
        text = f"{title}  [{DIM}]{meta}[/]" if meta else title
        self.query_one("#head", Static).update(text)

    def signature(self):
        """Cheap value that changes only when the data changes, so we rebuild rarely."""
        return time.time() // self.POLL

    async def refresh_pane(self, force: bool = False) -> None:
        sig = self.signature()
        if not force and sig == self._sig:
            return
        self._sig = sig
        body = self.query_one("#body", Vertical)
        try:
            widgets, head = self.build()
        except Exception:
            widgets = [
                Static(
                    f"[{ERR}]pane error[/]\n{traceback.format_exc()}", classes="empty"
                )
            ]
            head = (self.TITLE_TEXT, "error")
        await body.remove_children()
        if widgets:
            await body.mount_all(widgets)
        self.set_head(*head)
        await self.after_build()

    async def after_build(self) -> None:
        """Hook for panes that need to touch a widget once it is mounted."""

    def build(self):
        """Return (widgets, (title, meta)). Pure: no mounting, so errors are easy to report."""
        raise NotImplementedError


class DetailScreen(ModalScreen):
    """Full text of one item — the panes are small, so detail gets its own surface."""

    CSS = CSS
    BINDINGS = [Binding("escape,q,enter", "dismiss", "close", show=False)]

    def __init__(self, title: str, body: str) -> None:
        super().__init__()
        self._title = title
        self._body = body

    def compose(self) -> ComposeResult:
        with VerticalScroll(id="card"):
            yield Static(f"[{CYAN}][b]{self._title}[/b][/]")
            yield Static(rule(96))
            yield Static(self._body or f"[{DIM}]no description[/]")


# --- tasks -------------------------------------------------------------------

GLYPH = {
    "completed": (f"[{OK}]✓[/]", DIM),
    "in_progress": (f"[{CYAN}]●[/]", TEXT),
    "pending": (f"[{DIM}]○[/]", DIM),
    "blocked": (f"[{WARN}]▲[/]", WARN),
}


def newest_task_dir():
    """Claude Code writes one directory of task JSON per session; take the live one."""
    if not TASKS_DIR.is_dir():
        return None
    dirs = [d for d in TASKS_DIR.iterdir() if d.is_dir() and any(d.glob("*.json"))]
    return max(dirs, key=lambda d: d.stat().st_mtime) if dirs else None


def load_tasks():
    d = newest_task_dir()
    if d is None:
        return []
    tasks = []
    for f in d.glob("*.json"):
        try:
            data = json.loads(f.read_text())
        except (OSError, json.JSONDecodeError):
            continue
        if isinstance(data, dict) and data.get("subject"):
            tasks.append(data)
    order = {"in_progress": 0, "blocked": 1, "pending": 2, "completed": 3}

    def key(t):
        try:
            num = int(t.get("id", 0) or 0)
        except (TypeError, ValueError):
            num = 0
        return (order.get(t.get("status", "pending"), 9), num)

    tasks.sort(key=key)
    return tasks


def bar(done: int, total: int, width: int = 20) -> str:
    if total <= 0:
        return f"[{EDGE}]{'━' * width}[/]"
    fill = round(width * done / total)
    return f"[{CYAN}]{'━' * fill}[/][{EDGE}]{'━' * (width - fill)}[/]"


class TasksApp(PaneApp):
    """What Claude is doing, and how far along it is."""

    TITLE_TEXT = "CLAUDE · TASKS"
    POLL = 1.5
    BINDINGS = PaneApp.BINDINGS + [Binding("enter", "detail", "detail", show=False)]

    def signature(self):
        d = newest_task_dir()
        if d is None:
            return ("none",)
        return (
            str(d),
            tuple(sorted((f.name, f.stat().st_mtime) for f in d.glob("*.json"))),
        )

    def build(self):
        self._tasks = load_tasks()
        self._keep = self._list_index()
        total = len(self._tasks)
        done = sum(1 for t in self._tasks if t.get("status") == "completed")
        if not total:
            return [Static("no active task list", classes="empty")], (
                "CLAUDE · TASKS",
                "idle",
            )

        active = next(
            (t for t in self._tasks if t.get("status") == "in_progress"), None
        )
        now = (
            (active.get("activeForm") or active.get("subject")) if active else "waiting"
        )
        items = []
        for t in self._tasks:
            glyph, colour = GLYPH.get(t.get("status", "pending"), GLYPH["pending"])
            items.append(
                ListItem(
                    Label(f"{glyph} [{colour}]{(t.get('subject') or '')[:200]}[/]")
                )
            )
        widgets = [
            Static(f"{bar(done, total)}  [{DIM}]{done}/{total}[/]"),
            Static(f"[{CYAN}]▸[/] {str(now)[:120]}"),
            Static(""),
            ListView(*items),
        ]
        return widgets, ("CLAUDE · TASKS", f"{done}/{total}")

    def _list_index(self):
        try:
            return self.query_one(ListView).index
        except Exception:
            return None

    async def after_build(self) -> None:
        keep = getattr(self, "_keep", None)
        if keep is None:
            return
        try:
            lv = self.query_one(ListView)
        except Exception:
            return
        if 0 <= keep < len(self._tasks):
            lv.index = keep

    def action_detail(self) -> None:
        idx = self._list_index()
        if idx is None or not (0 <= idx < len(self._tasks)):
            return
        t = self._tasks[idx]
        meta = f"status: {t.get('status', '?')}"
        blocked = t.get("blockedBy") or []
        if blocked:
            meta += f"   blocked by: {', '.join(str(b) for b in blocked)}"
        self.push_screen(
            DetailScreen(
                t.get("subject", "task"),
                f"[{DIM}]{meta}[/]\n\n{t.get('description', '')}",
            )
        )


# --- brain -------------------------------------------------------------------

WIKILINK = re.compile(r"\[\[([^\]|#]+)")


def vault_notes():
    """Every note in the brain vault mapped to the notes it links to."""
    if not VAULT.is_dir():
        return {}
    notes = {}
    for f in sorted(VAULT.rglob("*.md")):
        if ".obsidian" in f.parts or ".trash" in f.parts:
            continue
        try:
            notes[f] = WIKILINK.findall(f.read_text(errors="replace"))
        except OSError:
            continue
    return notes


class BrainApp(PaneApp):
    """The project brain: projects, their docs, and how they link.

    A radial mindmap is unreadable in a terminal pane, so the legible form here is a tree with
    link counts. The radial view is Obsidian's own graph over the same vault — press `o`.
    """

    TITLE_TEXT = "PROJECT · BRAIN"
    POLL = 5.0
    BINDINGS = PaneApp.BINDINGS + [
        Binding("o", "open_note", "open in obsidian", show=False),
        Binding("g", "open_graph", "graph", show=False),
        Binding("s", "send_note", "send path to claude", show=False),
    ]

    def action_send_note(self) -> None:
        """Put the highlighted note's path into Claude's prompt, for Léon to build a line around."""
        f = self._selected()
        if f is None:
            return
        if send_to_claude(f"{f} "):
            self.set_head(self.TITLE_TEXT, f"→ sent {f.stem[:24]}")
        else:
            self.set_head(self.TITLE_TEXT, "no session to send to")

    def signature(self):
        if not VAULT.is_dir():
            return ("none",)
        return tuple(
            sorted(
                (str(f.relative_to(VAULT)), f.stat().st_mtime)
                for f in VAULT.rglob("*.md")
                if ".obsidian" not in f.parts
            )
        )

    def build(self):
        notes = vault_notes()
        if not notes:
            msg = f"no vault at [{DIM}]{VAULT}[/]\nrun [b]brain-sync[/b] to build it"
            return [Static(msg, classes="empty")], ("PROJECT · BRAIN", "empty")

        tree = Tree(f"[{LAV}]brain[/]")
        tree.show_root = True
        tree.root.expand()

        # Group by top-level folder, so the shape of the vault is the shape of the tree.
        groups = {}
        for f in notes:
            rel = f.relative_to(VAULT)
            groups.setdefault(rel.parts[0] if len(rel.parts) > 1 else ".", []).append(f)

        for key in sorted(groups):
            label = "loose notes" if key == "." else key
            node = tree.root.add(f"[{CYAN}]{label}[/]  [{DIM}]{len(groups[key])}[/]")
            if key != ".":
                node.expand()
            for f in sorted(groups[key]):
                links = len(notes[f])
                suffix = f"  [{DIM}]→{links}[/]" if links else ""
                node.add_leaf(f"{f.stem}{suffix}", data=f)

        return [tree], ("PROJECT · BRAIN", f"{len(notes)} notes")

    def _selected(self):
        try:
            node = self.query_one(Tree).cursor_node
        except Exception:
            return None
        data = getattr(node, "data", None) if node is not None else None
        return data if isinstance(data, Path) else None

    def on_tree_node_selected(self, event) -> None:
        """Enter on a note fills the GUIDE pane.

        This is an event handler, not a key binding: Tree consumes Enter itself to select a node,
        so an app-level `enter` binding never fires — which is why Enter appeared to do nothing.
        """
        data = getattr(event.node, "data", None)
        if isinstance(data, Path):
            (STATE_DIR / "cmode-selection").write_text(str(data))
            self.set_head("PROJECT · BRAIN", f"→ {data.stem[:28]}")

    def action_open_note(self) -> None:
        """Open the highlighted note in Obsidian itself."""
        f = self._selected()
        if f is None:
            return
        try:
            rel = f.relative_to(VAULT)
        except ValueError:
            return
        self._obsidian(
            f"open?vault={quote(VAULT.name)}&file={quote(str(rel.with_suffix('')))}"
        )

    def action_open_graph(self) -> None:
        """Open the vault's graph view — the real radial mindmap.

        brain-sync writes the vault's workspace so Obsidian opens *on* the graph, which needs no
        community plugin. Opening the vault is therefore enough to land on the graph.
        """
        self._obsidian(f"open?vault={quote(VAULT.name)}")

    def _obsidian(self, path: str) -> None:
        # Obsidian answers obsidian:// URIs only for vaults listed in its own obsidian.json, and
        # fails with an unhelpful "can't find the vault" dialog otherwise. Say so in the pane
        # instead, because from here the key just looked dead.
        if not vault_registered():
            self.set_head("PROJECT · BRAIN", "vault not registered — run brain-sync")
            return
        try:
            subprocess.Popen(
                ["xdg-open", f"obsidian://{path}"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
            )
        except OSError:
            pass


# --- todo + guide ------------------------------------------------------------

TODO_FILE = VAULT / "Inbox" / "My Todos.md"
CHECK = re.compile(r"^(\s*[-*]\s+\[)([ xX])(\]\s*)(.*)$")


def strip_frontmatter(text: str) -> str:
    """Drop a leading YAML block so the GUIDE shows the note, not its metadata.

    Markdown has no frontmatter, so Textual renders the `---` fences as horizontal rules with a
    wall of keys between them — the first screen of every generated note was unreadable.
    """
    if not text.startswith("---"):
        return text
    end = text.find("\n---", 3)
    return text[end + 4 :].lstrip("\n") if end != -1 else text


def read_todos():
    if not TODO_FILE.is_file():
        return []
    items = []
    try:
        lines = TODO_FILE.read_text(errors="replace").splitlines()
    except OSError:
        return []
    for i, line in enumerate(lines):
        m = CHECK.match(line)
        if m:
            items.append((i, m.group(2).lower() == "x", m.group(4).strip()))
    return items


def toggle_todo(lineno: int) -> None:
    try:
        lines = TODO_FILE.read_text(errors="replace").splitlines()
    except OSError:
        return
    if not (0 <= lineno < len(lines)):
        return
    m = CHECK.match(lines[lineno])
    if not m:
        return
    flip = " " if m.group(2).lower() == "x" else "x"
    lines[lineno] = f"{m.group(1)}{flip}{m.group(3)}{m.group(4)}"
    TODO_FILE.write_text("\n".join(lines) + "\n")


class TodoApp(PaneApp):
    """My list, and the step-by-step guide Claude wrote for me."""

    TITLE_TEXT = "MY TODO"
    POLL = 2.0
    BINDINGS = PaneApp.BINDINGS + [
        Binding("space", "toggle", "toggle", show=False),
        # priority, because `tab` is Textual's own focus-next key: a plain binding never fires
        # while the ListView holds focus. `g` is the same action for anyone who expects a letter.
        Binding("tab", "swap", "guide/list", show=False, priority=True),
        Binding("g", "swap", "guide/list", show=False),
        Binding("s", "send_todo", "send to claude", show=False),
    ]

    async def action_send_todo(self) -> None:
        """Hand the highlighted todo to Claude as the next thing to work on."""
        if self._view != "list":
            return
        idx = self._list_index()
        if idx is None or not (0 <= idx < len(self._items)):
            return
        text = self._items[idx][2]
        if send_to_claude(f"{text} "):
            self.set_head("MY TODO", "→ sent to claude")
        else:
            self.set_head("MY TODO", "no session to send to")

    async def on_mount(self) -> None:
        self._view = "list"
        self._items = []
        await super().on_mount()

    def signature(self):
        sel = STATE_DIR / "cmode-selection"
        return (
            self._view,
            TODO_FILE.stat().st_mtime if TODO_FILE.is_file() else 0,
            sel.read_text(errors="replace") if sel.is_file() else "",
        )

    async def action_swap(self) -> None:
        self._view = "guide" if self._view == "list" else "list"
        await self.refresh_pane(force=True)

    def build(self):
        return self._build_guide() if self._view == "guide" else self._build_list()

    def _build_guide(self):
        sel = STATE_DIR / "cmode-selection"
        path = None
        if sel.is_file():
            candidate = Path(sel.read_text(errors="replace").strip())
            path = candidate if candidate.is_file() else None
        if path is None:
            msg = "pick a note in the BRAIN pane (Enter) to read it here"
            return [Static(msg, classes="empty")], ("GUIDE", "tab → my todo")
        self._guide_text = strip_frontmatter(path.read_text(errors="replace"))
        return [VerticalScroll(Markdown())], ("GUIDE", path.stem[:40])

    def _build_list(self):
        self._items = read_todos()
        self._keep = self._list_index()
        if not self._items:
            msg = f"no list yet at [{DIM}]{TODO_FILE.name}[/]\nrun [b]brain-sync[/b] to create it"
            return [Static(msg, classes="empty")], ("MY TODO", "empty")
        items = []
        for _, is_done, text in self._items:
            mark = f"[{OK}]✓[/]" if is_done else f"[{DIM}]○[/]"
            items.append(
                ListItem(Label(f"{mark} [{DIM if is_done else TEXT}]{text[:200]}[/]"))
            )
        done = sum(1 for _, d, _ in self._items if d)
        return [ListView(*items)], ("MY TODO", f"{done}/{len(self._items)}")

    def _list_index(self):
        try:
            return self.query_one(ListView).index
        except Exception:
            return None

    async def after_build(self) -> None:
        if self._view == "guide":
            try:
                await self.query_one(Markdown).update(getattr(self, "_guide_text", ""))
            except Exception:
                pass
            return
        keep = getattr(self, "_keep", None)
        if keep is None:
            return
        try:
            lv = self.query_one(ListView)
        except Exception:
            return
        if 0 <= keep < len(self._items):
            lv.index = keep

    async def action_toggle(self) -> None:
        if self._view != "list":
            return
        idx = self._list_index()
        if idx is None or not (0 <= idx < len(self._items)):
            return
        toggle_todo(self._items[idx][0])
        await self.refresh_pane(force=True)


# --- status ------------------------------------------------------------------


PROJECTS_DIR = CLAUDE_DIR / "projects"
RATE_CACHE = COST_DIR / "usd-eur.json"
LIMITS_FILE = COST_DIR / "limits.json"
FALLBACK_EUR = 0.92


def real_limits():
    """Claude's true 5-hour and 7-day limits, as persisted by the status line.

    These numbers exist only in the status-line payload, so claude-statusline.py mirrors them to
    limits.json on every turn. Stale or missing means the status line has not run yet.
    """
    try:
        data = json.loads(LIMITS_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data.get("rate_limits"), dict) else None


def until(epoch) -> str:
    """'3h 20m' until a reset, or empty if the stamp is missing or already past.

    The 7-day window resets days out, so days are carried rather than shown as '137h'.
    """
    try:
        left = int(epoch) - time.time()
    except (TypeError, ValueError):
        return ""
    if left <= 0:
        return ""
    mins = int(left) // 60
    days, mins = divmod(mins, 1440)
    hours, mins = divmod(mins, 60)
    if days:
        return f"{days}d {hours}h"
    return f"{hours}h {mins:02d}m" if hours else f"{mins}m"


def usd_to_eur() -> float:
    """Today's USD→EUR rate, cached for a day. Offline or blocked: fall back to a fixed rate."""
    today = time.strftime("%Y-%m-%d")
    try:
        cached = json.loads(RATE_CACHE.read_text())
        if cached.get("date") == today and cached.get("rate"):
            return float(cached["rate"])
    except (OSError, json.JSONDecodeError, TypeError, ValueError):
        pass
    out = run(
        [
            "curl",
            "-fsSL",
            "--max-time",
            "3",
            "https://api.frankfurter.dev/v1/latest?base=USD&symbols=EUR",
        ],
        timeout=4.0,
    )
    try:
        rate = float(json.loads(out)["rates"]["EUR"])
    except (json.JSONDecodeError, KeyError, TypeError, ValueError):
        return FALLBACK_EUR
    try:
        RATE_CACHE.parent.mkdir(parents=True, exist_ok=True)
        RATE_CACHE.write_text(json.dumps({"date": today, "rate": rate}))
    except OSError:
        pass
    return rate


def usage_windows(hours=(1, 5)):
    """Tokens used in the last N hours, read from the session transcripts.

    Claude Code does not expose its own rate-limit counters on disk, but every transcript line
    carries a timestamp and a usage block, so the rolling windows can be measured directly.
    Only the tail of each recently-touched file is read — these grow to megabytes.
    """
    now = time.time()
    longest = max(hours) * 3600
    totals = {h: 0 for h in hours}
    if not PROJECTS_DIR.is_dir():
        return totals
    for f in PROJECTS_DIR.rglob("*.jsonl"):
        try:
            st = f.stat()
        except OSError:
            continue
        if now - st.st_mtime > longest:
            continue
        try:
            with open(f, "rb") as fh:
                if st.st_size > 4_000_000:
                    fh.seek(st.st_size - 4_000_000)
                    fh.readline()  # drop the partial line
                blob = fh.read().decode("utf-8", errors="replace")
        except OSError:
            continue
        for line in blob.splitlines():
            if '"usage"' not in line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            usage = (rec.get("message") or {}).get("usage")
            stamp = rec.get("timestamp")
            if not isinstance(usage, dict) or not stamp:
                continue
            try:
                # Transcript stamps are UTC; timegm reads the struct as UTC, where mktime would
                # read it as local time and shift every reading by the offset.
                when = calendar.timegm(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S"))
            except (TypeError, ValueError):
                continue
            n = sum(
                usage.get(k) or 0
                for k in (
                    "input_tokens",
                    "cache_creation_input_tokens",
                    "output_tokens",
                )
            )
            for h in hours:
                if now - when <= h * 3600:
                    totals[h] += n
    return totals


def spend_today():
    """Today's ledger totals: (cost_usd, tokens, sessions).

    The ledger is written by claude-statusline.py as session<TAB>cost<TAB>tokens<TAB>project.
    `cost` is what Claude Code reports per session, which on a subscription is the equivalent
    API value of the work — not money taken from a card. The pane labels it as such.
    """
    f = COST_DIR / f"{time.strftime('%Y-%m-%d')}.tsv"
    cost, tokens, sessions = 0.0, 0, 0
    try:
        lines = f.read_text(errors="replace").splitlines()
    except OSError:
        return cost, tokens, sessions
    for line in lines:
        parts = line.split("\t")
        if len(parts) < 3:
            continue
        try:
            cost += float(parts[1])
            tokens += int(parts[2])
        except ValueError:
            continue
        sessions += 1
    return cost, tokens, sessions


def repo_state(cwd: Path):
    rows = []
    if run(["jj", "root"], cwd=cwd):
        desc = run(
            ["jj", "log", "-r", "@", "--no-graph", "-T", "description.first_line()"],
            cwd=cwd,
        )
        rows.append(("change", desc or "(no description)"))
        diff = run(["jj", "diff", "--stat"], cwd=cwd).splitlines()
        rows.append(("files", diff[-1].strip() if diff else "clean"))
    else:
        branch = run(["git", "rev-parse", "--abbrev-ref", "HEAD"], cwd=cwd)
        if branch:
            rows.append(("branch", branch))
            dirty = run(["git", "status", "--porcelain"], cwd=cwd).splitlines()
            rows.append(("files", f"{len(dirty)} changed" if dirty else "clean"))
    return rows


def meter(used: float, budget: float, width: int = 14) -> str:
    """A proportion bar that turns amber then red as the budget is approached."""
    if budget <= 0:
        return f"[{EDGE}]{'━' * width}[/]"
    frac = max(0.0, min(1.0, used / budget))
    fill = round(width * frac)
    colour = ERR if frac >= 0.9 else (WARN if frac >= 0.7 else CYAN)
    return (
        f"[{colour}]{'━' * fill}[/][{EDGE}]{'━' * (width - fill)}[/]"
        f" [{colour}]{frac * 100:3.0f}%[/]"
    )


def toks(n) -> str:
    """Token counts the way the status line writes them: 1.2M, 340k, 512."""
    try:
        n = float(n)
    except (TypeError, ValueError):
        return "—"
    if n >= 1e6:
        return f"{n / 1e6:.2f}M"
    if n >= 1e3:
        return f"{n / 1e3:.0f}k"
    return f"{n:.0f}"


TIPS = [
    "ctrl+alt+d dashboard · ctrl+alt+g roblox · ctrl+alt+n normal",
    "ctrl+alt+z maximises a pane, again restores",
    "BRAIN: enter → guide · o obsidian · g graph · s → claude",
    "TODO: space toggles · tab/g guide · s → claude prompt",
]


class StatusApp(PaneApp):
    """Spend, repo state, and the things worth knowing in this repo."""

    TITLE_TEXT = "STATUS"
    POLL = 15.0  # the usage scan reads transcript tails; no need to do it every few seconds

    def build(self):
        cwd = Path.cwd()
        state = STATE_DIR / f"claude-mode-{os.environ.get('KITTY_PID', '0')}.state"
        mode = "normal"
        if state.is_file():
            parts = state.read_text(errors="replace").split()
            mode = parts[0] if parts else "normal"

        lim = real_limits() or {}
        rl = lim.get("rate_limits") or {}
        cw = lim.get("context_window") or {}
        widgets = []

        def head(text):
            widgets.append(Static(f"[{LAV}]{text}[/]"))

        def row(label, body):
            widgets.append(Static(f"[{DIM}]{label:<8}[/]{body}"))

        # --- the limits Claude actually throttles on ---------------------------
        # These come from the status-line payload, mirrored to limits.json: they exist nowhere
        # else on disk. Without them the pane falls back to rolling windows measured from the
        # transcripts, which are honest but are not the numbers that cut you off.
        head("LIMITS")
        shown = False
        for key, label in (("five_hour", "5 hour"), ("seven_day", "7 day")):
            block = rl.get(key) or {}
            pct = block.get("used_percentage")
            if pct is None:
                continue
            left = until(block.get("resets_at"))
            row(
                label,
                f"{meter(pct, 100)}  [{DIM}]{'resets ' + left if left else ''}[/]",
            )
            shown = True
        if not shown:
            win = usage_windows()
            row("5 hour", f"{toks(win[5])} tok  [{DIM}]measured, limit unknown[/]")
            row("1 hour", f"{toks(win[1])} tok  [{DIM}]measured[/]")
            widgets.append(
                Static(f"  [{WARN}]send a message to refresh the real limits[/]")
            )

        # --- context: used and, as he asked, what is left ---------------------
        widgets.append(Static(""))
        head("CONTEXT")
        pct = cw.get("used_percentage")
        size = cw.get("context_window_size")
        used = cw.get("total_input_tokens")
        if pct is not None:
            row("window", meter(pct, 100))
        if size and used is not None:
            row(
                "",
                f"{toks(used)} used [{DIM}]·[/] {toks(size - used)} left [{DIM}]of {toks(size)}[/]",
            )
        elif size:
            row("", f"[{DIM}]of {toks(size)}[/]")

        # --- this session, and today across sessions --------------------------
        widgets.append(Static(""))
        head("SESSION")
        sess_tok = lim.get("session_tokens")
        if sess_tok:
            row("tokens", f"{toks(sess_tok)}")
        rate = usd_to_eur()
        sess_cost = lim.get("cost_usd")
        if sess_cost is not None:
            row("value", f"€{sess_cost * rate:.2f}")
        cost_usd, day_tok, sessions = spend_today()
        row(
            "today",
            f"€{cost_usd * rate:.2f} [{DIM}]· {toks(day_tok)} tok · {sessions} sess[/]",
        )
        # Said plainly, because a euro figure next to a percentage reads like a bill: on a
        # subscription nothing here is charged, it is the API-equivalent value of the work.
        widgets.append(Static(f"  [{DIM}]plan-equivalent value, not billed[/]"))

        widgets.append(Static(""))
        head("REPO")
        for key, val in [("dir", cwd.name)] + repo_state(cwd):
            row(key, str(val)[:72])

        widgets.append(Static(""))
        head("KEYS")
        for tip in TIPS:
            widgets.append(Static(f"[{DIM}]·[/] {tip}"))
        return widgets, ("STATUS", mode)


# --- council -----------------------------------------------------------------

COUNCIL_STATE = STATE_DIR / "cmode-council.json"


class CouncilApp(PaneApp):
    """The agent roster: who is on the council, and where each one stands."""

    TITLE_TEXT = "COUNCIL"
    POLL = 2.0

    def signature(self):
        return COUNCIL_STATE.stat().st_mtime if COUNCIL_STATE.is_file() else 0

    def build(self):
        if not COUNCIL_STATE.is_file():
            msg = "no council in session — run /council"
            return [Static(msg, classes="empty")], ("COUNCIL", "not sitting")
        try:
            data = json.loads(COUNCIL_STATE.read_text(errors="replace"))
        except (OSError, json.JSONDecodeError):
            return [Static("council state is unreadable", classes="empty")], (
                "COUNCIL",
                "error",
            )

        agents = data.get("agents", []) or []
        widgets = [
            Static(f"[{DIM}]goal[/]   {str(data.get('goal', ''))[:100]}"),
            Static(""),
        ]
        for a in agents:
            status = a.get("status", "thinking")
            colour = {"done": OK, "blocked": WARN, "working": CYAN}.get(status, DIM)
            widgets.append(
                Static(
                    f"[{colour}]●[/] [b]{a.get('name', '?')}[/b]  [{DIM}]{status}[/]"
                )
            )
            if a.get("stance"):
                widgets.append(Static(f"  [{DIM}]{str(a['stance'])[:110]}[/]"))
        meta = f"round {data.get('round', 0)} · {len(agents)} agents"
        return widgets, ("COUNCIL", meta)


# --- roblox ------------------------------------------------------------------
# Four things have to line up before Claude can touch Studio, and when one is missing the symptom
# is always the same unhelpful "0 tools". `roblox-doctor` reports them on demand; this pane keeps
# them on screen while the work happens, next to the tree Rojo is actually syncing.

VINEGAR = Path(os.environ.get("VINEGAR_ROOT", HOME / ".local/share/vinegar"))
ROJO_PID = STATE_DIR / "cmode-rojo.pid"
ROJO_LOG = STATE_DIR / "cmode-rojo.log"
ANSI = re.compile(r"\x1b\[[0-9;]*m")


def procs():
    """Every process as (pid, cmdline). Reading /proc rather than shelling out to pgrep keeps
    this pane free of a procps dependency — and pgrep's own argv matches its own pattern."""
    out = []
    try:
        entries = list(Path("/proc").iterdir())
    except OSError:
        return out
    for p in entries:
        if not p.name.isdigit():
            continue
        try:
            raw = (p / "cmdline").read_bytes()
        except OSError:
            continue  # the process exited between listing and reading
        if raw:
            cmd = raw.replace(b"\0", b" ").decode(errors="replace").strip()
            out.append((int(p.name), cmd))
    return out


def studio_pid():
    """Studio itself, not its browser helpers.

    Every msedgewebview2.exe carries `--webview-exe-name=RobloxStudioBeta.exe`, so a plain name
    match counts four or five Studios and reports one as running after the real one has gone.
    """
    for pid, cmd in procs():
        if "RobloxStudioBeta.exe" in cmd and "webview" not in cmd.lower():
            return pid
    return None


def rojo_serve():
    """(pid, cwd) of a running `rojo serve`, else (None, "")."""
    for pid, cmd in procs():
        parts = cmd.split()
        if (
            len(parts) >= 2
            and parts[0].rsplit("/", 1)[-1] == "rojo"
            and parts[1] == "serve"
        ):
            try:
                return pid, os.readlink(f"/proc/{pid}/cwd")
            except OSError:
                return pid, ""
    return None, ""


def studio_mcp_enabled():
    """True / False / None (never opened the Assistant), from Studio's own settings file.

    "Enable Studio as MCP server" writes ."mcp-server".enabled. The neighbouring `integrations`
    key is a *different* feature — Studio acting as an MCP client — and stays empty with the
    server toggle on, so reading it reports OFF forever.
    """
    base = VINEGAR / "appdata/Roblox/AssistantSettings"
    try:
        files = [f for f in base.iterdir() if f.suffix == ".json"]
    except OSError:
        return None
    for f in files:
        try:
            return bool(
                (json.loads(f.read_text(errors="replace")).get("mcp-server") or {}).get(
                    "enabled"
                )
            )
        except (OSError, json.JSONDecodeError, AttributeError):
            continue
    return None


def rojo_project(start: Path):
    """The Rojo project file governing `start`, searching upward, or None."""
    for d in [start, *start.parents]:
        for name in ("default.project.json", "rojo.project.json"):
            f = d / name
            if f.is_file():
                return f
    return None


# Rojo's naming convention is the only thing that says what a file becomes in the game tree.
def script_kind(f: Path) -> str:
    stem = f.name[: -len(f.suffix)]
    if stem.endswith(".server"):
        return "server"
    if stem.endswith(".client"):
        return "client"
    if stem == "init":
        return "init"
    return "module"


KIND_COLOUR = {"server": WARN, "client": CYAN, "module": DIM, "init": LAV}


class RobloxApp(PaneApp):
    """Studio, its MCP server, Rojo, and the source tree being synced into the game."""

    TITLE_TEXT = "ROBLOX · STUDIO"
    POLL = 3.0
    BINDINGS = PaneApp.BINDINGS + [
        Binding("o", "open_studio", "open studio", show=False),
        Binding("j", "toggle_rojo", "rojo serve", show=False),
        Binding("d", "doctor", "doctor", show=False),
        Binding("s", "send_path", "send path to claude", show=False),
    ]

    def signature(self):
        proj = rojo_project(Path.cwd())
        src = []
        if proj is not None:
            for f in sorted((proj.parent / "src").rglob("*")):
                if f.suffix in (".lua", ".luau") and f.is_file():
                    try:
                        src.append((str(f), f.stat().st_mtime))
                    except OSError:
                        continue
        return (studio_pid(), studio_mcp_enabled(), rojo_serve()[0], tuple(src))

    def build(self):
        sp = studio_pid()
        mcp = studio_mcp_enabled()
        rpid, rcwd = rojo_serve()

        def row(state, label, detail):
            glyph = {
                True: f"[{OK}]●[/]",
                False: f"[{ERR}]○[/]",
                None: f"[{WARN}]◐[/]",
            }[state]
            return Static(f"{glyph} [b]{label:<11}[/b] [{DIM}]{detail}[/]")

        widgets = [
            row(
                sp is not None,
                "studio",
                f"running · pid {sp}" if sp else "not running — press o",
            ),
            row(
                mcp,
                "mcp server",
                {
                    True: "enabled — Claude has Studio's tools",
                    False: "OFF — Assistant (atom icon) ⟩ … ⟩ Manage MCP Servers",
                    None: "never opened the Assistant in Studio",
                }[mcp],
            ),
            row(
                rpid is not None,
                "rojo serve",
                f"pid {rpid} · {rcwd or '?'}" if rpid else "not syncing — press j",
            ),
        ]

        proj = rojo_project(Path.cwd())
        if proj is None:
            widgets.append(
                row(False, "project", f"no Rojo project at or above {Path.cwd()}")
            )
            widgets.append(
                Static(
                    f"\n[{DIM}]`roblox-new <name>` scaffolds one[/]", classes="empty"
                )
            )
            return widgets, ("ROBLOX · STUDIO", "no project")

        root = proj.parent
        try:
            name = json.loads(proj.read_text(errors="replace")).get("name") or root.name
        except (OSError, json.JSONDecodeError, AttributeError):
            name = root.name
        try:
            servers = (
                json.loads((root / ".mcp.json").read_text()).get("mcpServers") or {}
            )
            registered = "Roblox_Studio" in servers
        except (OSError, json.JSONDecodeError, AttributeError):
            registered = False
        note = (
            ".mcp.json registers Roblox_Studio"
            if registered
            else "Roblox_Studio missing from .mcp.json"
        )
        widgets.append(row(registered, "project", f"{name}  ·  {note}"))

        # The tree Rojo syncs. Shown from disk, because disk is the source of truth in a Rojo
        # project — the live DataModel needs the MCP tools, which is Claude's half of this pane.
        tree = Tree(f"[{LAV}]{name}[/]")
        tree.show_root = True
        tree.root.expand()
        total = 0
        src = root / "src"
        groups = {}
        if src.is_dir():
            for f in sorted(src.rglob("*")):
                if f.suffix in (".lua", ".luau") and f.is_file():
                    rel = f.relative_to(src)
                    groups.setdefault(
                        rel.parts[0] if len(rel.parts) > 1 else ".", []
                    ).append(f)
        for key in sorted(groups):
            label = "src" if key == "." else key
            node = tree.root.add(f"[{CYAN}]{label}[/]  [{DIM}]{len(groups[key])}[/]")
            node.expand()
            for f in groups[key]:
                kind = script_kind(f)
                total += 1
                node.add_leaf(f"{f.name}  [{KIND_COLOUR[kind]}]{kind}[/]", data=f)
        if not total:
            widgets.append(Static(f"\n[{DIM}]no Luau under {src}[/]", classes="empty"))
            return widgets, ("ROBLOX · STUDIO", name)

        widgets.append(Static(""))
        widgets.append(tree)
        return widgets, ("ROBLOX · STUDIO", f"{name} · {total} scripts")

    # --- actions ---------------------------------------------------------------

    def _selected(self):
        try:
            node = self.query_one(Tree).cursor_node
        except Exception:
            return None
        data = getattr(node, "data", None) if node is not None else None
        return data if isinstance(data, Path) else None

    def action_send_path(self) -> None:
        """Put the highlighted script's path into Claude's prompt, for Léon to build a line around."""
        f = self._selected()
        if f is None:
            return
        if send_to_claude(f"{f} "):
            self.set_head(self.TITLE_TEXT, f"→ sent {f.name[:28]}")
        else:
            self.set_head(self.TITLE_TEXT, "no session to send to")

    def action_open_studio(self) -> None:
        """Launch Studio. The wrapper refuses a second instance and focuses the first, so this is
        safe to press twice — two Studios in one Wine prefix fight over the plugin lock."""
        bin_ = tool("roblox-studio")
        if not bin_:
            self.set_head(self.TITLE_TEXT, "roblox-studio is not installed")
            return
        try:
            subprocess.Popen(
                [bin_],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except OSError as exc:
            self.set_head(self.TITLE_TEXT, f"could not start Studio: {exc}")
            return
        # The first launch after an update sits on a cold WebView2 cache for about 35 seconds and
        # looks frozen. Say so here, because this is where the key was pressed.
        self.set_head(self.TITLE_TEXT, "starting Studio — give it up to 40s")

    def action_toggle_rojo(self) -> None:
        """Start `rojo serve` for this project, or stop the one this pane started.

        A rojo Léon started himself in another terminal is left alone: a pane keybinding should
        never kill a process it does not own.
        """
        rpid, _ = rojo_serve()
        if rpid is not None:
            mine = ROJO_PID.read_text().strip() if ROJO_PID.is_file() else ""
            if mine != str(rpid):
                self.set_head(
                    self.TITLE_TEXT, f"rojo {rpid} was not started here — left alone"
                )
                return
            try:
                os.kill(rpid, signal.SIGTERM)
            except OSError as exc:
                self.set_head(self.TITLE_TEXT, f"could not stop rojo: {exc}")
                return
            ROJO_PID.unlink(missing_ok=True)
            self.set_head(self.TITLE_TEXT, f"stopped rojo {rpid}")
            return

        proj = rojo_project(Path.cwd())
        if proj is None:
            self.set_head(self.TITLE_TEXT, "no Rojo project here")
            return
        bin_ = tool("rojo")
        if not bin_:
            self.set_head(self.TITLE_TEXT, "rojo is not installed")
            return
        try:
            with ROJO_LOG.open("w") as log:
                child = subprocess.Popen(
                    [bin_, "serve", proj.name],
                    cwd=proj.parent,
                    stdout=log,
                    stderr=subprocess.STDOUT,
                    start_new_session=True,
                )
        except OSError as exc:
            self.set_head(self.TITLE_TEXT, f"could not start rojo: {exc}")
            return
        ROJO_PID.write_text(str(child.pid))
        self.set_head(
            self.TITLE_TEXT, f"rojo serve {child.pid} — Studio ⟩ Rojo ⟩ Connect"
        )

    def action_doctor(self) -> None:
        """The full `roblox-doctor` report, which checks things this pane cannot see from here —
        the Wine prefix, StudioMCP.exe, install completeness and the Rojo plugin."""
        bin_ = tool("roblox-doctor")
        if not bin_:
            self.push_screen(
                DetailScreen("roblox-doctor", "not installed — run `nh os switch .`")
            )
            return
        out = run([bin_], timeout=30.0) or "(no output)"
        # The doctor colours its own glyphs with ANSI, which Rich prints literally, and its
        # bracketed hints would be read as Rich markup. Strip one, escape the other, then put the
        # colour back on the two glyphs that carry the meaning.
        body = ANSI.sub("", out).replace("[", r"\[")
        body = body.replace("✓", f"[{OK}]✓[/]").replace("✗", f"[{ERR}]✗[/]")
        self.push_screen(DetailScreen("roblox-doctor", body))


# --- entry -------------------------------------------------------------------

APPS = {
    "tasks": TasksApp,
    "brain": BrainApp,
    "todo": TodoApp,
    "status": StatusApp,
    "council": CouncilApp,
    "roblox": RobloxApp,
}


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="cmode", description="dashboard panes for Claude Code modes"
    )
    ap.add_argument("pane", choices=sorted(APPS), help="which pane to run")
    args = ap.parse_args()
    APPS[args.pane]().run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
