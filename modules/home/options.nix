{ lib, ... }:

# The knobs a consumer sets. Everything else in this module is the same for all four of us.
{
  options.claude-env = {
    tier = lib.mkOption {
      type = lib.types.enum [
        "base"
        "blitsol"
      ];
      default = "base";
      description = ''
        base: everything that needs no shared company credential.
        blitsol: adds the servers that read Blitsol secrets from agenix (moneybird, firecrawl key,
        cloudflare). Only the four of us; later friends stay on base.
      '';
    };

    modes.enable = lib.mkEnableOption "the claude-mode Kitty layouts (/dashboard, /council, ...); Kitty only";

    # ~/.claude/settings.json's enabledPlugins and extraKnownMarketplaces are owned by
    # modules/home/settings.nix: anything not declared there is removed at the next switch, so
    # that what a laptop loads is visible in this repo. These two options are the escape hatch,
    # for a plugin that is genuinely one person's rather than the crew's. It is still declared —
    # in your own home config instead of this repo — which is the whole point.
    plugins = {
      personal = lib.mkOption {
        type = lib.types.attrsOf lib.types.bool;
        default = { };
        example = {
          "my-plugin@my-marketplace" = true;
        };
        description = ''
          Plugins to enable on this machine only, keyed by the install id (plugin@marketplace).
          A plugin from a marketplace that is not built in also needs an entry in
          plugins.personalMarketplaces, or its marketplace is removed and it stops loading.
        '';
      };

      personalMarketplaces = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              repo = lib.mkOption {
                type = lib.types.str;
                example = "owner/repo";
                description = "GitHub repository holding .claude-plugin/marketplace.json.";
              };
              rev = lib.mkOption {
                type = lib.types.nullOr lib.types.str;
                default = null;
                description = ''
                  Full 40-character commit SHA to pin the marketplace to, or null to track its
                  default branch. A pin is only honoured by Claude Code 2.1.324 and newer; older
                  versions refuse to load a marketplace pinned this way, so activation drops
                  every pin and warns until the machine crosses that version.
                '';
              };
            };
          }
        );
        default = { };
        description = "Marketplaces for this machine's own plugins, keyed by marketplace name.";
      };
    };

    # ~/.claude.json's user-scope mcpServers block is owned by modules/home/mcp.nix, for the same
    # reason the plugin channel is owned: `claude mcp add` is how 39 registrations ended up
    # scattered across five scopes. Each module below is off by default because every enabled
    # server's tool list is a standing cost in every session, measured in
    # research/context-budget.md. Verdicts and reasons: docs/mcp-audit.md.
    mcp = {
      modules = {
        nix = lib.mkEnableOption "mcp-nixos — NixOS option and package lookup";
        legal = lib.mkEnableOption "eu-law — the EU regulations server (keyless, Apache-2.0)";
        trading = lib.mkEnableOption "coingecko — keyless market data, for the trading-bot work";
        seo = lib.mkEnableOption "gsc — Google Search Console; needs a Cloud OAuth client of your own";
        sentry = lib.mkEnableOption "sentry — 1,089 tokens, the most expensive server measured";
        firecrawl = lib.mkEnableOption "firecrawl — web scrape and crawl, with your own key from agenix";
      };

      layaPath = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/you/Projects/Laya_And_CLM-MCPs";
        description = ''
          Checkout of Laya_And_CLM-MCPs. Set it to register the Laya decision server at user
          scope, so it is reachable from every project rather than only that repo. A string
          rather than a path so the checkout is not copied into the store. CLM is not registered
          either way: it is parked until a 24 GB card exists, and a server whose backend is
          absent is a tool that always fails.
        '';
      };

      # What the tier and the flags above actually resolved to. Set by modules/home/mcp.nix and
      # read by the test suite, which is the only way to check the tier split without a switch:
      # `tier = "base"` must produce no company server and `"blitsol"` must produce it.
      declared = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        internal = true;
        readOnly = true;
        # No default: mcp.nix always sets it, and in this home-manager a default counts as a
        # second definition of a read-only option, which is an error rather than a fallback.
        description = "The resolved user-scope MCP server set. Read-only; set by mcp.nix.";
      };

      personal = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
        default = { };
        example = {
          obsidian = {
            type = "stdio";
            command = "npx";
            args = [
              "-y"
              "@bitbonsai/mcpvault"
              "/home/you/Obsidian/Vault"
            ];
          };
        };
        description = ''
          MCP servers for this machine only, in Claude Code's own ~/.claude.json shape. Anything
          not declared here or in modules/home/mcp.nix is removed from user scope at the next
          switch (and saved to ~/.claude/removed-mcp-servers.json first), so this is where a
          server that points into one person's home belongs. Never put a secret in here: it
          would land in the world-readable Nix store. Read a key from agenix in a wrapper
          instead, the way the firecrawl module does.
        '';
      };
    };

    webDesignPlaybook = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Checkout of claude-web-stack; the flake sets this from its own input. null skips the skill.";
    };

    user = {
      name = lib.mkOption {
        type = lib.types.str;
        description = "How Claude should address you in CLAUDE.md (e.g. \"Léon\").";
      };
      notes = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = "Personal lines appended to the shared ~/.claude/CLAUDE.md (machine, editor, quirks).";
      };
    };
  };
}
