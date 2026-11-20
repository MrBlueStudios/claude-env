#!/usr/bin/env bash
# Tests for the Claude Code helper scripts in this directory.
#
# The firecrawl wrapper decides whether the MCP server starts at all and which
# backend it talks to, and it handles an API key — so its branches are worth
# pinning down without a rebuild.
#
#   bash modules/home/claude/scripts/tests.sh
#
# Shape and output deliberately mirror modules/system/scripts/tests.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pass=0; fail=0

ok()   { pass=$((pass+1)); }
bad()  { fail=$((fail+1)); printf '  FAIL: %s\n    expected: %s\n    actual:   %s\n' "$1" "$2" "$3"; }

assert_contains() { [[ "$3" == *"$2"* ]] && ok || bad "$1" "contains '$2'" "$3"; }
assert_lacks()    { [[ "$3" != *"$2"* ]] && ok || bad "$1" "does not contain '$2'" "$3"; }
assert_rc()       { [[ "$2" == "$3" ]] && ok || bad "$1" "exit $2" "exit $3"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Stand in for npx so the wrapper never reaches the network: print the environment
# the server would have been launched with, then exit 0.
mkdir -p "$TMP/bin"
cat > "$TMP/bin/npx" <<'STUB'
#!/usr/bin/env bash
echo "npx-args: $*"
echo "key: ${FIRECRAWL_API_KEY-<unset>}"
echo "url: ${FIRECRAWL_API_URL-<unset>}"
STUB
chmod +x "$TMP/bin/npx"

firecrawl() { PATH="$TMP/bin:$PATH" bash "$HERE/firecrawl-mcp.sh" 2>&1; }

# ── cloud backend ────────────────────────────────────────────────────────────

key_file="$TMP/key"
printf 'fc-test-key\n' > "$key_file"   # trailing newline, as agenix -e leaves

out="$(FIRECRAWL_KEY_FILE="$key_file" firecrawl)"; rc=$?
assert_rc       "cloud: starts with a key"            0 "$rc"
assert_contains "cloud: key passed to the server"     "key: fc-test-key" "$out"
# A key with its trailing newline intact would put a blank line before "url:".
assert_contains "cloud: newline stripped from key"    "key: fc-test-key
url:" "$out"
assert_contains "cloud: no API url set"               "url: <unset>" "$out"
assert_contains "cloud: version is pinned"            "firecrawl-mcp@" "$out"

out="$(FIRECRAWL_KEY_FILE="$TMP/does-not-exist" firecrawl)"; rc=$?
assert_rc       "cloud: refuses to start without a key" 1 "$rc"
assert_contains "cloud: says where the key should be"   "$TMP/does-not-exist" "$out"
assert_contains "cloud: points at agenix"               "agenix -e firecrawl-api-key.age" "$out"

: > "$TMP/empty"
out="$(FIRECRAWL_KEY_FILE="$TMP/empty" firecrawl)"; rc=$?
assert_rc       "cloud: refuses an empty key file" 1 "$rc"
assert_contains "cloud: says the file is empty"    "is empty" "$out"

# ── self-hosted backend ──────────────────────────────────────────────────────

out="$(FIRECRAWL_API_URL=http://vps:3002 FIRECRAWL_KEY_FILE="$TMP/does-not-exist" firecrawl)"; rc=$?
assert_rc       "self-hosted: starts without any key" 0 "$rc"
assert_contains "self-hosted: url passed through"     "url: http://vps:3002" "$out"
assert_contains "self-hosted: no key set"             "key: <unset>" "$out"

out="$(FIRECRAWL_API_URL=http://vps:3002 FIRECRAWL_KEY_FILE="$key_file" firecrawl)"; rc=$?
assert_rc       "self-hosted: a key is still honoured" 0 "$rc"
assert_contains "self-hosted: key passed through"      "key: fc-test-key" "$out"
assert_contains "self-hosted: url still set"           "url: http://vps:3002" "$out"

# ── the key must never be echoed on the failure path ─────────────────────────

printf 'super-secret\n' > "$TMP/secret"
out="$(FIRECRAWL_KEY_FILE="$TMP/secret" firecrawl)"
assert_lacks "key is not printed by the wrapper itself" "super-secret
firecrawl-mcp" "$out"

# ── claude-vet ───────────────────────────────────────────────────────────────
#
# A gate that passes everything is not a gate, so these fix both directions: a tree with a
# self-firing hook must fail, and the same tree must pass once the exemption is written down.
# Fixtures are built here rather than pointed at ~/.claude, which drifts.

vet() { bash "$HERE/claude-vet.sh" --exemptions "$1" "$2" 2>&1; }

mk_plugin() { # dir name hook-event
  mkdir -p "$1/.claude-plugin" "$1/hooks" "$1/skills/demo"
  printf 'MIT License\n\nCopyright (c) 2026 A Person\n' > "$1/LICENSE"
  cat > "$1/.claude-plugin/plugin.json" <<EOF
{ "name": "$2", "version": "1.0.0", "author": { "name": "A Person" }, "hooks": ["./hooks/h.json"] }
EOF
  printf -- '---\nname: demo\ndescription: a demo skill\n---\nbody\n' > "$1/skills/demo/SKILL.md"
  if [ -n "${3:-}" ]; then
    printf '{ "hooks": { "%s": [ { "hooks": [ { "type": "command", "command": "./x.js" } ] } ] } }\n' \
      "$3" > "$1/hooks/h.json"
  else
    printf '{ "hooks": {} }\n' > "$1/hooks/h.json"
  fi
}

EMPTY_EX="$TMP/no-exemptions.md"; : > "$EMPTY_EX"

mk_plugin "$TMP/hooky" hooky UserPromptSubmit
out="$(vet "$EMPTY_EX" "$TMP/hooky")"; rc=$?
assert_rc       "vet: a UserPromptSubmit hook blocks"      1 "$rc"
assert_contains "vet: names the event it blocked on"       "UserPromptSubmit hook" "$out"
assert_contains "vet: points at the exemption file"        "$EMPTY_EX" "$out"

cat > "$TMP/with-exemption.md" <<'EOF'
- `hooky` UserPromptSubmit — needed because the plugin delivers its whole payload this way.
EOF
out="$(vet "$TMP/with-exemption.md" "$TMP/hooky")"; rc=$?
assert_rc       "vet: a written exemption clears it"       0 "$rc"
assert_contains "vet: says the exemption applied"          "is exempted in" "$out"

# A bare name with no reason is how an exemption list rots; the reason is the point.
printf -- '- `hooky` UserPromptSubmit\n' > "$TMP/bare.md"
out="$(vet "$TMP/bare.md" "$TMP/hooky")"; rc=$?
assert_rc       "vet: an exemption with no reason does not count" 1 "$rc"

mk_plugin "$TMP/clean" clean ""
out="$(vet "$EMPTY_EX" "$TMP/clean")"; rc=$?
assert_rc       "vet: a hookless plugin passes"            0 "$rc"
assert_contains "vet: reports the named author"            "A Person" "$out"
assert_contains "vet: projects the always-on cost"         "projected always-on" "$out"

# PostToolUse still runs code, but only on a tool call — reported, never blocking.
mk_plugin "$TMP/posthook" posthook PostToolUse
out="$(vet "$EMPTY_EX" "$TMP/posthook")"; rc=$?
assert_rc       "vet: PostToolUse is reported, not blocked" 0 "$rc"
assert_contains "vet: still lists the hook"                 "PostToolUse" "$out"

mk_plugin "$TMP/nolicence" nolicence ""
rm "$TMP/nolicence/LICENSE"
out="$(vet "$EMPTY_EX" "$TMP/nolicence")"; rc=$?
assert_rc       "vet: a tree with no licence blocks"       1 "$rc"
assert_contains "vet: explains why the licence matters"    "public" "$out"

# The common monorepo case: the plugin is a subdirectory, the licence is at the repo root.
mkdir -p "$TMP/mono"
printf 'MIT License\n' > "$TMP/mono/LICENSE"
mk_plugin "$TMP/mono/plugins/sub" sub ""
rm "$TMP/mono/plugins/sub/LICENSE"
out="$(vet "$EMPTY_EX" "$TMP/mono/plugins/sub")"; rc=$?
assert_rc       "vet: finds a licence at the repo root"    0 "$rc"
assert_contains "vet: says where it found it"              "not in the plugin itself" "$out"

# REUSE-style repos keep a LICENSES/ *directory* of SPDX texts. Reading a directory used to
# be an error; worse, a repo whose parts are under different terms would be reported as having
# exactly one licence, which is the detail that decides whether it can be vendored at all.
mk_plugin "$TMP/dual" dual ""
mkdir -p "$TMP/dual/LICENSES"
printf 'MIT License\n' > "$TMP/dual/LICENSES/MIT.txt"
printf 'GNU GENERAL PUBLIC LICENSE\n' > "$TMP/dual/LICENSES/GPL-3.0-or-later.txt"
out="$(vet "$EMPTY_EX" "$TMP/dual")"; rc=$?
assert_rc       "vet: a multi-licence tree still passes"      0 "$rc"
assert_contains "vet: names both licences"                    "GPL-3.0-or-later" "$out"
assert_contains "vet: warns that the terms differ by part"    "different licences" "$out"
assert_lacks    "vet: never tries to read the directory"      "Is a directory" "$out"

out="$(vet "$EMPTY_EX" "$TMP/does-not-exist")"; rc=$?
assert_rc       "vet: a missing path is a usage error, not a pass" 2 "$rc"

# ── claude-settings: the plugin channel ──────────────────────────────────────
#
# Two things here are easy to get wrong in ways nobody notices for weeks. A commit pin that an
# older Claude Code can't load takes the plugin down with it, so the version gate decides
# whether the machine gets pins at all. And the repo owning enabledPlugins means a switch
# *deletes* entries — which has to be exactly the undeclared ones, and has to be said out loud.

SETTINGS_SH="$HERE/claude-settings.sh"

cat > "$TMP/base.json" <<'EOF'
{
  "theme": "custom:cyberpunk_dark",
  "enabledPlugins": { "superpowers@superpowers-marketplace": true, "svelte@svelte": true }
}
EOF
cat > "$TMP/pinned.json" <<'EOF'
{ "extraKnownMarketplaces": { "svelte": { "source": {
  "source": "github", "repo": "sveltejs/ai-tools",
  "ref": "61061d4704a5e61781e6415dd802e9d9aff89dbe" } } } }
EOF
cat > "$TMP/floating.json" <<'EOF'
{ "extraKnownMarketplaces": { "svelte": { "source": {
  "source": "github", "repo": "sveltejs/ai-tools" } } } }
EOF

mkdir -p "$TMP/cbin"
fake_claude() { # version-string
  printf '#!/usr/bin/env bash\necho "%s (Claude Code)"\n' "$1" > "$TMP/cbin/claude"
  chmod +x "$TMP/cbin/claude"
}

merge() { # settings-file
  PATH="$TMP/cbin:$PATH" bash "$SETTINGS_SH" "$1" \
    "$TMP/base.json" "$TMP/pinned.json" "$TMP/floating.json" 2>&1
}

# The version actually on this machine today: older than the first that can load a pin.
fake_claude 2.1.278
s="$TMP/settings-old.json"; printf '{}\n' > "$s"
out="$(merge "$s")"; rc=$?
assert_rc       "settings: an old Claude Code is not a failure"   0 "$rc"
assert_contains "settings: says which version it found"           "2.1.278" "$out"
assert_contains "settings: names the version pins need"           "2.1.324" "$out"
assert_lacks    "settings: writes no ref it cannot load"          '"ref"' "$(cat "$s")"
assert_contains "settings: still registers the marketplace"       "sveltejs/ai-tools" "$(cat "$s")"

# Exactly the version that gained SHA pinning, and one past it.
for v in 2.1.324 2.1.400; do
  fake_claude "$v"
  s="$TMP/settings-$v.json"; printf '{}\n' > "$s"
  out="$(merge "$s")"
  assert_contains "settings: $v writes the pin" \
    '"ref":"61061d4704a5e61781e6415dd802e9d9aff89dbe"' "$(jq -c . "$s")"
  assert_lacks    "settings: $v says nothing about the gate" "2.1.324, the first" "$out"
done

# A machine where `claude` can't be found: unpinned and loud, never pinned on a guess.
rm -f "$TMP/cbin/claude"
s="$TMP/settings-noclaude.json"; printf '{}\n' > "$s"
out="$(CLAUDE_BIN="$TMP/cbin/claude" merge "$s")"
assert_contains "settings: says it could not read a version" "no Claude Code version" "$out"
assert_lacks    "settings: unpinned when the version is unknown" '"ref"' "$(cat "$s")"

# The authority rule, which is the whole point of the channel.
fake_claude 2.1.400
s="$TMP/settings-drift.json"
cat > "$s" <<'EOF'
{
  "editorMode": "vim",
  "permissions": { "allow": ["Bash(npm run test *)"] },
  "mcpServers": { "leftover": { "command": "x", "env": { "TOKEN": "plaintext" } } },
  "enabledPlugins": { "svelte@svelte": true, "brag@latent-spaces": true },
  "extraKnownMarketplaces": { "latent-spaces": { "source": { "source": "github", "repo": "latent-spaces/brag" } } }
}
EOF
out="$(merge "$s")"; rc=$?
after="$(jq -c . "$s")"
assert_rc       "settings: a drifting file still merges"            0 "$rc"
assert_contains "settings: names the plugin it removed"             "brag@latent-spaces" "$out"
assert_contains "settings: names the marketplace it removed"        "marketplace  latent-spaces" "$out"
assert_contains "settings: says where to declare it instead"        "claude-env.plugins.personal" "$out"
assert_lacks    "settings: the undeclared plugin is gone"           "brag@latent-spaces" "$after"
assert_lacks    "settings: the undeclared marketplace is gone"      "latent-spaces" "$after"
assert_contains "settings: a declared plugin survives"              "svelte@svelte" "$after"
assert_contains "settings: a declared plugin it did not have is added" "superpowers@superpowers-marketplace" "$after"
assert_contains "settings: an unrelated key the user set survives"  '"editorMode":"vim"' "$after"
assert_contains "settings: a permission the user granted survives"  "npm run test" "$after"
assert_lacks    "settings: mcpServers is dropped with its token"    "plaintext" "$after"

# A file worth more than the merge: never half-write it.
s="$TMP/settings-broken.json"; printf '{ "theme": \n' > "$s"
before="$(cat "$s")"
out="$(merge "$s")"; rc=$?
assert_rc       "settings: invalid JSON reports rather than merges" 3 "$rc"
assert_contains "settings: says the file is not valid JSON"         "not valid JSON" "$out"
[[ "$(cat "$s")" == "$before" ]] && ok || bad "settings: broken file left untouched" "$before" "$(cat "$s")"

s="$TMP/fresh/settings.json"
out="$(merge "$s")"; rc=$?
assert_rc       "settings: a missing file is created"      0 "$rc"
assert_contains "settings: the new file has the base keys" "cyberpunk_dark" "$(cat "$s")"

out="$(PATH="$TMP/cbin:$PATH" bash "$SETTINGS_SH" "$TMP/base.json" 2>&1)"; rc=$?
assert_rc       "settings: wrong argument count is a usage error" 2 "$rc"
assert_contains "settings: prints the usage line"                 "usage: claude-settings.sh" "$out"

# ── claude-plugins-check ─────────────────────────────────────────────────────
#
# It reports drift, so the test that matters is that it reports none when there is none, and
# exits non-zero when there is. Fixtures stand in for ~/.claude so the result doesn't depend on
# whichever plugins this machine happens to have installed today.

CHECK_SH="$HERE/claude-plugins-check.sh"

mk_claude_dir() { # dir declared-ref installed-sha
  mkdir -p "$1/plugins/marketplaces/svelte" "$1/plugins/cache"
  git -C "$1/plugins/marketplaces/svelte" init -q 2>/dev/null
  git -C "$1/plugins/marketplaces/svelte" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m 'fixture' 2>/dev/null
  head="$(git -C "$1/plugins/marketplaces/svelte" rev-parse HEAD)"
  cat > "$1/settings.json" <<EOF
{ "enabledPlugins": { "svelte@svelte": true },
  "extraKnownMarketplaces": { "svelte": { "source": {
    "source": "github", "repo": "sveltejs/ai-tools", "ref": "${2:-$head}" } } } }
EOF
  cat > "$1/plugins/installed_plugins.json" <<EOF
{ "version": 2, "plugins": { "svelte@svelte": [ { "scope": "user", "version": "1.0.11",
  "gitCommitSha": "${3:-$head}" } ] } }
EOF
}

check() { CLAUDE_CONFIG_DIR="$1" bash "$CHECK_SH" 2>&1; }

mk_claude_dir "$TMP/cfg-clean"
out="$(check "$TMP/cfg-clean")"; rc=$?
assert_rc       "plugins-check: no drift exits 0"        0 "$rc"
assert_contains "plugins-check: says so plainly"         "no drift" "$out"

mk_claude_dir "$TMP/cfg-drift" "0123456789abcdef0123456789abcdef01234567"
out="$(check "$TMP/cfg-drift")"; rc=$?
assert_rc       "plugins-check: a marketplace off its pin exits 1" 1 "$rc"
assert_contains "plugins-check: names the declared commit"         "0123456789ab" "$out"

mkdir -p "$TMP/cfg-drift/plugins/cache/ponytail"
out="$(check "$TMP/cfg-drift")"
assert_contains "plugins-check: reports a leftover cache" "left over from a removed marketplace" "$out"

mk_claude_dir "$TMP/cfg-unused"
printf '{ "enabledPlugins": {}, "extraKnownMarketplaces": {} }\n' > "$TMP/cfg-unused/settings.json"
out="$(check "$TMP/cfg-unused")"; rc=$?
assert_rc       "plugins-check: installed but not enabled exits 1" 1 "$rc"
assert_contains "plugins-check: names the quiet case"              "installed but not enabled" "$out"

out="$(CLAUDE_CONFIG_DIR="$TMP/does-not-exist" bash "$CHECK_SH" 2>&1)"; rc=$?
assert_rc       "plugins-check: no settings file is a setup error" 2 "$rc"

# The skills half. A declared skill is a link into the store, so the four cases are: declared,
# machine-only and loading, machine-only and loading nothing, and linked somewhere off-store.
mk_claude_dir "$TMP/cfg-skills"
mkdir -p "$TMP/cfg-skills/skills" "$TMP/elsewhere/mine"
store_path="$(dirname "$(dirname "$(readlink -f "$(command -v jq)")")")"
ln -sfn "$store_path" "$TMP/cfg-skills/skills/declared"
mkdir -p "$TMP/cfg-skills/skills/mine" && printf -- '---\nname: mine\n---\n' > "$TMP/cfg-skills/skills/mine/SKILL.md"
mkdir -p "$TMP/cfg-skills/skills/a-pack/skills/inner"
printf -- '---\nname: inner\n---\n' > "$TMP/cfg-skills/skills/a-pack/skills/inner/SKILL.md"
printf -- '---\nname: linked\n---\n' > "$TMP/elsewhere/mine/SKILL.md"
ln -sfn "$TMP/elsewhere/mine" "$TMP/cfg-skills/skills/linked"
mkdir -p "$TMP/cfg-skills/skills/synced/whatever"

out="$(check "$TMP/cfg-skills")"
assert_contains "plugins-check: counts the declared skills"      "1 declared by the module" "$out"
assert_contains "plugins-check: names the machine-only skill"    "reach no other laptop: mine" "$out"
assert_contains "plugins-check: flags the off-store link"        "link outside the store" "$out"
assert_contains "plugins-check: names the pack that loads nothing" "register nothing: a-pack" "$out"
assert_lacks    "plugins-check: leaves Claude Code's own synced dir alone" "synced" "$out"

# ── vendored trees carry their attribution ───────────────────────────────────
#
# skills.nix declares each vendored skill by whole-directory source precisely so the LICENSE
# and NOTICE.md travel with it. That argument only holds if they are actually there, and the
# failure mode is silent: a skill copied in without them still works, it is just no longer
# legitimately redistributable from a public repo.

SKILL_SRC="$(cd "$HERE/../skills" && pwd)"
for d in "$SKILL_SRC"/*/; do
  name="$(basename "$d")"
  if [ -f "$d/LICENSE" ] || [ -f "$d/NOTICE.md" ]; then
    [ -f "$d/LICENSE" ]   && ok || bad "$name: has NOTICE.md but no LICENSE" "LICENSE" "missing"
    [ -f "$d/NOTICE.md" ] && ok || bad "$name: has LICENSE but no NOTICE.md" "NOTICE.md" "missing"
    if [ -f "$d/NOTICE.md" ]; then
      n="$(cat "$d/NOTICE.md")"
      assert_contains "$name: NOTICE names the upstream" "Vendored from http" "$n"
      [[ "$n" == *commit* ]] && ok || bad "$name: NOTICE pins no commit" "a commit" "$n"
    fi
  else
    # Not licence-bearing: it must still say where it came from, somewhere in its own text.
    grep -rqiE 'vendored from|written for this repo|source: ' "$d" \
      && ok || bad "$name: vendored with no attribution anywhere" "an origin line" "none found"
  fi
done

printf 'claude helper script tests: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
