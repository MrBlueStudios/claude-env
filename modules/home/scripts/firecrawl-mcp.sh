#!/usr/bin/env bash
# Launch the Firecrawl MCP server against either backend.
#
#   cloud (default)   needs an API key; read from agenix at startup
#   self-hosted       set FIRECRAWL_API_URL to the instance; the key is then
#                     optional, because the instance holds its own config
#
# Why the key is read here rather than passed in: `claude mcp add --env K=v`
# writes the literal value into ~/.claude.json, and .mcp.json has the same
# problem. That is how a plaintext token ended up in settings.json before
# (see settings.nix). Reading it in the process that needs it keeps it out of
# every config file on disk.
set -euo pipefail

key_file="${FIRECRAWL_KEY_FILE:-/run/agenix/firecrawl-api-key}"
api_url="${FIRECRAWL_API_URL:-}"

# $(< file) strips trailing newlines, which agenix -e leaves behind.
key=""
if [[ -r "$key_file" ]]; then
  key="$(<"$key_file")"
fi

if [[ -n "$api_url" ]]; then
  # Self-hosted. Pass a key through if there is one — an instance running with
  # USE_DB_AUTHENTICATION=true still wants it — but do not require one.
  export FIRECRAWL_API_URL="$api_url"
  if [[ -n "$key" ]]; then
    export FIRECRAWL_API_KEY="$key"
  fi
elif [[ -n "$key" ]]; then
  export FIRECRAWL_API_KEY="$key"
else
  if [[ -r "$key_file" ]]; then
    reason="$key_file is empty"
  else
    reason="no readable API key at $key_file"
  fi
  cat >&2 <<EOF
firecrawl-mcp: $reason

Firecrawl cloud has a free tier (1,000 credits/month, no card). Get a key at
https://firecrawl.dev, then:

  cd /etc/nixos/secrets && agenix -e firecrawl-api-key.age
  nh os switch .

Or point this at a self-hosted instance instead, by setting firecrawlApiUrl in
modules/home/claude/mcp.nix — no key needed.

Until one of those, this server will not start and /mcp will show it as failed.
EOF
  exit 1
fi

exec npx -y "firecrawl-mcp@${FIRECRAWL_MCP_VERSION:-3.30.3}"
