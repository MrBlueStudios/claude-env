# Layout engine for Claude Code modes.
#
# Claude Code cannot repaint its own TUI, so a "mode" is a Kitty window layout built *around* the
# live session with `kitten @` remote control (enabled in modules/home/kitty.nix). The Claude pane
# is never touched: panes are added beside it and closed again, so the session survives every
# mode switch.
#
# Modes: normal (just the chat), dashboard (panes), rapid (chat + task feed), council (agent grid),
# roblox (Studio/MCP/Rojo status + the source tree).
# Usage: claude-mode <mode>|status|panes

MODES="normal dashboard rapid council roblox"

# Kitty gives every window an id; ours is the one this script's shell runs in.
CLAUDE_WIN="${KITTY_WINDOW_ID:-}"
STATE_DIR="${XDG_RUNTIME_DIR:-/tmp}"
STATE="$STATE_DIR/claude-mode-${KITTY_PID:-0}.state"

die() {
  printf 'claude-mode: %s\n' "$1" >&2
  exit 1
}

require_kitty() {
  [ -n "$CLAUDE_WIN" ] || die "not running inside Kitty (KITTY_WINDOW_ID unset — a keybinding needs \`launch --copy-env\`)"
  [ -n "${KITTY_LISTEN_ON:-}" ] || die "Kitty remote control is off (KITTY_LISTEN_ON unset)"
  kitten @ ls >/dev/null 2>&1 || die "Kitty remote control is not responding on $KITTY_LISTEN_ON"
  resolve_claude_win
}

