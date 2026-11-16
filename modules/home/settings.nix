{
  config,
  pkgs,
  lib,
  ...
}:

# ~/.claude/settings.json: the preferences layer.
#
# The file stays writable (so /config, /permissions and "don't ask again" keep working). On every
# switch, the keys below are deep-merged on top of it — Nix wins on the keys it sets, everything
# else in the file is kept. The security policy (guard hook + deny rules) is NOT here: it lives in
# /etc/claude-code/managed-settings.json (modules/system/claude-code-policy.nix), which no user or
# project setting can override.
let
  home = config.home.homeDirectory;
  hook = script: {
    type = "command";
    command = "${home}/.claude/hooks/${script}";
  };

  base = {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    theme = "custom:cyberpunk_dark";
    statusLine = {
      type = "command";
      command = "${home}/.claude/statusline.sh";
      padding = 0;
    };

    # No `autoCompactThreshold` setting exists; this is the real control. Compact at ~400k tokens
    # instead of near the 1M limit: every turn resends the whole context, so long sessions burn
    # plan limits fast (docs/dev-environment-plan.md §2.4).
    autoCompactWindow = 400000;
    cleanupPeriodDays = 90; # transcripts double as the audit trail (master doc §84)
    spinnerTipsEnabled = false;

    env = {
      DISABLE_AUTOUPDATER = "1"; # Nix owns the claude-code version (`nix flake update`)
      DO_NOT_TRACK = "1"; # honoured by npx tools such as impeccable and playwright-cli
    };

    hooks = {
      PostToolUse = [
        {
          matcher = "Write|Edit|MultiEdit";
          hooks = [ (hook "post-edit-lint.sh") ];
        }
        {
          matcher = "Write|Edit|MultiEdit|NotebookEdit";
          hooks = [ ((hook "record-artifact.sh") // { async = true; }) ];
        }
      ];
      Stop = [ { hooks = [ (hook "notify-done.sh") ]; } ];
    };

    extraKnownMarketplaces.superpowers-marketplace.source = {
      source = "github";
      repo = "obra/superpowers-marketplace";
    };
    enabledPlugins."superpowers@superpowers-marketplace" = true;

    # /brag: turns the current project into a launch video via HeyGen's Hyperframes renderer
    # (Puppeteer + FFmpeg). Verified repo: github.com/latent-spaces/brag. Untested on NixOS yet —
    # Hyperframes may hit the same "npm-downloaded browsers don't run on NixOS" issue playwright-cli
    # works around in ./tools.nix; if /brag's render step fails on a missing/incompatible Chromium,
    # point it at pkgs.chromium the same way.
    extraKnownMarketplaces.brag.source = {
      source = "github";
      repo = "latent-spaces/brag";
    };
    enabledPlugins."brag@brag" = true;
  };

  baseFile = pkgs.writeText "claude-settings-base.json" (builtins.toJSON base);

  # Neon dark theme. Token names: https://code.claude.com/docs/en/terminal-config
  theme = {
    name = "Cyberpunk Dark";
    base = "dark";
    overrides = {
      claude = "#a78bfa";
      claudeShimmer = "#c4b5fd";
      text = "#e5e7eb";
      inverseText = "#0b0b14";
      inactive = "#6b7280";
      inactiveShimmer = "#9ca3af";
      subtle = "#4b5563";
      suggestion = "#38bdf8";
      permission = "#38bdf8";
      permissionShimmer = "#7dd3fc";
      remember = "#a78bfa";
      success = "#50fa7b";
      error = "#ff5555";
      warning = "#f1fa8c";
      warningShimmer = "#fef9c3";
      merged = "#a78bfa";
      promptBorder = "#a78bfa";
      promptBorderShimmer = "#c4b5fd";
      planMode = "#38bdf8";
      autoAccept = "#50fa7b";
      bashBorder = "#ff79c6";
      ide = "#38bdf8";
      fastMode = "#f1fa8c";
      diffAdded = "#14532d";
      diffRemoved = "#5f1d24";
      diffAddedDimmed = "#0f2e1c";
      diffRemovedDimmed = "#3a1418";
      diffAddedWord = "#1f7a3f";
      diffRemovedWord = "#8f2a36";
      userMessageBackground = "#1a1726";
      userMessageBackgroundHover = "#231f35";
      bashMessageBackgroundColor = "#1f1420";
      memoryBackgroundColor = "#13202b";
      selectionBg = "#3b2f63";
      rate_limit_fill = "#a78bfa";
      rate_limit_empty = "#2a2540";
    };
  };
in
{
  home.file.".claude/themes/cyberpunk_dark.json".text = builtins.toJSON theme;

  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    settings="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    if [ ! -s "$settings" ]; then
      run sh -c 'echo "{}" > "$1"' _ "$settings"
    fi
    if ${pkgs.jq}/bin/jq empty "$settings" 2>/dev/null; then
      tmp="$(mktemp)"
      # base wins on its own keys; `mcpServers` is not a settings key (MCP lives in ~/.claude.json
      # and .mcp.json) and the old setup script left plaintext tokens in it, so it is dropped
      if ${pkgs.jq}/bin/jq -s '(.[0] * .[1]) | del(.mcpServers)' "$settings" ${baseFile} > "$tmp" && [ -s "$tmp" ]; then
        run mv "$tmp" "$settings"
        run chmod 600 "$settings"
      else
        rm -f "$tmp"
        warnEcho "merging Nix's Claude Code settings into $settings failed; file left untouched."
      fi
    else
      warnEcho "$settings is not valid JSON; left untouched. Fix it, then switch again."
    fi
  '';
}
