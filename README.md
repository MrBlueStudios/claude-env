# claude-env

One Claude Code environment for the crew's NixOS laptops: every MCP server, skill, agent, hook
and guardrail available in every project folder, managed by home-manager. You bring nixpkgs and
home-manager (25.05 or 26.05 both evaluate); this flake only exports modules.

## Use it

```nix
# flake.nix
inputs.claude-env.url = "github:MrBlueStudios/claude-env";
# optional: if you already pin claude-web-stack, share the pin
inputs.claude-env.inputs.claude-web-stack.follows = "claude-web-stack";
```

```nix
# home-manager
{ inputs, ... }: {
  imports = [ inputs.claude-env.homeManagerModules.default ];
  claude-env.user.name = "Kish";     # how Claude addresses you in ~/.claude/CLAUDE.md
  claude-env.tier = "base";          # "blitsol" adds the company connectors (needs the agenix secrets)
  claude-env.modes.enable = false;   # Kitty-only /dashboard, /council, ... layouts; opt in if you run Kitty
  claude-env.user.notes = ''
    - Home directory: /home/kish
    - Lenovo Legion, KDE Plasma
  '';
}
```

```nix
# NixOS (the managed PreToolUse guard; deny rules for .env, /run/agenix, SSH keys)
{ inputs, ... }: {
  imports = [ inputs.claude-env.nixosModules.default ];
}
```

Then `claude mcp list` after the first switch: the module writes the user-scope `mcpServers`
block of `~/.claude.json` itself, so there is nothing to run by hand. The set depends on
`claude-env.tier` and the `claude-env.mcp.modules.*` flags; anything registered by hand is
removed and saved to `~/.claude/removed-mcp-servers.json`. `just plugins-check` reports the
same kind of drift for plugins and skills.

## What is in here

| Path | What |
|---|---|
| `modules/home/` | home-manager module: hooks, settings, tools, MCP servers, agents, skills, modes, CLAUDE.md |
| `modules/home/options.nix` | the knobs: `claude-env.tier`, `claude-env.modes.enable`, `claude-env.user.*` |
| `modules/system/guard.nix` | NixOS module writing `/etc/claude-code/managed-settings.json` |
| `docs/mcp-audit.md` | which MCP servers made it into base, blitsol or an opt-in module, and why |
| `docs/project-state.yaml` | source of truth for the build board |
| `research/` | the decisions behind the design, one file per question |

## Rules

- English everywhere in this repo: code, comments, notifications. Dutch only in shipped product copy.
- Nothing personal lands here. Names, machines and company credentials stay in your own config or in agenix.
- Prefer a CLI over an MCP server when the CLI already does the job (see `docs/mcp-audit.md`).
