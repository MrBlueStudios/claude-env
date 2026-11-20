{
  config,
  pkgs,
  lib,
  ...
}:

# MCP servers, declared rather than registered by hand.
#
# Claude Code reads them from three places: `mcpServers` at the top of ~/.claude.json (user
# scope, every project), `projects[<dir>].mcpServers` in the same file (local scope, one
# directory), and a committed .mcp.json per repo (project scope). It never reads them from
# settings.json. This module owns the first and prunes the second; project scope stays with the
# repo that needs it, which is the one place a per-client token legitimately lives.
#
# Which servers, and why each one, is docs/mcp-audit.md (16 Nov 2026): 39 registrations, 23
# dropped, of which 8 were dead placeholders. The rule it applies is CLAUDE.md's: no MCP server
# where a CLI does the job better, because a server's tool list is a standing cost and `gh`,
# `playwright-cli`, `docker` and `tailscale` are not.
#
# Three corrections to that audit, found while wiring it up on 2026-11-20:
#
#   - moneybird is gone, not fixed. It was the one server that justified the shared secrets
#     repo, and on 17 Nov Blitsol moved off Moneybird to AdministratieX. So the Blitsol tier
#     adds one server (cloudflare, per-person OAuth, no secret) plus two account invites.
#   - overheid-apis does not exist. `npx -y @dstotijn/mcp-developer-overheid-api-register`
#     resolves to nothing on the npm registry, so that registration has never started a server.
#     It is a ninth dead placeholder, with a different failure mode than the eight token stubs.
#     The `legal` module is eu-law alone.
#   - vies-vat is not Léon's own build. It is a clone of Jazib-but/check-vat-vies-mcp-Jazib
#     (MIT, no hooks, reaches ec.europa.eu, which is the real VIES API), registered as
#     `node /home/leon-new/projects/.../dist/index.js`. Packaging someone else's template repo
#     to give four laptops a VAT lookup is the wrong trade when a 40-line CLI does it with no
#     session cost at all. It is therefore not declared here — see q-vies-vat.
let
  cfg = config.claude-env;
  blitsol = cfg.tier == "blitsol";
  on = cfg.mcp.modules;

  http = url: {
    type = "http";
    inherit url;
  };
  npx = spec: args: {
    type = "stdio";
    command = "npx";
    args = [
      "-y"
      spec
    ]
    ++ args;
  };

  # 26.05 has playwright-mcp 0.0.69 and mcp-nixos 2.4.3; 25.05 has neither, so both fall back to
  # a pinned fetch rather than `@latest`, which would make the tool list change under people.
  # Either way the browser is nixpkgs' chromium: an npm-downloaded one does not run on NixOS,
  # which is the same problem playwright-cli solves in ./tools.nix.
  playwrightArgs = [
    "--headless"
    "--isolated"
    "--executable-path"
    "${pkgs.chromium}/bin/chromium"
  ];
  playwright =
    (
      if pkgs ? playwright-mcp then
        {
          type = "stdio";
          command = "${pkgs.playwright-mcp}/bin/mcp-server-playwright";
          args = playwrightArgs;
        }
      else
        npx "@playwright/mcp@0.0.86" playwrightArgs
    )
    // {
      env.PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
    };

  nixos =
    if pkgs ? mcp-nixos then
      {
        type = "stdio";
        command = "${pkgs.mcp-nixos}/bin/mcp-nixos";
      }
    else
      {
        type = "stdio";
        command = "uvx";
        args = [ "mcp-nixos==2.4.3" ];
      };

  firecrawlVersion = "3.30.3";

  # null → Firecrawl cloud, authenticated with the agenix key.
  # A URL → a self-hosted instance, which then needs no key. If that instance ever
  # runs somewhere other than this laptop, bind it to the tailnet rather than a public
  # port: the self-hosted API ships unauthenticated (see their SELF_HOST.md).
  firecrawlApiUrl = null;

  # Reads /run/agenix/firecrawl-api-key, then execs the npm server. The key is never passed with
  # `claude mcp add --env`, which writes the literal value into ~/.claude.json. Source is a plain
  # file so it can be run and tested outside Nix.
  firecrawl = pkgs.writeShellApplication {
    name = "firecrawl-mcp-agenix";
    runtimeInputs = [ pkgs.nodejs ];
    # writeShellApplication supplies its own shebang, so drop the source's rather than
    # leave a second one mid-file. The version pin lives here, next to the others, so Nix
    # stays the single source of truth for what gets fetched.
    text =
      "export FIRECRAWL_MCP_VERSION=${firecrawlVersion}\n"
      + lib.optionalString (firecrawlApiUrl != null) "export FIRECRAWL_API_URL=${firecrawlApiUrl}\n"
      + lib.removePrefix "#!/usr/bin/env bash\n" (builtins.readFile ./scripts/firecrawl-mcp.sh);
  };

  servers =
    # ── base: everyone, no credential of anyone else's ──────────────────────
    {
      # Current library docs, and the cheapest server measured (239 tokens). Keyless over HTTP
      # is rate-limited per IP; a person who hits that limit adds their own key, which is why
      # this is a plain URL rather than a wrapper around a secret.
      context7 = http "https://mcp.context7.com/mcp";

      # Jira and Confluence. Writes are behind an `ask` rule in the guard (ct-atlassian-ask),
      # because this server can transition issues and edit pages in a shared site.
      atlassian = http "https://mcp.atlassian.com/v2/mcp";

      inherit playwright;
    }

    # ── blitsol: the company tier ───────────────────────────────────────────
    // lib.optionalAttrs blitsol {
      # Official Cloudflare API server, per-person OAuth, so the flake carries no credential.
      # `wrangler` covers deploys; this covers everything else.
      cloudflare = http "https://mcp.cloudflare.com/mcp";
    }

    # ── opt-in modules: off by default, each one a standing token cost ──────
    // lib.optionalAttrs on.sentry {
      # 1,089 tokens, the most expensive server measured. Only projects that ship to Sentry.
      sentry = http "https://mcp.sentry.dev/mcp";
    }
    // lib.optionalAttrs on.nix { mcp-nixos = nixos; }
    // lib.optionalAttrs on.legal {
      eu-law = npx "@ansvar/eu-regulations-mcp@1.1.2" [ ];
    }
    // lib.optionalAttrs on.trading {
      # Keyless and free. Registered as plain HTTP rather than through mcp-remote: Claude Code
      # speaks HTTP itself, so the bridge is a third-party package in the path for nothing.
      coingecko = http "https://mcp.api.coingecko.com/mcp";
    }
    // lib.optionalAttrs on.seo {
      # Needs a Google Cloud OAuth client of your own; there is no official Google server.
      # Point GOOGLE_APPLICATION_CREDENTIALS at it in your own home config — not here, because
      # a path into one person's home is not shareable and a key in the store is not private.
      gsc = npx "mcp-server-gsc@0.3.0" [ ];
    }
    // lib.optionalAttrs on.firecrawl {
      # Registered by wrapper name, not store path: the path changes on every rebuild and would
      # rot in ~/.claude.json. home.packages puts the wrapper on PATH.
      firecrawl = {
        type = "stdio";
        command = "firecrawl-mcp-agenix";
      };
    }

    # Laya: small, calibrated, CPU-fine, and useful in every project rather than one, so it goes
    # to user scope with an absolute path. CLM is deliberately absent — it is parked until a
    # 24 GB card exists, and a registered server with no backend is a tool that always fails.
    // lib.optionalAttrs (cfg.mcp.layaPath != null) {
      laya-mcp-server = {
        type = "stdio";
        command = "uv";
        args = [
          "run"
          "--project"
          "${cfg.mcp.layaPath}/laya-mcp-server"
          "--frozen"
          "--quiet"
          "laya-decision-mcp"
        ];
        env = {
          LAYA_MCP_MODEL = "auto";
          LAYA_MCP_PRELOAD = "english";
        };
      };
    }

    // cfg.mcp.personal;

  # Names to remove wherever they are found, including the local scopes under ~ and
  # ~/projects/fastsdcpu that made 24 servers reachable from one directory each. Everything here
  # has a verdict in docs/mcp-audit.md; the reason is one of three — a CLI does it better, the
  # registration was a dead placeholder, or it duplicates something that stays.
  dropped = [
    # settled: a CLI or a built-in does it better
    "github"
    "filesystem"
    "memory"
    "sequential-thinking"
    "docker"
    "ollama"
    "tailscale"
    "lighthouse"
    "eslint"
    "a11y"
    "fonts"
    # settled: covered by context7 or the svelte plugin
    "shadcn-svelte"
    "gsap"
    # dead placeholders: a stub token, or a package that does not exist
    "elevenlabs"
    "figma-dev"
    "inspiration"
    "shopify"
    "overheid-apis"
    # duplicates of something that stays
    "stripe" # the Stripe connector is the Blitsol-tier path
    "moneybird" # Blitsol left Moneybird on 17 Nov; nothing replaces the server
    # not crew tools
    "todoist" # Jira is
    "lottie"
  ];

  declared = pkgs.writeText "claude-mcp-servers.json" (builtins.toJSON { mcpServers = servers; });

  writer = pkgs.writeShellApplication {
    name = "claude-mcp-apply";
    runtimeInputs = with pkgs; [
      jq
      coreutils
    ];
    bashOptions = [
      "nounset"
      "pipefail"
    ];
    text = builtins.readFile ./scripts/claude-mcp.sh;
  };
in
{
  claude-env.mcp.declared = servers;

  home.packages = lib.optional on.firecrawl firecrawl;

  # ~/.claude.json is Claude Code's own state file, so the script edits the parsed document and
  # moves it into place atomically rather than rewriting it; it declines to create one that does
  # not exist yet, because a state file without an account is worse than none.
  home.activation.claudeMcp = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    run ${writer}/bin/claude-mcp-apply "$HOME/.claude.json" ${declared} ${lib.escapeShellArgs dropped} \
      || warnEcho "the declared MCP servers were not written to ~/.claude.json; see above."
  '';
}
