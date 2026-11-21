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

  # ── the plugin channel ───────────────────────────────────────────────────────
  #
  # Every plugin the four of us load is declared here, with the marketplace commit it came from,
  # so a fresh laptop gets the same set rather than whatever the marketplaces serve that day.
  # `rev` is the commit `just vet` cleared; `just plugins-check` reports where the machine has
  # drifted from it. Raising a pin means re-running the gate, which is the point of having one.
  #
  # The revs reach Claude Code as `ref`, which only accepts a SHA from 2.1.324 on, so
  # ./scripts/claude-settings.sh picks the pinned or the floating form by the version it finds.
  marketplaces = {
    # Pins the catalog, not the plugin: superpowers-marketplace lists superpowers as a `url`
    # source on obra/superpowers.git with no ref of its own, so the plugin still tracks main
    # (installed 7.0.0, upstream 7.0.2 as of 2026-11-20). Closing that needs the catalog
    # replaced by an inline `settings` source carrying the plugin's own `sha`, which changes
    # how the plugin resolves and wants one supervised reinstall — see docs/project-state.yaml.
    superpowers-marketplace = {
      repo = "obra/superpowers-marketplace";
      rev = "2cf27fa76667afa0ba724ad8141a6938a3834e32";
    };

    # /brag: turns the current project into a launch video via HeyGen's Hyperframes renderer
    # (Puppeteer + FFmpeg). Untested on NixOS yet — Hyperframes may hit the same "npm-downloaded
    # browsers don't run on NixOS" issue playwright-cli works around in ./tools.nix; if /brag's
    # render step fails on a missing/incompatible Chromium, point it at pkgs.chromium the same way.
    # Its catalog entry is a relative path, so this rev pins the plugin's own files too.
    brag = {
      repo = "latent-spaces/brag";
      rev = "669ab9286aa28b6c3ee30e75f181ee74319d012a";
    };

    # The Svelte team's own plugin: MCP docs server plus the svelte-file-editor agent. Also a
    # relative-path entry, so the rev pins the plugin.
    svelte = {
      repo = "sveltejs/ai-tools";
      rev = "61061d4704a5e61781e6415dd802e9d9aff89dbe";
    };
  }
  // config.claude-env.plugins.personalMarketplaces;

  # One source per marketplace, with the ref the caller asks for.
  sources =
    withRev:
    lib.mapAttrs (_: m: {
      source = {
        source = "github";
        repo = m.repo;
      }
      // lib.optionalAttrs (withRev && m.rev != null) { ref = m.rev; };
    }) marketplaces;

  marketplacesPinned = pkgs.writeText "claude-marketplaces-pinned.json" (
    builtins.toJSON { extraKnownMarketplaces = sources true; }
  );
  marketplacesFloating = pkgs.writeText "claude-marketplaces-floating.json" (
    builtins.toJSON { extraKnownMarketplaces = sources false; }
  );

  settingsMerge = pkgs.writeShellApplication {
    name = "claude-settings";
    runtimeInputs = with pkgs; [
      jq
      coreutils
      gnugrep
    ];
    # no errexit: this is a merge whose failure paths all end in a warning and an exit code the
    # activation script reads, not in a half-written settings file
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./scripts/claude-settings.sh;
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

    # The marketplaces these come from are above; the sources themselves are written to a
    # separate file so the pinned and floating forms can be chosen at activation time.
    enabledPlugins = {
      "superpowers@superpowers-marketplace" = true;
      "brag@brag" = true;
      "svelte@svelte" = true;

      # claude-plugins-official is built in, so it needs no marketplace entry — and Claude Code
      # refuses a commit pin on a reserved marketplace name, so this one necessarily floats.
      # It is Anthropic's own marketplace, which is the only reason that is acceptable here.
      "frontend-design@claude-plugins-official" = true;
    }
    // config.claude-env.plugins.personal;
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

  # The merge, the two keys the repo owns and the version gate live in ./scripts/claude-settings.sh
  # so they can be tested without a rebuild (modules/home/scripts/tests.sh). The script reads a
  # Claude Code version to decide whether the marketplaces can be pinned; claude-code is the
  # consumer's package, not this flake's, so look for it rather than assuming activation's PATH
  # has it. Not finding one is handled — it falls back to unpinned and says so.
  #
  # The candidate list is the whole fix for a real failure, so each entry is here for a reason.
  # On 2026-11-21 this printed "no Claude Code version to read" on a machine with Claude Code
  # 2.1.278 installed, because home-manager-as-a-NixOS-module puts user packages in
  # /etc/profiles/per-user/<user>/bin, which is neither on the activation unit's PATH nor in the
  # two paths this used to try. That is worse than it looks: the fallback is "unpinned", so the
  # pins would never have started applying after the version floor was crossed, and nothing
  # would have said why. The username comes from Nix rather than $USER, which activation does
  # not reliably set.
  home.activation.claudeSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    claudeBin="$(command -v claude || true)"
    for candidate in \
      "$HOME/.nix-profile/bin/claude" \
      "/etc/profiles/per-user/${config.home.username}/bin/claude" \
      /run/current-system/sw/bin/claude \
      "$HOME/.local/bin/claude"; do
      if [ -z "$claudeBin" ] && [ -x "$candidate" ]; then claudeBin="$candidate"; fi
    done
    run env CLAUDE_BIN="$claudeBin" ${settingsMerge}/bin/claude-settings \
      "$HOME/.claude/settings.json" ${baseFile} ${marketplacesPinned} ${marketplacesFloating} \
      || warnEcho "Nix's Claude Code settings were not merged into ~/.claude/settings.json; see above."
  '';
}
