{ config, pkgs, lib, ... }:

let
  # 25.05: pkgs.nixfmt is the old Haskell 0.6 formatter (and an alias that warns); the RFC one is
  # nixfmt-rfc-style. 26.05: nixfmt-rfc-style is the alias that warns and pkgs.nixfmt is 1.x.
  # Touching the wrong attribute prints a warning on every eval, so pick by nixpkgs release.
  nixfmt = if lib.versionAtLeast lib.trivial.release "26.05" then pkgs.nixfmt else pkgs.nixfmt-rfc-style;
  # 26.05 removed nodePackages; 25.05 has no top-level prettier.
  prettier = pkgs.prettier or pkgs.nodePackages.prettier;
in

{
  # Hook scripts. They are registered in ~/.claude/settings.json by ./settings.nix.
  # The PreToolUse security guard is system-level policy: modules/system/claude-code-policy.nix.
  # (The old audit-log.sh was dropped: transcripts already hold the full audit trail.)

  # ── PostToolUse: auto-format edited files ────────────────────────────
  home.file.".claude/hooks/post-edit-lint.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -euo pipefail

      JQ="${pkgs.jq}/bin/jq"

      INPUT="$(cat)"
      FILE="$(echo "$INPUT" | $JQ -r '.tool_input.file_path // empty')"

      # No file path — nothing to format
      [ -z "$FILE" ] && exit 0
      [ ! -f "$FILE" ] && exit 0

      case "$FILE" in
        *.ts|*.tsx|*.js|*.jsx|*.svelte)
          # Only format if a prettier config exists in the project
          DIR="$(dirname "$FILE")"
          while [ "$DIR" != "/" ]; do
            if [ -f "$DIR/.prettierrc" ] || [ -f "$DIR/.prettierrc.json" ] || [ -f "$DIR/prettier.config.js" ] || [ -f "$DIR/prettier.config.mjs" ]; then
              ${prettier}/bin/prettier --write "$FILE" 2>/dev/null || true
              break
            fi
            DIR="$(dirname "$DIR")"
          done
          ;;
        *.py)
          ${pkgs.ruff}/bin/ruff format "$FILE" 2>/dev/null || true
          ;;
        *.nix)
          ${nixfmt}/bin/nixfmt "$FILE" 2>/dev/null || true
          ;;
      esac

      exit 0
    '';
  };

  # ── Stop: desktop notification when Claude finishes ──────────────────
  home.file.".claude/hooks/notify-done.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      ${pkgs.libnotify}/bin/notify-send -a "Claude Code" \
        "Claude Code" "Task completed" \
        -i dialog-information 2>/dev/null || true
    '';
  };
}
