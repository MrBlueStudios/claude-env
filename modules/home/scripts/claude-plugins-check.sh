#!/usr/bin/env bash
# Report where this machine's plugins have drifted from what claude-env declares.
#
#   claude-plugins-check [--remote]
#
# Declared is ~/.claude/settings.json, which modules/home/settings.nix writes on every switch.
# Actual is what Claude Code has on disk: the marketplace clones under
# ~/.claude/plugins/marketplaces/ and the install records in installed_plugins.json. The two
# come apart in ways that are each worth seeing:
#
#   - a marketplace clone sitting on a different commit than the declared pin, which is what a
#     refresh does on a machine too old to honour the pin;
#   - a plugin that is enabled but was never installed, or installed and never enabled — the
#     second is how two plugins sat on this machine for weeks costing nothing and doing nothing;
#   - a marketplace or plugin cache left behind by an uninstall.
#
# --remote also asks GitHub where each marketplace's default branch is now, so a pin that has
# fallen behind upstream is visible before someone decides whether to raise it.
#
# Exit 0 when everything lines up, 1 when something is reported, 2 on a usage or setup problem.
set -uo pipefail

REMOTE=0
case "${1:-}" in
  --remote) REMOTE=1 ;;
  "") ;;
  *)
    echo "usage: claude-plugins-check [--remote]" >&2
    exit 2
    ;;
esac

CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
SETTINGS="$CLAUDE_DIR/settings.json"
PLUGINS="$CLAUDE_DIR/plugins"

if [ ! -s "$SETTINGS" ]; then
  echo "claude-plugins-check: no $SETTINGS — run a switch first" >&2
  exit 2
fi
if ! jq empty "$SETTINGS" 2>/dev/null; then
  echo "claude-plugins-check: $SETTINGS is not valid JSON" >&2
  exit 2
fi

findings=0
note() {
  findings=$((findings + 1))
  printf '  ! %s\n' "$1"
}

# ── marketplaces ─────────────────────────────────────────────────────────────

echo "marketplaces"
while IFS=$'\t' read -r name repo ref; do
  [ -n "$name" ] || continue
  clone="$PLUGINS/marketplaces/$name"
  line="  $name  $repo"
  [ "$ref" = "null" ] || line="$line  pinned ${ref:0:12}"

  if [ ! -d "$clone/.git" ]; then
    echo "$line"
    note "not cloned yet: Claude Code fetches it at the next session start"
    continue
  fi

  head="$(git -C "$clone" rev-parse HEAD 2>/dev/null)"
  echo "$line  on ${head:0:12}"

  if [ "$ref" != "null" ] && [ "$ref" != "$head" ]; then
    note "$name is on ${head:0:12} but declared at ${ref:0:12}"
  fi

  if [ "$REMOTE" = 1 ] && [ -n "$repo" ]; then
    upstream="$(gh api "repos/$repo/commits?per_page=1" --jq '.[0].sha' 2>/dev/null)"
    if [ -n "$upstream" ] && [ "$upstream" != "$head" ]; then
      # The backticks are literal text in a message, not a command substitution — and the
      # disable has to be here rather than left as a warning, because `writeShellApplication`
      # runs shellcheck at build time with no locale set, so printing a diagnostic whose
      # context line contains the em dash below kills the build (see the test-shellcheck note
      # in the justfile).
      # shellcheck disable=SC2016
      printf '    upstream is at %s — raise the pin only after `just vet`\n' "${upstream:0:12}"
    fi
  fi
