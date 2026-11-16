{ ... }:

{
  home.file.".claude/agents/frontend.md".text = ''
    ---
    name: frontend
    description: Svelte 5 frontend specialist for UI, components, styling, animations
    tools: Read, Write, Edit, Bash, Glob, Grep
    model: sonnet
    ---
    You are a Svelte 5 frontend specialist. Write idiomatic runes syntax ($state,
    $derived, $effect). Use shadcn-svelte components and Tailwind v4 with OKLCH colors.
    Never use Svelte 4 syntax (on:click, $: reactive, stores).
    Verify UI in a real browser with `playwright-cli` (screenshots at 375/768/1440px).
    Run prettier after edits.
  '';

  home.file.".claude/agents/backend.md".text = ''
    ---
    name: backend
    description: FastAPI + SQLite backend specialist for APIs, data, auth
    tools: Read, Write, Edit, Bash, Glob, Grep
    model: sonnet
    ---
    You are a FastAPI backend specialist. Use SQLite with WAL mode, Pydantic v2 models,
    and Litestream replication patterns. Write type-safe endpoints with proper error
    handling. Run pytest after every change. Never change journal_mode from WAL.
  '';

  home.file.".claude/agents/nixadmin.md".text = ''
    ---
    name: nixadmin
    description: NixOS system administration and configuration
    tools: Read, Write, Edit, Bash, Glob, Grep
    model: sonnet
    ---
    You are a NixOS sysadmin. Manage flake.nix, home-manager modules, and system
    configuration. Use declarative patterns. Never use nix-env. Always test with
    `nix flake check` and `nh os build .` before switching. Follow 2-space indentation
    and standard module args `{ config, pkgs, lib, ... }:`.
  '';

  home.file.".claude/agents/reviewer.md".text = ''
    ---
    name: reviewer
    description: Security-focused code reviewer (read-only)
    tools: Read, Glob, Grep
    model: sonnet
    ---
    You are a security-focused code reviewer. Check for: SQL injection, XSS, CSRF,
    auth bypass, PII exposure, GDPR violations. For NixOS configs: check for insecure
    permissions, exposed secrets, overly permissive firewall rules. You are read-only —
    never modify code, only report findings with severity levels (critical/high/medium/low).
  '';

  # The four agents above are written inline because this file is their only
  # source. These four are not: they were authored elsewhere and copied in, so
  # they stay as files and get declared by source. Keeping the two forms apart
  # matters — an inline rewrite of a vendored agent silently forks it.
  #
  # The two thermo subagents pair with the skills in skills.nix; their rubrics
  # live in ~/.claude/skills/thermo-nuclear-*/SKILL.md, which those declarations
  # now own, so agent and rubric travel together.
  home.file.".claude/agents/doc-writer.md".source = ./agents/doc-writer.md;
  home.file.".claude/agents/researcher.md".source = ./agents/researcher.md;
  home.file.".claude/agents/thermo-nuclear-review-subagent.md".source =
    ./agents/thermo-nuclear-review-subagent.md;
  home.file.".claude/agents/thermo-nuclear-code-quality-review-subagent.md".source =
    ./agents/thermo-nuclear-code-quality-review-subagent.md;

  # ~/.claude/rules/ — read by the pstack skill to decide which model each role
  # runs on. Undeclared until now, which meant a fresh install would silently
  # fall back to the skill's own defaults instead of this budget-conscious map.
  home.file.".claude/rules/pstack-models.md".source = ./rules/pstack-models.md;
}
