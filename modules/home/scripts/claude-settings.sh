#!/usr/bin/env bash
# Merge the generated Claude Code settings into ~/.claude/settings.json.
#
#   claude-settings.sh <settings.json> <base.json> <pinned.json> <floating.json>
#
# The file stays writable, so /config, /permissions and "don't ask again" keep working: the
# generated keys are deep-merged on top of whatever is there. Two jobs go beyond that merge.
#
# The repo owns `enabledPlugins` and `extraKnownMarketplaces` outright. Both keys are dropped
# from the file before the merge, so a plugin installed by hand on one laptop disappears at the
# next switch instead of living on invisibly — which is the drift ct-plugin-channel exists to
# close. Anything meant to survive is declared in the module, or per-machine through
# claude-env.plugins.personal, and arrives here inside <base.json> like everything else.
# Removals are named on stderr: a silent one is how people stop trusting a generated file.
#
# Pinning a marketplace to a commit (`ref` set to a full SHA) needs Claude Code 2.1.324 or
# newer; an older version refuses to load a marketplace pinned that way and its plugins stop
# loading with it. So the caller passes both forms and this script picks by the version actually
# installed. The pins then start applying the moment a machine crosses that version, with no
# edit here, and until then the only cost is a warning.
set -uo pipefail

MIN_VERSION=2.1.324

warn() { printf 'claude-settings: %s\n' "$1" >&2; }

if [ "$#" -ne 4 ]; then
  echo "usage: claude-settings.sh <settings.json> <base.json> <pinned.json> <floating.json>" >&2
  exit 2
fi

settings="$1"
base="$2"
pinned="$3"
floating="$4"

for f in "$base" "$pinned" "$floating"; do
  if [ ! -r "$f" ]; then
    warn "cannot read $f"
    exit 2
  fi
done

if [ ! -s "$settings" ]; then
  mkdir -p "$(dirname "$settings")" || exit 3
  printf '{}\n' > "$settings" || exit 3
fi

if ! jq empty "$settings" 2>/dev/null; then
  warn "$settings is not valid JSON; left untouched. Fix it, then switch again."
  exit 3
fi

# ── which form of the marketplace sources applies here ───────────────────────

have="$("${CLAUDE_BIN:-claude}" --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+){1,3}' | head -1)"
overlay="$pinned"

if [ -z "$have" ]; then
  overlay="$floating"
  warn "no Claude Code version to read (tried '${CLAUDE_BIN:-claude} --version'), so marketplaces are left unpinned."
elif [ "$(printf '%s\n%s\n' "$MIN_VERSION" "$have" | sort -V | head -1)" != "$MIN_VERSION" ]; then
  overlay="$floating"
  warn "Claude Code $have is older than $MIN_VERSION, the first version that can load a marketplace pinned to a commit, so marketplaces are left unpinned. 'nix flake update' to cross it."
fi

# ── name what the merge is about to remove ───────────────────────────────────

dropped="$(jq -rs '
  (.[1].enabledPlugins // {}) as $plugins
  | (.[2].extraKnownMarketplaces // {}) as $markets
  | [ ((.[0].enabledPlugins // {}) | keys[] | select(in($plugins) | not) | "plugin       " + .),
      ((.[0].extraKnownMarketplaces // {}) | keys[] | select(in($markets) | not) | "marketplace  " + .) ]
  | .[]' "$settings" "$base" "$overlay" 2>/dev/null)"

if [ -n "$dropped" ]; then
  warn "removing entries from $settings that claude-env does not declare:"
  while IFS= read -r line; do
    printf '  %s\n' "$line" >&2
  done <<< "$dropped"
  warn "to keep one, declare it in modules/home/settings.nix (all four laptops) or in claude-env.plugins.personal (this machine)."
fi

# ── merge ────────────────────────────────────────────────────────────────────
#
# The generated keys win on themselves and the rest of the file is kept, except for the three
# keys deleted here: the two the repo owns, and `mcpServers`, which is not a settings key at all
# (MCP lives in ~/.claude.json and .mcp.json) and which the old setup script left plaintext
# tokens in.

tmp="$(mktemp)" || exit 3
if jq -s '(.[0] | del(.mcpServers, .enabledPlugins, .extraKnownMarketplaces)) * .[1] * .[2]' \
  "$settings" "$base" "$overlay" > "$tmp" && [ -s "$tmp" ]; then
  mv "$tmp" "$settings" && chmod 600 "$settings"
else
  rm -f "$tmp"
  warn "merging the generated settings into $settings failed; file left untouched."
  exit 3
fi
