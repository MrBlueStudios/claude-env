{ config, lib, ... }:

# ~/.claude/CLAUDE.md: the part all four of us share, then whatever the person adds.
let
  cfg = config.claude-env;
  shared = ''
    # ${cfg.user.name} — crew conventions (claude-env, tier: ${cfg.tier})

    ## Preferences
    - NixOS with home-manager; this module manages ~/.claude. Edit it in the claude-env repo, not in place.
    - Use jj for version control in colocated repos; prefer jj commands over git
    - Run `just test` before committing. Never commit failing tests
    - Conventional commits (feat/fix/chore/docs prefix)
    - Code, comments, CLI output and notifications are English. Dutch only for end-user copy on
      sites shipped to Dutch customers, and only when asked for.

    ## Stack defaults
    - Frontend: SvelteKit 5 + Svelte 5 runes + shadcn-svelte + Tailwind v4
    - Backend: FastAPI + SQLite WAL + Pydantic v2
    - Infra: Contabo Cloud VPS + Caddy + Cloudflare + Litestream to S3
    - NixOS: flakes, home-manager, 2-space indent

    ## CLI-first
    Prefer these over MCP tools: `gh … --json --jq` (GitHub), `playwright-cli` (browser),
    `sqlite-utils`/`litecli` (SQLite), `rg`/`fd`, `jq`, `nix search`/`nix eval`, `just <recipe>`.
    Ask for compact output (`--json` + `--jq`, `-l`, `--stat`) instead of full dumps.
    Local tools: `claude-artifacts` (files Claude wrote here), `compliance-scan` (web legal red flags).

    ## Guardrails
    A managed PreToolUse guard denies destructive commands and reads of .env, /run/agenix and SSH
    keys. If it blocks something legitimate, say so and ask ${cfg.user.name} — don't work around it.

    # Compact instructions
    When compacting, keep: the current goal, files changed, decision IDs, failing tests and their
    errors, and the next step. Drop: file dumps, exploration output, superseded plans.
  '';
in
{
  home.file.".claude/CLAUDE.md".text =
    shared + lib.optionalString (cfg.user.notes != "") ("\n## This machine\n" + cfg.user.notes + "\n");
}
