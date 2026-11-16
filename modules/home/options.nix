{ lib, ... }:

# The knobs a consumer sets. Everything else in this module is the same for all four of us.
{
  options.claude-env = {
    tier = lib.mkOption {
      type = lib.types.enum [ "base" "blitsol" ];
      default = "base";
      description = ''
        base: everything that needs no shared company credential.
        blitsol: adds the servers that read Blitsol secrets from agenix (moneybird, firecrawl key,
        cloudflare). Only the four of us; later friends stay on base.
      '';
    };

    modes.enable = lib.mkEnableOption "the claude-mode Kitty layouts (/dashboard, /council, ...); Kitty only";

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