# The id of the window in *this tab* that is actually running Claude Code, or empty.
#
# Kitty reports every window's foreground processes, and a live session shows up as argv[0]
# `claude`. Matching on the basename keeps it honest: the panes themselves run `cmode` and
# `claude-mode`, and plenty of unrelated paths contain the word "claude".
#
# Scoped to the tab holding the window the key was pressed in, so a dashboard is always built
# around the session you are looking at, never one in some other tab.
claude_win_in_my_tab() {
  kitten @ ls 2>/dev/null | jq -r --arg me "$CLAUDE_WIN" '
    [ .[].tabs[]
      | select([.windows[].id | tostring] | index($me))
      | .windows[]
      | select([ .foreground_processes[]? | (.cmdline[0] // "") | sub(".*/"; "") ]
               | index("claude"))
      | .id ] | first // empty' 2>/dev/null
}

# A mode is a view of a live session, so refuse to build one where there is no session. Without
# this the keybinding happily decorated any terminal — panes polling a session that wasn't there.
require_claude() {
  win=$(claude_win_in_my_tab)
  if [ -z "$win" ]; then
    die "no Claude Code session in this tab — a mode is a live view of one, so start \`claude\` here first"
  fi
  # Also fixes the pane-focus case: pressing the key inside a pane would otherwise split that
  # pane and nest the dashboard inside itself.
  CLAUDE_WIN="$win"
}

# Lenient version for teardown and verify, which must keep working even if the session has since
# exited: prefer the real session window, else anything that is not one of our own panes.
resolve_claude_win() {
  win=$(claude_win_in_my_tab)
  if [ -n "$win" ]; then
    CLAUDE_WIN="$win"
    return 0
  fi
  if ! kitten @ ls 2>/dev/null |
    jq -e --arg id "$CLAUDE_WIN" '[.[].tabs[].windows[]
        | select((.id|tostring) == $id) | .user_vars.cmode_pane] | any' >/dev/null 2>&1; then
    return 0 # not a pane: the environment was right
  fi
  chat=$(kitten @ ls 2>/dev/null | jq -r --arg id "$CLAUDE_WIN" '
    [.[].tabs[] | select([.windows[].id | tostring] | index($id))
      | .windows[] | select(.user_vars.cmode_pane == null) | .id] | first // empty' 2>/dev/null)
  [ -n "$chat" ] && CLAUDE_WIN="$chat"
  return 0
}

# `kitten @ launch` starts the child from the *kitty server's* environment, not ours, so a bare
# `cmode` is not necessarily on its PATH (it is on ours, via this wrapper's runtimeInputs).
# Resolve it here and launch panes by absolute path.
CMODE_BIN="$(command -v cmode 2>/dev/null || true)"

require_cmode() {
  [ -n "$CMODE_BIN" ] || die "cmode is not on PATH — run \`nh os switch .\` to install the panes"
}

# --- state -------------------------------------------------------------------
# One line: "<mode> <id> <id> ...". Only panes we created are listed, so teardown can never
# close the Claude pane or a window the user opened themselves.

state_mode() {
  if [ -s "$STATE" ]; then
    cut -d' ' -f1 "$STATE"
  else
    echo normal
  fi
}

state_panes() {
  if [ -s "$STATE" ]; then
    cut -s -d' ' -f2- "$STATE"
  fi
}
state_write() {
  mode="$1"
  shift
  printf '%s %s\n' "$mode" "$*" >"$STATE"
}

# A pane id we recorded may already be gone (user closed it). Keep only ids Kitty still knows.
# jq prints one id per line, so flatten to spaces before the padded substring match below.
live_panes() {
  live=$(kitten @ ls 2>/dev/null | jq -r '.[].tabs[].windows[].id' 2>/dev/null | tr '\n' ' ')
  for id in $(state_panes); do
    case " $live " in *" $id "*) printf '%s ' "$id" ;; esac
  done
}

teardown() {
  for id in $(live_panes); do
    [ "$id" = "$CLAUDE_WIN" ] && continue # never close the session we live in
    kitten @ close-window --match "id:$id" >/dev/null 2>&1 || true
  done
  state_write normal
}

# --- layout primitives -------------------------------------------------------
# `kitten @ launch` prints the new window id. --dont-take-focus keeps the cursor in the chat.

# `--match` on launch picks the *tab*, not the window to split: kitty always splits whatever is
# focused. With --dont-take-focus the focus never moves, so without this explicit focus every
# split lands on the same pane — which is what halved the task pane twice instead of the chat.
pane() {
  location="$1"
  anchor="$2"
  label="$3"
  shift 3
  kitten @ focus-window --match "id:$anchor" >/dev/null 2>&1
  kitten @ launch \
    --location="$location" \
    --dont-take-focus \
    --cwd="${CMODE_CWD:-$PWD}" \
    --var "cmode_pane=$label" \
    --title "$label" \
    `# the kitty server's PATH is not Léon's: without this a pane cannot find roblox-doctor,` \
    `# rojo or roblox-studio, and its keys look dead` \
    --env "PATH=$PATH" \
    `# lets a pane type into the session's prompt (cmode's send_to_claude), which is what` \
    `# makes these panes usable rather than decorative` \
    --env "CMODE_CLAUDE_WIN=$CLAUDE_WIN" \
    -- "$@" 2>/dev/null
}

# Kitty's splits layout can only put a *new* window below the one it splits, never above, so the
# chat cannot be pushed down by splitting. Instead we send the new pane to an edge and let the
# chat keep the rest. `move_to_screen_edge` acts on the focused window, hence the focus dance.
to_edge() {
  kitten @ focus-window --match "id:$1" >/dev/null 2>&1
  kitten @ action layout_action move_to_screen_edge "$2" >/dev/null 2>&1
}

# Which window sits in the given direction from the chat. Lets the layout be checked rather than
# assumed — `kitten @ ls` reports no geometry, but neighbour matching answers the same question.
neighbour_of_claude() {
  kitten @ focus-window --match "id:$CLAUDE_WIN" >/dev/null 2>&1
  kitten @ ls --match "neighbor:$1" 2>/dev/null |
    jq -r '.[].tabs[].windows[] | "\(.id):\(.title)"' 2>/dev/null | head -1
}

pane_lines() {
  kitten @ ls 2>/dev/null | jq -r ".[].tabs[].windows[]|select(.id==$1)|.lines" 2>/dev/null | head -1
}

# Léon's chosen shape: the chat is the tall pane, so the task strip is kept short. Resize by
# measurement, not by a fixed number of steps — a blind loop crushed this pane to one line,
# because how much a single increment moves depends on the split tree.
resize_toward() {
  id="$1"
  target="$2"
  step="$3"
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    have=$(pane_lines "$id")
    case "$have" in '' | *[!0-9]*) return ;; esac
    if [ "$step" -lt 0 ]; then
      [ "$have" -le "$target" ] && return
    else
      [ "$have" -ge "$target" ] && return
    fi
    kitten @ resize-window --match "id:$id" --axis vertical --increment "$step" >/dev/null 2>&1 || return
    after=$(pane_lines "$id")
    [ "$after" = "$have" ] && return # kitty refused; we are at the limit
  done
}

resize_to() { resize_toward "$1" "$2" -2; }
grow_to() { resize_toward "$1" "$2" 2; }

finish() {
  kitten @ focus-window --match "id:$CLAUDE_WIN" >/dev/null 2>&1
}

# --- modes -------------------------------------------------------------------

mode_normal() {
  teardown
  kitten @ goto-layout fat >/dev/null 2>&1
  finish
  echo "mode: normal — just the chat."
}

