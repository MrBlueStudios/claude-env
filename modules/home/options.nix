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
