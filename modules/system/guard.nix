{
  config,
  pkgs,
  lib,
  ...
}:

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
    runtimeInputs = with pkgs; [
      jq
      gnugrep
      gnused
      coreutils
    ];
    text = builtins.readFile ./claude-code/guard.sh;
  };

  policy = {
    hooks.PreToolUse = [
      {
        matcher = "Bash";
        hooks = [
          {
            type = "command";
            command = "${guard}/bin/claude-guard";
            timeout = 10;
          }
        ];
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
    # Writes to the shared Jira and Confluence land in front of the whole crew, so they are
    # asked here rather than at user level: `ask` outranks an `allow`, and a managed rule
    # survives the "don't ask again" click that a user-level rule would not.
    # Reads stay silent on purpose — everyone touches the board daily.
    # Revisit when the Atlassian MCP server gains write tools; this list is not a wildcard.
    permissions.ask = [
      "mcp__atlassian__addOrEditJiraIssueComment"
      "mcp__atlassian__createJiraIssue"
      "mcp__atlassian__editJiraIssue"
      "mcp__atlassian__transitionJiraIssue"
      "mcp__atlassian__createConfluenceContent"
      "mcp__atlassian__updateConfluenceContent"
      "mcp__atlassian__addGraphContext"
      "mcp__atlassian__executeWrite"
      "mcp__atlassian__executeDestructive"
    ];
  };
in
{
  environment.etc."claude-code/managed-settings.json".text = builtins.toJSON policy;

  # On PATH so `just test-guard` can also exercise the built binary.
  environment.systemPackages = [ guard ];
}