# ┌───────────┬───────────┬───────────┐
# │ CLAUDE·   │ MY TODO   │ PROJECT·  │
# │  TASKS    │  + GUIDE  │  BRAIN    │
# ├───────────┴──┬────────┴───────────┤
# │ ▸ CLAUDE CODE│ STATUS             │
# │   (you type) │                    │
# └──────────────┴────────────────────┘
#
# Built in this order for a reason: sending the task pane to the top edge leaves the chat as a
# full-width bottom strip, and the final vsplit off the chat is what makes it bottom-*left*.
mode_dashboard() {
  teardown
  # Record the mode before the panes start: the status pane reads this file on its first frame,
  # and would otherwise label itself "normal" until its next poll.
  state_write "$MODE_NAME"
  kitten @ goto-layout splits >/dev/null 2>&1

  # 1. A sibling below the chat, then sent to the top edge; the chat keeps the whole bottom.
  tasks=$(pane hsplit "$CLAUDE_WIN" tasks "$CMODE_BIN" tasks)
  [ -n "$tasks" ] || die "could not create the task pane (is \`cmode\` on PATH?)"
  to_edge "$tasks" top

  # 2. Three across the top: tasks, then todo, with brain ending up in the right-hand corner.
  todo=$(pane vsplit "$tasks" todo "$CMODE_BIN" todo)
  brain=$(pane vsplit "$todo" brain "$CMODE_BIN" brain)

  # 3. The last split halves the chat's strip: chat bottom-left, status bottom-right.
  status=$(pane vsplit "$CLAUDE_WIN" status "$CMODE_BIN" status)

  # The chat is the tall pane. Only the chat is resized: the split tree groups panes into rows,
  # so resizing a right-column pane vertically drags the whole row boundary with it.
  grow_to "$CLAUDE_WIN" 24
  state_write dashboard "$tasks" "$brain" "$todo" "$status"
  finish
  echo "mode: dashboard — tasks, brain, todo+guide, status. /normal to collapse."
}

# Rapid-fire questions: the chat stays dominant, with only the task feed visible so Léon can see
# what the background agent is doing while answering.
mode_rapid() {
  teardown
  # Record the mode before the panes start: the status pane reads this file on its first frame,
  # and would otherwise label itself "normal" until its next poll.
  state_write "$MODE_NAME"
  kitten @ goto-layout splits >/dev/null 2>&1
  tasks=$(pane vsplit "$CLAUDE_WIN" tasks "$CMODE_BIN" tasks)
  [ -n "$tasks" ] || die "could not create the task pane (is \`cmode\` on PATH?)"
  state_write rapid "$tasks"
  finish
  echo "mode: rapid — chat + live task feed. Say 'end rapid' to stop the questions."
}

# Council: the agent roster beside the chat, with the task feed as a strip on top.
mode_council() {
  teardown
  # Record the mode before the panes start: the status pane reads this file on its first frame,
  # and would otherwise label itself "normal" until its next poll.
  state_write "$MODE_NAME"
  kitten @ goto-layout splits >/dev/null 2>&1
  tasks=$(pane hsplit "$CLAUDE_WIN" tasks "$CMODE_BIN" tasks)
  [ -n "$tasks" ] || die "could not create the task pane (is \`cmode\` on PATH?)"
  to_edge "$tasks" top
  agents=$(pane vsplit "$CLAUDE_WIN" council "$CMODE_BIN" council)
  resize_to "$tasks" 9
  state_write council "$tasks" "$agents"
  finish
  echo "mode: council — agent roster + task feed. /normal to collapse."
  # The chair writes the roster here; the COUNCIL pane renders whatever it finds.
  echo "council state: $STATE_DIR/cmode-council.json"
}

# Roblox: Studio/MCP/Rojo state and the synced source tree beside the chat, task feed on top.
#
# ┌──────────────────────────────┐
# │ CLAUDE·TASKS                 │
# ├───────────────┬──────────────┤
# │ ▸ CLAUDE CODE │ ROBLOX·      │
# │   (you type)  │   STUDIO     │
# └───────────────┴──────────────┘
#
# Same build order as council, for the same reason: the task pane goes to the top edge so the
# chat keeps the whole bottom strip, and the last vsplit makes the chat bottom-*left*.
mode_roblox() {
  teardown
  # Record the mode before the panes start: the status pane reads this file on its first frame,
  # and would otherwise label itself "normal" until its next poll.
  state_write "$MODE_NAME"
  kitten @ goto-layout splits >/dev/null 2>&1
  tasks=$(pane hsplit "$CLAUDE_WIN" tasks "$CMODE_BIN" tasks)
  [ -n "$tasks" ] || die "could not create the task pane (is \`cmode\` on PATH?)"
  to_edge "$tasks" top
  rbx=$(pane vsplit "$CLAUDE_WIN" roblox "$CMODE_BIN" roblox)
  resize_to "$tasks" 9
  state_write roblox "$tasks" "$rbx"
  finish
  echo "mode: roblox — Studio/MCP/Rojo state + the synced tree. /normal to collapse."
  echo "keys in the ROBLOX pane: o open Studio · j rojo serve · d doctor · s send path to Claude"
}

# --- entry -------------------------------------------------------------------

case "${1:-status}" in
  status)
    printf 'mode: %s\n' "$(state_mode)"
    printf 'panes: %s\n' "$(live_panes)"
    ;;
  panes) live_panes && echo ;;
  verify)
    # Report the chat's neighbours, so the layout can be checked instead of assumed.
    require_kitty
    printf 'mode: %s\n' "$(state_mode)"
    for dir in top bottom left right; do
      printf '%-7s %s\n' "$dir" "$(neighbour_of_claude "$dir")"
    done
    finish
    ;;
  normal)
    require_kitty
    mode_normal
    ;;
  dashboard | rapid | council | roblox)
    require_kitty
    require_claude
    require_cmode
    MODE_NAME="$1"
    "mode_${1}"
    ;;
  *) die "unknown mode '$1' (want one of: $MODES status panes)" ;;
esac
