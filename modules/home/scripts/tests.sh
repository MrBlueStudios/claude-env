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
