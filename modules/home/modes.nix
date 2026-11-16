{
  config,
  pkgs,
  lib,
  ...
}:

# Claude Code "modes": /normal, /dashboard, /rapid, /council, /roblox.
#
# Claude Code cannot repaint its own TUI, so a mode is a Kitty window layout built *around* the
# live session with `kitten @` remote control (modules/home/kitty.nix sets allow_remote_control).
# The chat pane is never closed or restarted — panes are added beside it and torn down again.
#
# Three tools:
#   claude-mode  layout engine (bash + kitten @)
#   cmode        the panes themselves (one Textual app per subcommand)
#   brain-sync   projects + their docs -> Obsidian vault, which the brain pane reads
let
  # Same pattern as tools.nix: sources live in ./scripts so they are testable outside Nix.
  py =
    name: libs: file:
    pkgs.writers.writePython3Bin name {
      libraries = libs;
      flakeIgnore = [
        "E501"
        "W503"
        "E203" # black formats slices as `a[i : i + 2]`; flake8 disagrees, black wins
      ];
    } (lib.removePrefix "#!/usr/bin/env python3\n" (builtins.readFile file));

  cmodeRaw = py "cmode" [ pkgs.python3Packages.textual ] ./scripts/cmode.py;
  brainSyncRaw = py "brain-sync" [ ] ./scripts/brain_sync.py;

  # Both shell out, and a Python writer gets no PATH of its own: cmode needs curl for the
  # USD→EUR rate, git/jj for repo state and xdg-open for Obsidian; brain-sync needs git.
  wrap =
    drv: name: deps:
    pkgs.symlinkJoin {
      inherit name;
      paths = [ drv ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = "wrapProgram $out/bin/${name} --prefix PATH : ${lib.makeBinPath deps}";
    };

  cmode = wrap cmodeRaw "cmode" (
    with pkgs;
    [
      curl
      git
      jujutsu
      xdg-utils
      kitty # `kitten @ send-text`: how a pane types into the session's prompt
    ]
  );
  # procps for the pgrep that checks whether Obsidian is running before editing its config.
  brainSync = wrap brainSyncRaw "brain-sync" (
    with pkgs;
    [
      git
      procps
    ]
  );

  # `cmode` must be on PATH for the panes to start, and `kitten` talks to the running Kitty.
  claudeMode = pkgs.writeShellApplication {
    name = "claude-mode";
    runtimeInputs = [
      pkgs.kitty
      pkgs.jq
      cmode
    ];
    # No errexit: the script is full of probes where a non-zero exit is a normal answer.
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./scripts/claude-mode.sh;
  };
in
# Kitty-only: every layout is driven by `kitten @`, so this is opt-in (claude-env.modes.enable).
lib.mkIf config.claude-env.modes.enable {
  home.packages = [
    claudeMode
    cmode
    brainSync
  ];

  # --- the five modes --------------------------------------------------------
  # All five are `disable-model-invocation: true`: switching Léon's layout is his call, never a
  # side effect of something Claude decided to do.

  home.file.".claude/skills/normal/SKILL.md".text = ''
    ---
    name: normal
    description: Collapse every dashboard pane — back to the plain Claude Code terminal
    disable-model-invocation: true
    allowed-tools: Bash
    ---
    Run `claude-mode normal`. It closes only the panes a mode created, never this session.
    Report the result in one line. Do not explain anything further.
  '';

  home.file.".claude/skills/dashboard/SKILL.md".text = ''
    ---
    name: dashboard
    description: Turn this terminal into the dashboard — task progress, project brain, my todo + guide, status
    disable-model-invocation: true
    allowed-tools: Bash
    ---
    1. Run `claude-mode dashboard`. It builds Kitty splits around this live session: the chat
       keeps running in the bottom-left, taller than the rest of its column.

           ┌───────────────┬───────────────┐
           │ CLAUDE·TASKS  │ PROJECT·BRAIN │
           ├───────────────┤───────────────┤
           │ ▸ the chat    │ MY TODO/GUIDE │
           │   (you type   ├───────────────┤
           │    here)      │ STATUS        │
           └───────────────┴───────────────┘

    2. If it reports that `cmode` is missing, the panes are not built yet: tell Léon to run
       `nh os switch .` and stop. If it says there is no Claude Code session in this tab,
       something is wrong with the session detection — say so rather than retrying.
    3. If BRAIN says there is no vault, offer to run `brain-sync` (about 2 seconds). Do not run it
       without asking — it writes a few hundred notes.
    4. Report in one line which panes came up. The keys are in the STATUS pane; do not list them
       unless asked.
  '';

  home.file.".claude/skills/rapid/SKILL.md".text = ''
    ---
    name: rapid
    description: Rapid-fire one-tap questions while a background agent keeps building
    disable-model-invocation: true
    allowed-tools: Bash, Agent, SendMessage, AskUserQuestion, Read, Edit, Write, Glob, Grep, TodoWrite
    ---
    Goal: $ARGUMENTS

    Keep Léon answering quick questions while real work happens in the background. He must never
    wait on you, and the agent must never wait on him.

    1. Run `claude-mode rapid` so the task feed is visible beside the chat.
    2. **Opening burst.** One AskUserQuestion call with 3-4 questions — the ones where a wrong
       guess would waste the most work. Options only; he should not have to type.
    3. **Dispatch.** Spawn ONE background agent (Agent tool, `subagent_type` matching the work)
       with the goal and every answer so far. Tell it to build, test, and report back both its
       progress and any decision that is blocking it.
    4. **The loop**, repeating until he stops it:
       a. Ask the next question immediately — do not wait for the agent to report.
       b. The moment he answers, SendMessage that answer to the agent, saying what it changes.
       c. Ask the next question in the same turn. Never end a turn without a question pending.
    5. **Question discipline** — this is the whole point, so hold to it:
       - One tap: 2-4 concrete options, your recommendation first.
       - Never ask what the repo, the code or the agent could tell you. Go look instead.
       - Every question must change something being built right now. No trivia, no preferences
         you will not act on.
       - Before each question, one short line on what his last answer changed.
       - Prefer whatever the agent flagged as blocking.
    6. **Stopping.** He says "end rapid", "stop questions" or similar — or the agent reports the
       work is production ready:
       - Stop asking at once.
       - Let the agent finish. Wait for its final report; never kill it mid-task.
       - Leave the layout alone unless he asks for `/normal`.
       - Report: what shipped, which of his answers decided what, and what is still open.
  '';

  home.file.".claude/skills/roblox/SKILL.md".text = ''
    ---
    name: roblox
    description: Roblox game work — Studio/MCP/Rojo state beside the chat, and the live game tree
    disable-model-invocation: true
    allowed-tools: Bash, Read, Edit, Write, Glob, Grep, TodoWrite, AskUserQuestion
    ---
    Goal: $ARGUMENTS

    1. Run `claude-mode roblox`. It builds the layout around this live session:

           ┌──────────────────────────────┐
           │ CLAUDE·TASKS                 │
           ├───────────────┬──────────────┤
           │ ▸ the chat    │ ROBLOX·      │
           │   (you type   │   STUDIO     │
           │    here)      │              │
           └───────────────┴──────────────┘

       The ROBLOX pane shows Studio, the MCP toggle, `rojo serve` and this project's
       `.mcp.json`, plus the Luau tree Rojo is syncing. Its keys: `o` opens Studio, `j` starts or
       stops `rojo serve`, `d` runs the full `roblox-doctor`, `s` sends the highlighted path to
       the prompt. Do not list those keys back to Léon — they are on screen.
    2. **Check the connection before promising anything.** Run `roblox-doctor`. The four things
       that must line up are Studio running, the MCP toggle on, the Rojo plugin installed and
       `Roblox_Studio` in this project's `.mcp.json`. If the doctor says Studio is not running,
       start it with `roblox-studio` and wait — the first launch after an update sits for about
       40 seconds on a cold WebView2 cache and looks frozen. Never launch it twice.
    3. **Do you actually have the tools?** The `Roblox_Studio` MCP server only loads at Claude
       Code startup. If `/mcp` does not list it, say so and tell Léon to restart the session in
       this directory — do not fake it with file edits and call the game tested.
    4. **Work through Studio, not around it.** With the tools live, prefer them over guessing:
       `inspect_instance` and `search_game_tree` to see what is really there, `execute_luau` to
       try something in the open place, `start_stop_play` plus `get_console_output` to test, and
       `screen_capture` to look at the result yourself before claiming it works.
    5. **Source of truth is `src/`, not the place file.** Edit files on disk and let Rojo sync
       them; never write a change only into the live DataModel, and never commit a `.rbxl`.
       `selene src` lints and `stylua src` formats — run both before you say you are done.
    6. Report what changed, what you verified in the running game, and what is still unproven.
  '';

  home.file.".claude/skills/council/SKILL.md".text = ''
    ---
    name: council
    description: Seat several agents on a goal together, regrouping so they critique each other
    disable-model-invocation: true
    allowed-tools: Bash, Agent, SendMessage, AskUserQuestion, Read, Write, Edit, Glob, Grep, TodoWrite
    ---
    Goal: $ARGUMENTS

    You are the chair, not a member. You never argue a position — you dispatch, collect, make them
    read each other, and report.

    1. **The goal.** If $ARGUMENTS is empty or vague, settle it in at most two AskUserQuestion
       calls, then state the goal in one sentence and move on.
    2. Run `claude-mode council`. It prints the path of the council state file; keep it.
    3. **Seat the council.** Three agents unless Léon said otherwise. Give each a distinct remit
       and a genuinely different angle so they are not three copies of you — for example one who
       builds the obvious thing, one whose job is to find what breaks it, and one who has to make
       it fit what already exists. Write the roster to the state file with the Write tool:
       `{"goal": "...", "round": 1, "agents": [{"name": "...", "status": "working", "stance": ""}]}`
       so the COUNCIL pane shows it.
    4. **Round.** Dispatch all agents in ONE message so they run concurrently. Each returns: what
       it did, what it recommends, its biggest doubt, and where it needs another agent.
    5. **Regroup** after every round — this is the part that earns the cost:
       - Update the state file: each agent's status and a one-line stance.
       - Send every agent a digest of the others' findings via SendMessage, and ask it to say
         plainly where it now agrees, where it still disagrees and why, and what it will change.
       - Collect the replies. Name the real disagreements; never average them into mush.
    6. **Léon's calls.** When a disagreement is his to settle (scope, cost, taste, risk), bring it
       with AskUserQuestion — the positions as options, each labelled with who argued it. Do not
       settle those yourself.
    7. **Next round or finish.** Run another round while rounds are still changing the answer.
       Stop when they converge, when he says stop, or when the next round would only restate the
       last. Then: the decision, who dissented and on what, and what got built.
    8. Mark every agent `done` in the state file when the council rises.
  '';
}
