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

printf 'claude helper script tests: %d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
