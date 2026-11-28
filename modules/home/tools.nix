{
  config,
  pkgs,
  lib,
  ...
}:

# Local tooling around Claude Code: status line, artifact index + viewers, compliance scan.
# Sources live in ./scripts so they can be tested outside Nix; these wrappers pin their runtime deps.
let
  # The writer adds its own shebang; drop the source's so flake8 doesn't trip over line 2.
  # E203 is on the list because black formats slices as `a[i : i + 2]` and flake8 flags it —
  # black's own docs call E203 wrong. The repo's formatter hook would undo any manual fix.
  py =
    name: file:
    pkgs.writers.writePython3Bin name {
      flakeIgnore = [
        "E501"
        "W503"
        "E203"
      ];
    } (lib.removePrefix "#!/usr/bin/env python3\n" (builtins.readFile file));

  statusline = py "claude-statusline" ./scripts/claude-statusline.py;
  artifactHook = py "claude-artifact-hook" ./scripts/claude-artifact-hook.py;
  artifacts = py "claude-artifacts" ./scripts/claude-artifacts.py;
  # EU VAT validation against VIES; replaces the vies-vat MCP server (q-vies-vat).
  vatCheck = py "vat-check" ./scripts/vat-check.py;

  # Wrap the Python tools so `git` is always found (they shell out to it).
  withGit =
    drv: name:
    pkgs.symlinkJoin {
      inherit name;
      paths = [ drv ];
      nativeBuildInputs = [ pkgs.makeWrapper ];
      postBuild = "wrapProgram $out/bin/${name} --prefix PATH : ${lib.makeBinPath [ pkgs.git ]}";
    };

  artifactsPick = pkgs.writeShellApplication {
    name = "claude-artifacts-pick";
    runtimeInputs = with pkgs; [
      fzf
      bat
      chafa
      xdg-utils
      artifacts
    ];
    text = ''
      # Fuzzy-pick any file Claude wrote (all projects), preview it, open it with the default app.
      # shellcheck disable=SC2016  # the preview command is expanded by fzf, not here
      claude-artifacts --all --paths --limit 500 |
        fzf --prompt 'artifact › ' --height 100% \
          --preview 'case {} in *.png|*.jpg|*.jpeg|*.webp|*.gif) chafa --size "$FZF_PREVIEW_COLUMNS"x"$FZF_PREVIEW_LINES" {} ;; *) bat --color=always --style=numbers {} ;; esac' |
        xargs -r -I{} xdg-open {}
    '';
  };

  # Browser automation for agents. Snapshots/screenshots go to ./.playwright-cli/ instead of into
  # the context window. Uses nixpkgs' Chromium: npm-downloaded browsers don't run on NixOS.
  playwrightCli = pkgs.writeShellApplication {
    name = "playwright-cli";
    runtimeInputs = [ pkgs.nodejs ];
    text = ''
      export PLAYWRIGHT_MCP_EXECUTABLE_PATH="''${PLAYWRIGHT_MCP_EXECUTABLE_PATH:-${pkgs.chromium}/bin/chromium}"
      export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
      exec npx -y @playwright/cli@0.1.22 "$@"
    '';
  };

  # Kokoro-82M TTS for Hyperframes. kokoro-onnx isn't in nixpkgs, so it lives in a pip venv
  # (`just setup-tts`); its manylinux wheels then dlopen libstdc++/libgcc_s (numpy, onnxruntime)
  # and libz, which a nix python doesn't put on the loader path — numpy then fails to import and
  # Hyperframes misreports it as "the kokoro-onnx package is not installed".
  # nix-ld doesn't cover this: it patches foreign *executables*, not dlopen from a nix interpreter.
  # Scoped to this wrapper rather than exported from the hyperframes one below, so the ffmpeg and
  # chromium Hyperframes shells out to never inherit a library path meant for the wheels — an
  # inherited LD_LIBRARY_PATH is exactly what broke them before (see the overlay in flake.nix).
  ttsPython = pkgs.writeShellApplication {
    name = "hyperframes-python";
    text = ''
      venv="$HOME/.local/share/hyperframes/venv"
      if [ ! -x "$venv/bin/python" ]; then
        echo "hyperframes: TTS venv is missing — run 'just setup-tts' to create it" >&2
        exit 1
      fi
      export LD_LIBRARY_PATH=${
        lib.makeLibraryPath [
          pkgs.stdenv.cc.cc.lib
          pkgs.zlib
        ]
      }
      exec "$venv/bin/python" "$@"
    '';
  };

  # Hyperframes (HTML → MP4), the renderer the /brag skill family drives. Same NixOS problem
  # playwrightCli solves — npm-downloaded browsers don't run here — plus local voice via ttsPython.
  hyperframes = pkgs.writeShellApplication {
    name = "hyperframes";
    runtimeInputs = [
      pkgs.nodejs
      pkgs.unzip # doctor's "archive extractor"; p7zip in packages.nix isn't what it probes for
    ];
    text = ''
      # Hygiene, not a workaround: this shells out to stable-channel chromium/ffmpeg and to
      # npm-downloaded native modules, none of which should inherit whatever library path the
      # caller happened to export. ttsPython sets its own; a stale Claude session still carries
      # the pre-override alsa path (flake.nix) and would otherwise break both of the above.
      unset LD_LIBRARY_PATH
      export HYPERFRAMES_BROWSER_PATH="''${HYPERFRAMES_BROWSER_PATH:-${pkgs.chromium}/bin/chromium}"
      export HYPERFRAMES_PYTHON="''${HYPERFRAMES_PYTHON:-${ttsPython}/bin/hyperframes-python}"
      export HYPERFRAMES_FFMPEG_PATH="''${HYPERFRAMES_FFMPEG_PATH:-${pkgs.ffmpeg-full}/bin/ffmpeg}"
      export HYPERFRAMES_FFPROBE_PATH="''${HYPERFRAMES_FFPROBE_PATH:-${pkgs.ffmpeg-full}/bin/ffprobe}"
      exec npx -y hyperframes@0.9.9 "$@"
    '';
  };

  complianceScan = pkgs.writeShellApplication {
    name = "compliance-scan";
    runtimeInputs = [
      pkgs.ripgrep
      pkgs.coreutils
    ];
    # no errexit: the scan is a series of greps where "no match" (exit 1) is the good outcome
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./scripts/compliance-scan.sh;
  };

  # What a plugin or skill tree would bring onto the machine, before `claude plugin install`
  # runs its code. Ships to all four of us rather than living in the justfile alone, because
  # the person about to install something is the one who needs it.
  claudeVet = pkgs.writeShellApplication {
    name = "claude-vet";
    runtimeInputs = with pkgs; [
      ripgrep
      jq
      coreutils
      findutils
      gnugrep
      gnused
    ];
    # same reason as compliance-scan: this is greps, and "no match" is usually the good outcome
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./scripts/claude-vet.sh;
  };

  # The other half of the vetting story: claude-vet says what a tree would bring, this says
  # whether what the machine is actually running is still what the repo declares. `gh` is
  # optional — only --remote uses it — so it is not a runtime input.
  pluginsCheck = pkgs.writeShellApplication {
    name = "claude-plugins-check";
    runtimeInputs = with pkgs; [
      jq
      git
      coreutils
      findutils
    ];
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./scripts/claude-plugins-check.sh;
  };
