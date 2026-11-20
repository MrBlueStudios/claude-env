#!/usr/bin/env bash
# claude-vet — what a Claude Code plugin or skill tree would bring onto this machine.
#
#   claude-vet <path>                     vet a checkout before installing it
#   claude-vet --exemptions <file> <path> use a different exemption list
#
# It reports identity, hooks, code surface, outbound addresses and context cost, and exits 1
# when it finds something that must not land unreviewed. Like compliance-scan it finds
# *candidates*: a hit is not proof of malice, and a clean run is not an endorsement. The one
# thing it is strict about is a hook that runs on its own — see BLOCKING below.
set -uo pipefail

EXEMPTIONS="${CLAUDE_VET_EXEMPTIONS:-docs/vet-exemptions.md}"
while [ $# -gt 0 ]; do
  case "$1" in
    --exemptions) EXEMPTIONS="${2:?--exemptions needs a file}"; shift 2 ;;
    -h|--help) sed -n '2,9p' "$0" | sed 's/^# \?//'; exit 0 ;;
    *) break ;;
  esac
done

ROOT="${1:-}"
if [ -z "$ROOT" ] || [ ! -d "$ROOT" ]; then
  echo "claude-vet: give it a directory to vet (a plugin checkout or a skills tree)" >&2
  exit 2
fi
ROOT="$(cd "$ROOT" && pwd)"
FAILURES=0

# The default is relative, so running this from outside a claude-env checkout — which is the
# normal case for the shipped command — would otherwise point people at a path that means
# nothing from where they are standing. Resolve it, and when there is no such file say where one
# would have to go rather than naming a file that is not there.
if [ -f "$EXEMPTIONS" ]; then
  EXEMPTIONS="$(cd "$(dirname "$EXEMPTIONS")" && pwd)/$(basename "$EXEMPTIONS")"
  WHERE="$EXEMPTIONS"
else
  WHERE="docs/vet-exemptions.md in a claude-env checkout (or the file in CLAUDE_VET_EXEMPTIONS)"
fi

# Hooks that fire without the user doing anything: the whole session, or every prompt, or every
# subagent. A plugin with one of these runs code on input it was never handed deliberately, so it
# is the one thing that blocks rather than warns.
BLOCKING='SessionStart|UserPromptSubmit|SubagentStart'
# The rest still run code, but only in response to a tool call or the end of a turn.
OTHER_HOOKS='PreToolUse|PostToolUse|SessionEnd|Stop|SubagentStop|PreCompact|Notification'

RG=(rg --no-heading --color=never --hidden --glob '!.git' --glob '!node_modules' --glob '!*.lock')
CODE=("${RG[@]}" --glob '!*.md' --glob '!*.txt' --glob '!LICENSE*')

say()  { printf '\n%s\n' "$1"; }
high() { FAILURES=$((FAILURES + 1)); printf '\n[BLOCK] %s\n' "$1"; }
warn() { printf '\n[NOTE]  %s\n' "$1"; }

echo "claude-vet: $ROOT"

# ── identity ─────────────────────────────────────────────────────────────────
MANIFEST=""
for m in "$ROOT/.claude-plugin/plugin.json" "$ROOT/plugin.json"; do
  # plugin.json at the root is sometimes a two-line pointer; the real one is under .claude-plugin
  [ -f "$m" ] && [ "$(jq -r 'has("name") // false' "$m" 2>/dev/null)" = true ] && { MANIFEST="$m"; break; }
done

