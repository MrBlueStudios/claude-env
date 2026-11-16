{ config, pkgs, lib, ... }:

# Claude Code security policy, as managed settings (/etc/claude-code/managed-settings.json).
#
# Managed settings sit above user, project and local settings: their hooks always run and their
# deny rules cannot be overridden by an allow anywhere else. Hooks from other levels still run too
# (they merge), so the user-level hooks in modules/home/claude/settings.nix keep working.
# Never set allowManagedHooksOnly / allowManagedPermissionRulesOnly here — that would silently
# switch off every user and project hook and permission rule.
let
  guard = pkgs.writeShellApplication {
    name = "claude-guard";
    runtimeInputs = with pkgs; [ jq gnugrep gnused coreutils ];
    text = builtins.readFile ./claude-code/guard.sh;
  };

  policy = {
    hooks.PreToolUse = [
      {
        matcher = "Bash";
        hooks = [ { type = "command"; command = "${guard}/bin/claude-guard"; timeout = 10; } ];
      }
    ];
    # `//` = absolute path, `~/` = home (a single leading `/` would be relative to this file).
    # Read denies also stop Edit/Write on these paths; the guard covers cat/grep/cp via Bash.
    permissions.deny = [
      "Read(//**/.env)"
      "Read(//**/.env.local)"
      "Read(//**/.env.production)"
      "Read(//run/agenix/**)"
      "Read(~/.ssh/id_*)"
    ];
  };
in
{
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON policy;

  # On PATH so `just test-guard` can also exercise the built binary.
  environment.systemPackages = [ guard ];
}
