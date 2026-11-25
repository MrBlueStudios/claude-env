# claude-env — tests. Nothing here switches a system.
#
# `test` was evaluation-only until 2026-11-20, and that is how two scripts reached `main` with a
# build failure in them: `pkgs.writeShellApplication` runs `bash -n` and `shellcheck` in its
# *check* phase, which a `nix eval` never reaches. The suite was green, and `nh os switch` on
# Léon's laptop was not. `test-shellcheck` closes that, and it is the same tool with the same
# default flags rather than a lint of our own choosing — plus one trap worth stating: the Nix
# build sandbox has no locale, so a shellcheck diagnostic whose context line holds a non-ASCII
# character (an em dash, which these scripts are full of) dies with "cannot encode character"
# and exit 2. A style warning nobody would act on therefore breaks a system build, so the
# findings have to be at zero rather than merely understood.

set shell := ["bash", "-c"]

root := justfile_directory()
# The test flakes declare claude-env as `path:../..`, but Nix resolves relative inputs against the
# store copy, so the root is passed explicitly and the lock files keep only the nixpkgs/home-manager pins.
overrides := "--no-write-lock-file --override-input claude-env path:" + root + " --override-input web-stack path:" + root + "/tests/web-stack-stub"
# Nix prints the in-memory lock changes on every run; drop that noise but keep real errors.
quiet := "2> >(grep -v -e '^• ' -e '^    ' -e 'not writing modified lock' -e 'is dirty' >&2)"

default: test

# Evaluate the home-manager module (base + blitsol) and the NixOS guard on both supported releases,
# then run the guard and helper-script tests.
test: test-25-05 test-26-05 test-shellcheck test-guard test-scripts test-share-app test-build

# The same suite without the two real builds: everything that runs in seconds, for the inner
# loop. `test` is what runs before a commit, because `test-fast` is exactly what was green
# while the switch was broken.
test-fast: test-25-05 test-26-05 test-shellcheck test-guard test-scripts test-share-app

# The ground truth the eval tests cannot reach: actually build what `nh os switch` builds, so a
# failing check phase inside any writeShellApplication is caught here instead of on a laptop.
# ~40 s per release once the store is warm, minutes on a cold one. test-shellcheck is the fast
# proxy for the same failure; this is the one that cannot be fooled.
#
# Three builds per release, because the first fix covered one of them. A base-tier friend's
# generation; the same module with *every* option on, which is the only thing that builds the
# derivations behind an off-by-default flag (claude-mode, the six opt-in MCP servers); and the
# *system* guard, whose claude-guard script is a writeShellApplication of its own. Building the
# managed-settings file is enough for the last — its `command` interpolates the guard's store
# path, so the string context makes Nix realise the script in order to write the JSON.
test-build:
    @cd {{ root }} && for d in tests/eval-25.05 tests/eval-26.05; do \
        printf '%-22s %-8s ' "$d" build; \
        (cd "$d" && nix build --no-link {{overrides}} "path:$PWD#homeConfigurations.base.activationPackage" {{quiet}}) \
          && echo "home-manager generation builds: ok" || exit 1; \
        printf '%-22s %-8s ' "$d" all-on; \
        (cd "$d" && nix build --no-link {{overrides}} "path:$PWD#homeConfigurations.everything.activationPackage" {{quiet}}) \
          && echo "every option on builds too: ok" || exit 1; \
        printf '%-22s %-8s ' "$d" guard; \
        (cd "$d" && nix build --no-link {{overrides}} "path:$PWD#nixosConfigurations.guard.config.environment.etc.\"claude-code/managed-settings.json\".source" {{quiet}}) \
          && echo "claude-guard builds: ok" || exit 1; \
      done