NAME="$(basename "$ROOT")"
if [ -n "$MANIFEST" ]; then
  NAME="$(jq -r '.name // empty' "$MANIFEST")"
  say "Identity"
  jq -r '"  name:    \(.name // "—")
  version: \(.version // "—")
  author:  \(.author.name // .author // "— NONE NAMED")
  url:     \(.author.url // .homepage // .repository // "—")
  licence: \(.license // "— not declared in the manifest")"' "$MANIFEST"
else
  say "Identity"
  echo "  no plugin manifest — vetting as a plain skills/rules tree ($NAME)"
fi

# A plugin is often a subdirectory of a monorepo that carries the licence at its root
# (sveltejs/ai-tools does), so walk up as well — but never past $HOME.
LIC=""
d="$ROOT"
while [ -n "$d" ] && [ "$d" != "/" ] && [ "$d" != "$HOME" ]; do
  # -type f matters: projects following the REUSE convention (Serena does) keep a LICENSES/
  # *directory* of SPDX texts, and reading a directory is an error, not a licence.
  LIC="$(find "$d" -maxdepth 1 -type f \( -iname 'LICENSE*' -o -iname 'COPYING*' \) -print -quit 2>/dev/null)"
  [ -n "$LIC" ] && break
  d="$(dirname "$d")"
done
# A LICENSES/ directory is the REUSE convention for a repo whose parts are under different
# terms — Serena's SolidLSP is MIT while the application is GPL-3.0-or-later. That distinction
# decides whether anything here can be vendored into a public repo, so it is said out loud
# rather than left to whoever opens the root LICENSE and sees one name.
SPDX_DIR="$(find "$ROOT" -maxdepth 2 -type d -name LICENSES -print -quit 2>/dev/null)"
if [ -n "$SPDX_DIR" ]; then
  printf '  licences: %s holds %s SPDX text(s): %s\n' \
    "${SPDX_DIR#"$ROOT"/}" "$(find "$SPDX_DIR" -type f | wc -l)" \
    "$(find "$SPDX_DIR" -type f -printf '%f ' 2>/dev/null | sed 's/\.txt//g')"
  warn "Parts of this tree are under different licences. Check which one covers the part you want before vendoring any of it."
fi

if [ -n "$LIC" ]; then
  printf '  LICENSE: %s — %s%s\n' \
    "$(basename "$LIC")" \
    "$(head -3 "$LIC" | tr -d '\r' | grep -m1 -oiE '(MIT|Apache[^ ]*|BSD[^ ]*|GNU [A-Za-z ]*Public License|MPL|ISC)' || echo 'unrecognised, read it')" \
    "$([ "$d" = "$ROOT" ] || echo " (found at $d, not in the plugin itself)")"
elif [ -f "$EXEMPTIONS" ] && rg -q "^\s*-?\s*\`?$NAME\`?\s+LICENSE\b.{10,}" "$EXEMPTIONS" 2>/dev/null; then
  echo "  LICENSE: none in this tree, exempted in $EXEMPTIONS"
else
  high "No LICENSE anywhere above this tree. This repo is public, so vendoring an unlicensed tree is a real problem, not a formality. If the licence lives in the upstream repo root, record it as \"$NAME LICENSE — <where it is>\" in $WHERE."
fi

if [ -n "$MANIFEST" ] && [ "$(jq -r '(.author.name // .author // "") | length' "$MANIFEST")" = 0 ]; then
  high "No named author in the manifest. The crew's bar is an official or identifiable author."
fi

# ── inventory and projected context cost ─────────────────────────────────────
# A skill is any directory holding a SKILL.md. Packs disagree about depth — some are
# skills/<name>/, mattpocock's are skills/<category>/<name>/ — so depth is not the test.
# What is excluded is the per-harness copies (.openclaw, .codex-plugin, …) that ship the same
# skills again for Codex, Gemini and the rest, and anything under tests or evals.
SKILLS="$(find "$ROOT" -name SKILL.md -not -path '*/node_modules/*' 2>/dev/null \
  | grep -vE '/(\.openclaw|\.agents|\.codex-plugin|\.gemini|\.opencode|\.cursor|\.windsurf|\.kiro|\.qoder|\.grok-plugin|\.kimi-plugin|\.devin-plugin|tests|evals)/' \
  | wc -l)"
AGENTS="$(find "$ROOT/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l)"
COMMANDS="$(find "$ROOT/commands" -maxdepth 1 \( -name '*.md' -o -name '*.toml' \) 2>/dev/null | wc -l)"
say "Inventory"
printf '  skills: %s   agents: %s   commands: %s\n' "$SKILLS" "$AGENTS" "$COMMANDS"
if [ "$SKILLS" -gt 0 ]; then
  # 64 tokens per skill, measured on 2026-11-19 by enabling and disabling superpowers
  # (research/context-budget.md finding 10). Projected, not measured for this tree.
  printf '  projected always-on: ~%s tokens (%s skills x 64, measured rate)\n' "$((SKILLS * 64))" "$SKILLS"
  [ "$SKILLS" -gt 20 ] && warn "$SKILLS skills is a large always-on bill. Take the ones you want, not the catalogue."
fi

# ── hooks ────────────────────────────────────────────────────────────────────
say "Hooks"
HOOK_JSON="$(find "$ROOT" -name '*.json' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null)"
FOUND_HOOKS=""
if [ -n "$HOOK_JSON" ]; then
  # a hook config keys its events at the top of a "hooks" object; match the key, not a mention
  FOUND_HOOKS="$(echo "$HOOK_JSON" | tr '\n' '\0' | xargs -0 -r rg -o --no-filename \
    "\"($BLOCKING|$OTHER_HOOKS)\"\\s*:" 2>/dev/null | tr -d '":' | sort -u)"
fi
if [ -z "$FOUND_HOOKS" ]; then
  echo "  none declared"
else
  echo "$FOUND_HOOKS" | sed 's/^/  /'
  for ev in $FOUND_HOOKS; do
    if echo "$ev" | grep -qE "^($BLOCKING)$"; then
      if [ -f "$EXEMPTIONS" ] && rg -q "^\s*-?\s*\`?$NAME\`?\s+$ev\b.{10,}" "$EXEMPTIONS" 2>/dev/null; then
        echo "  ($ev is exempted in $EXEMPTIONS)"
      else
        high "$ev hook: runs on its own, on input nobody handed it. Write an exemption in $WHERE (\"$NAME $ev — <reason>\") or do not install this."
      fi
    fi
  done
fi

# ── code surface ─────────────────────────────────────────────────────────────
say "Code surface"
surface() { # label pattern
  local out
  out="$("${CODE[@]}" --line-number -o -e "$2" "$ROOT" 2>/dev/null | cut -c1-160 | head -6)"
  [ -z "$out" ] && return
  printf '  %s:\n%s\n' "$1" "$(echo "$out" | sed 's|^'"$ROOT"'/|    |')"
}
surface "process spawning" 'child_process|spawnSync|execSync|\bspawn\(|\bexecFile\(|subprocess\.|os\.system'
surface "network calls"    '\bfetch\(|XMLHttpRequest|https?\.request|urllib|requests\.(get|post)|WebSocket|axios'
surface "install pipes"    'curl[^|]*\|\s*(ba)?sh|wget[^|]*\|\s*(ba)?sh|iwr[^|]*\|\s*iex'

ENVS="$("${CODE[@]}" -o -e 'process\.env\.[A-Z_][A-Z_0-9]*' -e "os\.environ\[['\"][A-Z_][A-Z_0-9]*" -e 'getenv\("[A-Z_][A-Z_0-9]*' "$ROOT" 2>/dev/null \
  | grep -oE '[A-Z_][A-Z_0-9]{2,}' | sort -u | tr '\n' ' ')"
[ -n "$ENVS" ] && printf '  environment read: %s\n' "$ENVS"

ALL_HOSTS="$("${CODE[@]}" -o -e 'https?://[a-zA-Z0-9.-]+' "$ROOT" 2>/dev/null \
  | sed 's|.*https\?://||' | grep -vE '^(localhost|127\.|0\.0\.0\.0)' | sort -u)"
N_HOSTS="$(echo "$ALL_HOSTS" | grep -c . || true)"
if [ "$N_HOSTS" -gt 0 ]; then
  printf '  outbound addresses in code (%s): %s\n' "$N_HOSTS" "$(echo "$ALL_HOSTS" | head -15 | tr '\n' ' ')"
  if [ "$N_HOSTS" -gt 15 ]; then
    echo "    … $((N_HOSTS - 15)) more; rerun with CLAUDE_VET_HOSTS=all to see them"
    [ "${CLAUDE_VET_HOSTS:-}" = all ] && echo "$ALL_HOSTS" | sed 's/^/    /'
    # Hundreds of hosts is usually a brand/icon lookup table rather than a call site, which is
    # exactly what it is in taste-skill. Say so instead of implying hundreds of exfil paths.
    warn "$N_HOSTS distinct addresses is a lot. Check whether they are call sites or just a data table (an icon or brand registry) before reading anything into the count."
  else
    warn "Check each address above. A plugin that can reach the network can send your prompts to it."
  fi
fi

MCP="$(find "$ROOT" -name '.mcp.json' -o -name 'mcp.json' 2>/dev/null | head -3)"
[ -n "$MCP" ] && { printf '  declares MCP servers: %s\n' "$(echo "$MCP" | tr '\n' ' ')"; \
  warn "MCP servers are registered imperatively by an installer. Declare them in mcp.nix instead."; }

# ── verdict ──────────────────────────────────────────────────────────────────
echo
if [ "$FAILURES" -gt 0 ]; then
  echo "claude-vet: $FAILURES blocking finding(s). Not cleared to install."
  exit 1
fi
echo "claude-vet: no blocking findings. Read the notes above before installing."
exit 0