done < <(jq -r '(.extraKnownMarketplaces // {}) | to_entries[]
  | [.key, (.value.source.repo // .value.source.url // ""), (.value.source.ref // "null")]
  | @tsv' "$SETTINGS")

# A clone with no declaration is either a built-in marketplace or an uninstall that left its
# files behind. Both are worth naming; only the second is drift.
if [ -d "$PLUGINS/marketplaces" ]; then
  while IFS= read -r clone; do
    name="$(basename "$clone")"
    if ! jq -e --arg n "$name" '(.extraKnownMarketplaces // {}) | has($n)' "$SETTINGS" > /dev/null 2>&1; then
      printf '  %s  not declared\n' "$name"
      case "$name" in
        claude-plugins-official | claude-code-plugins | anthropic-* | agent-skills)
          printf '    built in to Claude Code, so it needs no declaration\n'
          ;;
        *) note "$name is registered on this machine but not declared in claude-env" ;;
      esac
    fi
  done < <(find "$PLUGINS/marketplaces" -mindepth 1 -maxdepth 1 -type d | sort)
fi

# ── plugins ──────────────────────────────────────────────────────────────────

echo "plugins"
installed="$PLUGINS/installed_plugins.json"
[ -s "$installed" ] || installed=/dev/null

while IFS=$'\t' read -r id enabled; do
  [ -n "$id" ] || continue
  record="$(jq -r --arg id "$id" '(.plugins[$id] // [])[0] // {} | [(.version // "?"), (.gitCommitSha // "")] | @tsv' \
    "$installed" 2>/dev/null)"
  version="$(printf '%s' "$record" | cut -f1)"
  sha="$(printf '%s' "$record" | cut -f2)"

  if [ -z "$version" ] || [ "$version" = "?" ]; then
    printf '  %s  enabled=%s  not installed\n' "$id" "$enabled"
    [ "$enabled" = "true" ] && note "$id is enabled but not installed, so none of it loads"
    continue
  fi

  if [ -n "$sha" ]; then
    printf '  %s  %s  from %s  enabled=%s\n' "$id" "$version" "${sha:0:12}" "$enabled"
  else
    printf '  %s  %s  enabled=%s\n' "$id" "$version" "$enabled"
    note "$id records no commit, so its files are not pinned by anything (its catalog entry fetches a branch)"
  fi

  # Installed and not enabled is the quiet case: it loads nothing, costs no tokens and fires no
  # hook, so it is invisible until someone reads this. Both plugins the audit removed were here.
  if [ "$enabled" != "true" ]; then
    note "$id is installed but not enabled, so it does nothing — uninstall it or declare it"
  fi
done < <(jq -rs '
  (.[0].enabledPlugins // {}) as $enabled
  | ([ $enabled | keys[] ] + ((.[1].plugins // {}) | keys) | unique)[]
  | [., (($enabled[.] // false) | tostring)] | @tsv' "$SETTINGS" "$installed")

# ── skills ───────────────────────────────────────────────────────────────────
#
# A skill the module declares arrives as a symlink into /nix/store, because skills.nix sets
# home.file.<...>.source. So the test needs no list to compare against: anything in
# ~/.claude/skills that is a real directory, or a link to somewhere else, is on this machine
# only. That is fine for a scratch skill and not fine for one the crew depends on, and the
# difference is invisible until it is counted.

if [ -d "$CLAUDE_DIR/skills" ]; then
  echo "skills"
  declared=0
  loading=()
  inert=()
  elsewhere=()
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    # `synced` is Claude Code's own: the skills it pulls from the claude.ai account, controlled
    # by syncClaudeAiSkills rather than by any repo.
    [ "$name" = "synced" ] && continue

    if [ -L "$dir" ]; then
      case "$(readlink "$dir")" in
        /nix/store/*)
          declared=$((declared + 1))
          continue
          ;;
        *)
          elsewhere+=("$name -> $(readlink "$dir")")
          continue
          ;;
      esac
    fi

    # Only a SKILL.md directly inside the directory registers a skill. A pack with its own
    # skills/ subdirectory sits one level too deep and loads nothing at all.
    if [ -f "$dir/SKILL.md" ]; then
      loading+=("$name")
    else
      inert+=("$name")
    fi
  done < <(find "$CLAUDE_DIR/skills" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) | sort)

  printf '  %d declared by the module\n' "$declared"

  if [ "${#loading[@]}" -gt 0 ]; then
    note "${#loading[@]} skill(s) load on this machine and reach no other laptop: ${loading[*]}"
  fi
  if [ "${#elsewhere[@]}" -gt 0 ]; then
    note "${#elsewhere[@]} skill(s) link outside the store, so they break on any other laptop:"
    for e in "${elsewhere[@]}"; do printf '    %s\n' "$e"; done
  fi
  if [ "${#inert[@]}" -gt 0 ]; then
    note "${#inert[@]} director(ies) here have no SKILL.md of their own, so they register nothing: ${inert[*]}"
  fi
fi

# ── leftovers ────────────────────────────────────────────────────────────────

if [ -d "$PLUGINS/cache" ]; then
  while IFS= read -r dir; do
    name="$(basename "$dir")"
    if [ ! -d "$PLUGINS/marketplaces/$name" ]; then
      size="$(du -sh "$dir" 2>/dev/null | cut -f1)"
      note "$PLUGINS/cache/$name ($size) is left over from a removed marketplace"
    fi
  done < <(find "$PLUGINS/cache" -mindepth 1 -maxdepth 1 -type d | sort)
fi

if [ -d "$PLUGINS/.trash" ] && [ -n "$(find "$PLUGINS/.trash" -mindepth 1 -maxdepth 1 2>/dev/null)" ]; then
  note "$PLUGINS/.trash ($(du -sh "$PLUGINS/.trash" 2>/dev/null | cut -f1)) is Claude Code's own \
trash from uninstalls; nothing reads it"
fi

# ── what the account pushed, which is not drift but is worth seeing ──────────
#
# ~/.claude/plugins/synced holds plugins the claude.ai account offers: first-party marketplaces
# such as knowledge-work-plugins and claude-for-legal, downloaded whether or not anyone asked.
# Each carries a .meta.json whose `installation_preference` is "available" until it is installed.
# Reported as a count, not as a finding, because no repo declares it and nothing here is wrong —
# but it was 38 plugins and 331 skills on the first machine that looked, which is worth knowing
# before anyone wonders where 16 MB and a long `/plugin` list came from. The number that matters
# is the enabled one: a skill costs tokens only once its plugin is enabled, and none of these is.
echo "account-synced"
synced_meta=()
if [ -d "$PLUGINS/synced" ]; then
  while IFS= read -r f; do synced_meta+=("$f"); done \
    < <(find "$PLUGINS/synced" -mindepth 2 -maxdepth 2 -name '*.meta.json' 2>/dev/null | sort)
fi
if [ "${#synced_meta[@]}" -eq 0 ]; then
  echo "  none: nothing from the claude.ai account on this machine"
else
  synced_skills="$(find "$PLUGINS/synced" -name SKILL.md 2>/dev/null | wc -l)"
  synced_size="$(du -sh "$PLUGINS/synced" 2>/dev/null | cut -f1)"
  printf '  %d plugin(s), %s skill(s), %s — offered by the account, not by any repo\n' \
    "${#synced_meta[@]}" "$synced_skills" "${synced_size:-?}"
  # An "installed" preference means it is more than an offer, so it belongs in the report above.
  installed_synced="$(grep -l '"installation_preference": *"installed"' "${synced_meta[@]}" 2>/dev/null |
    sed 's|.*/||; s|\.meta\.json$||' | tr '\n' ' ')"
  if [ -n "$installed_synced" ]; then
    note "account-synced and installed, so declared by nobody: $installed_synced"
  else
    echo "  all offered rather than installed, so none of them loads or costs a token"
  fi
fi

echo
if [ "$findings" -eq 0 ]; then
  echo "no drift: every declared plugin is installed and every marketplace is where it should be"
  exit 0
fi
printf '%d thing(s) to look at, listed above.\n' "$findings"
exit 1