in
{
  home.packages = [
    # repomix as a CLI only — never `repomix --mcp`, and never to pack a repo into context,
    # which is the opposite of the budget discipline in research/context-budget.md. What it is
    # here for is measuring (`--token-count-tree`, `--token-budget`) and its Secretlint pass
    # (on by default; `--no-security-check` turns it off) as a pre-flight before anything is
    # shared. Note the release split: 26.05 has 1.15.0 with both measuring flags, 25.05 has
    # 0.3.3 with neither — only the secret scan works there, so measure on 26.05.
    pkgs.repomix

    (withGit statusline "claude-statusline")
    (withGit artifactHook "claude-artifact-hook")
    (withGit artifacts "claude-artifacts")
    artifactsPick
    complianceScan
    vatCheck
    claudeVet
    pluginsCheck
    playwrightCli
    hyperframes
    ttsPython
  ];

  # Stable paths the settings file points at (store paths change every generation).
  home.file.".claude/statusline.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      exec ${withGit statusline "claude-statusline"}/bin/claude-statusline
    '';
  };
  home.file.".claude/hooks/record-artifact.sh" = {
    executable = true;
    text = ''
      #!/usr/bin/env bash
      # PostToolUse (async): index files Claude writes into ~/.local/state/claude-artifacts/index.sqlite
      exec ${withGit artifactHook "claude-artifact-hook"}/bin/claude-artifact-hook
    '';
  };
}
