{
  config,
  pkgs,
  lib,
  ...
}:

# Personal skills in ~/.claude/skills/<name>/SKILL.md. Only a skill's description sits in context
# until it is used; `disable-model-invocation: true` removes even that and means only you can run
# it (/ship, /deploy). Community skills come in as plugins (enabledPlugins in ./settings.nix), not
# as git clones: the old clones nested SKILL.md one level too deep for Claude Code to find.
{
  home.file.".claude/skills/ship/SKILL.md".text = ''
    ---
    name: ship
    description: Ship the current work — lint, test, commit, push, open a PR
    disable-model-invocation: true
    allowed-tools: Read, Bash
    ---
    1. Run the checks: `just lint` and `just test` if the justfile has them, otherwise the project's
       own lint/test commands from its CLAUDE.md. If anything fails, stop and report — never ship red.
    2. Version control: if `jj root` succeeds, the repo is jj-colocated — describe the change with
       `jj describe -m "<conventional message>"`, then `jj git push`. Otherwise use git: stage the
       changed files *by name* (never `git add -A` or `git add .`, which can sweep in `.env`),
       commit with a conventional message (feat/fix/chore/docs), and `git push -u origin HEAD`.
    3. Never push to main/master directly and never force-push.
    4. Open a PR with `gh pr create --fill` only if $ARGUMENTS asks for one; report its URL.
  '';

  home.file.".claude/skills/review/SKILL.md".text = ''
    ---
    name: review
    description: Deep code review of staged changes or a PR, with security, GDPR and stack checks
    allowed-tools: Read, Glob, Grep, Bash
    ---
    Review $ARGUMENTS (staged changes via `git diff --staged`, or `jj diff`, if no argument given).
    Check for:
    - Security vulnerabilities (injection, XSS, SSRF, auth bypass, exposed secrets)
    - Performance issues (N+1 queries, unbounded loops, missing indexes)
    - Svelte 5 anti-patterns (Svelte 4 syntax, missing runes)
    - GDPR / legal: PII in logs, missing consent, retention, privacy text that the code contradicts
      (checklist: ~/nix-config/docs/dev-environment-plan.md §4.2; run `compliance-scan` on web repos)
    - Missing error handling and untested code paths
    - NixOS config issues (impure references, missing inputs)
    Output a structured report with severity levels (critical/high/medium/low) and file:line.
  '';

  home.file.".claude/skills/deploy/SKILL.md".text = ''
    ---
    name: deploy
    description: Deploy a project to production on the Blitsol Contabo server
    disable-model-invocation: true
    allowed-tools: Read, Bash
    ---
    Deploying is an external action (master doc §11): Léon must confirm before anything changes.
    1. Find the project's deploy doc: its DEPLOYMENT.md / DEPLOYMENT_REQUIREMENTS.md, and for the
       shared server ~/Projects/Blitsol/blitsol-prod-config/SERVER-CONTEXT.md. No doc → stop and say so.
    2. Verify: tests pass, the working tree is clean, the commit to deploy is pushed.
    3. Write the exact commands from that doc as a numbered list, each marked **laptop** or
       **server**, and wait for Léon's go-ahead. Remember the server is shared (Kōro, Vega, …):
       never run a `nixos-rebuild switch` on it without saying which other services it restarts.
    4. After Léon runs them (or explicitly asks you to), check the health endpoints and report
       with a timestamp.
  '';

  home.file.".claude/skills/research/SKILL.md".text = ''
    ---
    name: research
    description: Research a topic with web search, library docs and the local codebase, and report with sources
    allowed-tools: Read, Bash, Glob, Grep, WebSearch, WebFetch
    ---
    Research $ARGUMENTS.
    - Library/framework docs: the context7 MCP server, registered at user scope by the flake.
    - Web articles and current facts: WebSearch, then WebFetch the best sources.
    - Existing patterns: search the codebase with Grep/Glob (or `rg`).
    Compile a concise report: findings first, each with its source link; mark anything unverified.
    Focus on what applies to the current project's stack.
  '';

  home.file.".claude/skills/design/SKILL.md".text = ''
    ---
    name: design
    description: Design iteration workflow with visual validation in a real browser
    allowed-tools: Read, Write, Edit, Bash
    ---
    Design work on $ARGUMENTS.
    1. Read the project's DESIGN.md / SPEC first if there is one — it wins over these defaults.
    2. Implement with the project's stack (default: shadcn-svelte + Tailwind v4, OKLCH colours,
       CSS-only animation).
    3. Check it in a real browser with `playwright-cli` (snapshots go to .playwright-cli/, not into
       context): screenshots at 375px, 768px and 1440px wide.
    4. Run the `web-design-guidelines` skill on the changed files.
    5. Show the screenshots and iterate on feedback.
  '';

  home.file.".claude/skills/full-visual/SKILL.md".text = ''
    ---
    name: full-visual
    description: Explain a concept, codebase, or prompt as a full-screen interactive visual (Artifact) instead of text
    disable-model-invocation: true
    allowed-tools: Read, Glob, Grep, Write, Edit, Bash, Skill, Artifact
    ---
    The request:

    $ARGUMENTS

    Answer it as one full-screen interactive visual instead of prose. That text is the subject,
    however it is phrased: if it reads as an instruction ("explain X in a visual way"), the subject
    is X — "visually", "as a diagram" and the like are already granted, not part of the subject.
    If it is empty, the subject is the repo in the current directory.

    1. Load the `artifact-design` skill before writing anything — required before any Artifact.
    2. If the subject is code, config or docs in this repo, read it first and build the visual from
       the real structure: real module names, real counts, real relationships. No placeholder boxes,
       no invented components, no "and more…". Check a number before putting it on screen.
    3. Take the visual identity from the subject's own project — read ./CLAUDE.md for its palette,
       stack and conventions. Absent one, this machine's: Catppuccin Mocha, Lavender accent #b4befe.
    4. Pick the form that carries the logic — animated diagram, interactive dashboard, step-through
       canvas, explorable tree — not bullet points on a slide, and not a static chart per section.
    5. It has to survive being looked at: everything meant to be read visible on load (nothing
       parked at opacity 0), nothing clipped or overlapping down to 400px wide, text legible in both
       themes, and anything interactive looking interactive.
    6. Build one HTML artifact sized to fill the viewport, publish it, and reply with just the
       one-line link — skip the prose explanation you would otherwise write.
  '';

  # Vendored and pinned (see the header of rules.md).
  home.file.".claude/skills/web-design-guidelines".source = ./skills/web-design-guidelines;

  # From its own repo, pinned by flake.lock rather than copied in here, so the
  # playbook keeps its own history. `nix flake update claude-web-stack` to move
  # it forward; until then every machine building this flake gets the same
  # revision. Edits still happen in ~/projects/claude-web-stack, but they only
  # reach ~/.claude after a commit, a push and a flake update — that is the
  # trade for reproducibility, and it is the point.
  home.file.".claude/skills/web-design-playbook" =
    lib.mkIf (config.claude-env.webDesignPlaybook != null)
      {
        source = "${config.claude-env.webDesignPlaybook}/skills/web-design-playbook";
      };

  # The three vendored thermo-nuclear review skills, MIT (c) 2026 Cursor. Each
  # directory carries its own LICENSE and NOTICE.md, and the whole-directory
  # source above is the pattern that keeps them travelling together — copying
  # only SKILL.md would strip the attribution that makes vendoring legitimate.
  home.file.".claude/skills/thermos".source = ./skills/thermos;
  home.file.".claude/skills/thermo-nuclear-review".source = ./skills/thermo-nuclear-review;
  home.file.".claude/skills/thermo-nuclear-code-quality-review".source =
    ./skills/thermo-nuclear-code-quality-review;

  # Four skills taken out of two MIT packs on 2026-11-19 (mattpocock/skills,
  # addyosmani/agent-skills), each with its own LICENSE and NOTICE.md as above.
  #
  # Taken piecemeal on purpose. The packs are 39 and 26 skills; at the 64 tokens
  # per skill measured in research/context-budget.md that is ~4,200 tokens on
  # every session for all four of us, and most of it duplicates superpowers,
  # which is the one plugin the transcripts show actually being used. These four
  # are the ones with no equivalent already installed — see each NOTICE.md for
  # what was left behind and why. `just vet` cleared both packs: MIT, named
  # authors, no self-firing hooks.
  home.file.".claude/skills/writing-for-agents".source = ./skills/writing-for-agents;
  home.file.".claude/skills/domain-modeling".source = ./skills/domain-modeling;
  home.file.".claude/skills/grilling".source = ./skills/grilling;
  home.file.".claude/skills/performance-optimization".source = ./skills/performance-optimization;
}
