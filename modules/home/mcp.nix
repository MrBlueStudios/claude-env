{
  config,
  pkgs,
  lib,
  ...
}:

# MCP servers. Claude Code reads them from ~/.claude.json (user scope, written by `claude mcp add`)
# and from each repo's committed .mcp.json (project scope) — never from settings.json.
#
#   user scope:    context7 (library docs) and firecrawl (web scrape/crawl/search).
#                  Both are general-purpose and have no CLI equivalent worth using.
#                  Run `just setup-mcp` once.
#   project scope: nix-config/.mcp.json → mcp-nixos; Kōro/.mcp.json → svelte.
#   replaced by CLIs: GitHub → `gh`, Playwright → `playwright-cli`, filesystem/memory → built-ins.
#
# firecrawl needs an API key. It is NOT passed with `claude mcp add --env`, because that
# writes the literal value into ~/.claude.json; the wrapper below reads it from agenix at
# startup instead, so the key never lands in a config file.
let
  context7 = "@upstash/context7-mcp@4.4.1";
  firecrawlVersion = "3.30.3";

  # null → Firecrawl cloud, authenticated with the agenix key.
  # A URL → a self-hosted instance, which then needs no key. If that instance ever
  # runs somewhere other than this laptop, bind it to the tailnet rather than a public
  # port: the self-hosted API ships unauthenticated (see their SELF_HOST.md).
  firecrawlApiUrl = null;

  # Reads /run/agenix/firecrawl-api-key, then execs the npm server. Source is a plain file
  # so it can be run and tested outside Nix.
  firecrawl = pkgs.writeShellApplication {
    name = "firecrawl-mcp-agenix";
    runtimeInputs = [ pkgs.nodejs ];
    # writeShellApplication supplies its own shebang, so drop the source's rather than
    # leave a second one mid-file. The version pin lives here, next to context7's, so Nix
    # stays the single source of truth for what gets fetched.
    text =
      "export FIRECRAWL_MCP_VERSION=${firecrawlVersion}\n"
      + lib.optionalString (firecrawlApiUrl != null) "export FIRECRAWL_API_URL=${firecrawlApiUrl}\n"
      + lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./scripts/firecrawl-mcp.sh);
  };

  # what the old script tried to register (three of those npm packages never existed).
  # firecrawl used to be here; it is a real server and is registered again above, so
  # keep it out of this list or --prune will remove it on every run.
  # docs/mcp-audit.md, 16 Nov 2026: dropped from user scope. playwright and svelte stay.
  legacy = [
    "memory"
    "filesystem"
    "github"
    "mcp-nixos"
    "sequential-thinking"
    "obsidian"
  ];
in
{
  home.packages = [ firecrawl ];

  home.file.".local/bin/setup-claude-mcp.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # Usage: setup-claude-mcp.sh [--prune]
      #   registers the user-scope servers (context7, firecrawl);
      #   --prune also removes the legacy ones.
      set -euo pipefail
      command -v claude >/dev/null || { echo "claude is not on PATH"; exit 1; }

      if claude mcp get context7 >/dev/null 2>&1; then
        echo "context7: already registered"
      else
        claude mcp add --scope user context7 -- npx -y ${context7}
      fi

      # Registered by wrapper name, not store path: the path changes on every rebuild and
      # would rot in ~/.claude.json. home.packages puts the wrapper on PATH.
      if claude mcp get firecrawl >/dev/null 2>&1; then
        echo "firecrawl: already registered"
      else
        claude mcp add --scope user firecrawl -- firecrawl-mcp-agenix
      fi

      ${lib.optionalString (firecrawlApiUrl == null) ''
        if [ ! -r /run/agenix/firecrawl-api-key ]; then
          echo "firecrawl: registered, but there is no API key yet — the server will fail to start."
          echo "           cd /etc/nixos/secrets && agenix -e firecrawl-api-key.age && nh os switch ."
        fi
      ''}

      if [ "''${1:-}" = "--prune" ]; then
        for name in ${lib.concatStringsSep " " legacy}; do
          if claude mcp get "$name" >/dev/null 2>&1; then
            echo "removing legacy user-scope server: $name"
            claude mcp remove --scope user "$name" || true
          fi
        done
      fi

      claude mcp list
    '';
  };
}