# Every script the module wraps in writeShellApplication, checked the way its check phase does:
# `bash -n -O extglob` then `shellcheck` with no flags. Run against the source rather than the
# assembled file, so it needs no build — the assembled version only adds a shebang and `set -o`
# lines, neither of which changes a finding. A finding here is a failed `nh os switch`.
test-shellcheck:
    @cd {{ root }} && fail=0; \
      if command -v shellcheck >/dev/null; then sc="shellcheck"; else sc="nix run nixpkgs#shellcheck --"; fi; \
      for f in modules/home/scripts/*.sh modules/system/claude-code/*.sh; do \
        case "$f" in *tests.sh|*-test.sh) continue ;; esac; \
        bash -n -O extglob "$f" || { echo "bash -n: $f"; fail=1; }; \
        LC_ALL=C.UTF-8 $sc -s bash "$f" || fail=1; \
      done; \
      [ "$fail" = 0 ] && echo "shellcheck: $(ls modules/home/scripts/*.sh modules/system/claude-code/*.sh | grep -vcE 'tests\.sh|-test\.sh') packaged script(s) clean" || exit 1

test-25-05:
    @just _eval tests/eval-25.05

test-26-05:
    @just _eval tests/eval-26.05

_eval dir:
    @cd {{dir}} && for c in base blitsol; do \
        printf '%-22s %-8s ' "{{dir}}" "$c"; \
        nix eval --raw {{overrides}} "path:$PWD#homeConfigurations.$c.activationPackage.outPath" {{quiet}} && echo; \
      done
    @# The activation snippet has to find Claude Code without activation's PATH, and the path it
    @# missed on 2026-11-21 is the one home-manager-as-a-NixOS-module actually uses. Asserted
    @# here because the lookup lives in Nix rather than in a script the unit tests can run, and
    @# because its failure mode is a warning nobody reads plus pins that never apply.
    @cd {{dir}} && printf '%-22s %-8s ' "{{dir}}" claudebin && \
      nix eval --raw {{overrides}} "path:$PWD#homeConfigurations.base.config.home.activation.claudeSettings.data" {{quiet}} \
        | grep -q '/etc/profiles/per-user/kish/bin/claude' \
      && echo "finds claude in the per-user profile: ok"
    @cd {{dir}} && printf '%-22s %-8s ' "{{dir}}" guard && \
      nix eval --raw {{overrides}} "path:$PWD#nixosConfigurations.guard.config.environment.etc.\"claude-code/managed-settings.json\".source.outPath" {{quiet}} && echo
    @cd {{dir}} && test "$(nix eval --json {{overrides}} "path:$PWD#homeConfigurations.base.config.home.file" --apply 'f: builtins.length (builtins.filter (n: builtins.match ".claude/skills/(dashboard|council)/.*" n != null) (builtins.attrNames f))' {{quiet}})" = 0 \
      && echo "{{dir}}  base has no claude-mode skills: ok"
    @# The tier split, which is only visible in the resolved MCP server set: a base friend must
    @# get no company server, and the Blitsol tier must get it. Opt-in modules stay off in both.
    @cd {{dir}} && test "$(nix eval --raw {{overrides}} "path:$PWD#homeConfigurations.base.config.claude-env.mcp.declared" --apply 's: builtins.concatStringsSep "," (builtins.attrNames s)' {{quiet}})" = "atlassian,context7,playwright" \
      && echo "{{dir}}  base tier: atlassian, context7, playwright only: ok"
    @cd {{dir}} && test "$(nix eval --raw {{overrides}} "path:$PWD#homeConfigurations.blitsol.config.claude-env.mcp.declared" --apply 's: builtins.concatStringsSep "," (builtins.attrNames s)' {{quiet}})" = "atlassian,cloudflare,context7,playwright" \
      && echo "{{dir}}  blitsol tier: adds cloudflare: ok"

# The PreToolUse guard's own cases (allow / ask / deny).
test-guard:
    bash modules/system/claude-code/guard-test.sh

# The firecrawl wrapper and other helper scripts.
test-scripts:
    bash modules/home/scripts/tests.sh

# The share inbox's Android share target (share-app/). Pure functions only; the page is checked on the phone.
test-share-app:
    node --test share-app/*.test.mjs

# Publish share-app/ to https://crew-share.pages.dev. Needs `nix run nixpkgs#wrangler -- login` once.
share-deploy:
    nix run nixpkgs#wrangler -- pages deploy share-app --project-name crew-share --branch main

# Send a link to the crew inbox from the laptop: `just share https://example.com "why it matters"`
[positional-arguments]
share url note="":
    gh issue create -R MrBlueStudios/crew-vault -l inbox --title "$1" --body "$(printf '%s %s\n\nvia: laptop' "$1" "${2:-}")"

# What a plugin or skill tree would bring onto this machine. Run it on a checkout *before*
# `claude plugin install` executes any of its code. Exits 1 on a blocking finding; the
# exemptions it honours are in docs/vet-exemptions.md.
vet path:
    @bash {{ root }}/modules/home/scripts/claude-vet.sh \
      --exemptions {{ root }}/docs/vet-exemptions.md {{ path }}

# Where this machine's plugins have drifted from what the repo declares: a marketplace off its
# pin, a plugin enabled but never installed (or installed and never enabled), a cache left over
# from an uninstall. Pass --remote to also ask GitHub how far behind each pin now is.
plugins-check *args:
    @bash {{ root }}/modules/home/scripts/claude-plugins-check.sh {{ args }}
