# claude-env — evaluation tests. Nothing here builds or switches a system.

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
test: test-25-05 test-26-05 test-guard test-scripts

test-25-05:
    @just _eval tests/eval-25.05

test-26-05:
    @just _eval tests/eval-26.05

_eval dir:
    @cd {{dir}} && for c in base blitsol; do \
        printf '%-22s %-8s ' "{{dir}}" "$c"; \
        nix eval --raw {{overrides}} "path:$PWD#homeConfigurations.$c.activationPackage.outPath" {{quiet}} && echo; \
      done
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
