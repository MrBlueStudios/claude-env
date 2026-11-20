#!/usr/bin/env bash
# Write the user-scope MCP servers into ~/.claude.json from what Nix declares.
#
#   claude-mcp.sh <claude.json> <declared.json> [dropped-name ...]
#
# ~/.claude.json is Claude Code's own state file: account details, per-project trust decisions,
# caches, and two places where MCP servers live — `mcpServers` at the top level (user scope,
# every project) and `projects[<dir>].mcpServers` (local scope, one directory). Both drifted,
# because the only way to register a server used to be `claude mcp add`.
#
# So this owns exactly two things and touches nothing else in the file:
#
#   1. Top-level `mcpServers` becomes the declared set. A server registered by hand is removed,
#      named on stderr, and written to ~/.claude/removed-mcp-servers.json first, so "it was
#      working yesterday" has an answer that isn't a shrug. Keeping one means declaring it —
#      in the module for all four laptops, or in claude-env.mcp.personal for this one.
#   2. Local-scope copies of a declared or dropped server are removed from every project entry.
#      A server that is declared at user scope is reachable everywhere, so a local copy is at
#      best a duplicate and at worst an older pin of the same thing. Local servers that are
#      neither declared nor dropped are left alone and reported, because someone may have added
#      one on purpose and the drift that matters is the invisible kind.
#
# Written as a merge of the parsed document rather than a textual edit, and moved into place
# atomically: a half-written ~/.claude.json costs the account's session history.
set -uo pipefail

warn() { printf 'claude-mcp: %s\n' "$1" >&2; }

if [ "$#" -lt 2 ]; then
  echo "usage: claude-mcp.sh <claude.json> <declared.json> [dropped-name ...]" >&2
  exit 2
fi

target="$1"
declared="$2"
shift 2

if [ ! -r "$declared" ]; then
  warn "cannot read $declared"
  exit 2
fi

# `claude mcp add` creates the file, so a machine that has never run Claude Code has nothing to
# write into yet. Starting one here would make up an account-less state file; let Claude Code
# create its own and pick the servers up at the next switch.
if [ ! -s "$target" ]; then
  warn "$target does not exist yet — start Claude Code once, then switch again to register the MCP servers."
  exit 0
fi

if ! jq empty "$target" 2>/dev/null; then
  warn "$target is not valid JSON; left untouched. Claude Code keeps a copy under ~/.claude/backups/."
  exit 3
fi

if [ "$#" -gt 0 ]; then
  dropped_json="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
else
  dropped_json='[]'
fi

# ── what changes, before anything is written ─────────────────────────────────

# `$want | has(.)` would ask whether $want has a key named $want, because inside has() the input
# is $want and not the key — so every name is bound to a variable first.
report="$(jq -rs --argjson dropped "$dropped_json" '
  (.[0] // {}) as $live | (.[1].mcpServers // {}) as $want
  | def redundant($n): ($want | has($n)) or ($dropped | index($n));
  (($live.mcpServers // {}) | keys) as $have
  | [ ($have[] | . as $n | select(($want | has($n)) | not) | "remove user   " + $n),
      ($want | keys[] | . as $n | select(($have | index($n)) == null) | "add user      " + $n),
      ($live.projects // {} | to_entries[] | .key as $dir
        | (.value.mcpServers // {}) | keys[] | . as $n
        | if redundant($n) then "remove local  " else "keep local    " end + $n + "  (" + $dir + ")") ]
  | .[]' "$target" "$declared")"

removals="$(printf '%s\n' "$report" | grep -c '^remove user' || true)"
if [ "${removals:-0}" -gt 0 ]; then
  keep="$HOME/.claude/removed-mcp-servers.json"
  mkdir -p "$(dirname "$keep")"
  if jq -s --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
    (.[1].mcpServers // {}) as $want
    | { removedAt: $at,
        servers: ((.[0].mcpServers // {})
                  | with_entries(.key as $n | select(($want | has($n)) | not))) }' \
    "$target" "$declared" > "$keep.tmp" 2>/dev/null; then
    mv "$keep.tmp" "$keep"
    warn "removed user-scope servers were saved to $keep"
  else
    rm -f "$keep.tmp"
  fi
fi

if [ -n "$report" ]; then
  warn "MCP servers in $target:"
  while IFS= read -r line; do
    printf '  %s\n' "$line" >&2
  done <<< "$report"
fi

# ── write ────────────────────────────────────────────────────────────────────

tmp="$(mktemp)" || exit 3
if jq -s --argjson dropped "$dropped_json" '
  (.[1].mcpServers // {}) as $want
  | .[0]
  | .mcpServers = $want
  | if has("projects") then
      .projects |= with_entries(
        if (.value | type) == "object" and (.value | has("mcpServers"))
        then .value.mcpServers |= with_entries(
          .key as $n | select((($want | has($n)) or ($dropped | index($n))) | not))
        else . end)
    else . end' "$target" "$declared" > "$tmp" && [ -s "$tmp" ] && jq empty "$tmp" 2>/dev/null; then
  # Preserve the mode rather than inherit mktemp's: this file holds account details.
  chmod 600 "$tmp"
  mv "$tmp" "$target"
else
  rm -f "$tmp"
  warn "writing the declared MCP servers into $target failed; file left untouched."
  exit 3
fi
