---
name: security-audit
description: Use when asked to check a project's security, scan for vulnerabilities, find hardcoded secrets, audit dependencies for CVEs, test a website or app for weaknesses, or review a Roblox game against exploits — and when deciding what a scan is allowed to point at
allowed-tools: Read, Write, Edit, Bash, Glob, Grep, Skill
---

<!-- Léon's own skill, written for this repo's crew: copied from Claude_testing (claude-lab) skills/security-audit on 2026-11-28. -->

Security audit of $ARGUMENTS. Background: `docs/research/security-tooling.md`.

## 0. A tool that did not run found nothing, and that looks identical to clean

This is the failure that matters. `semgrep: command not found` produces zero findings, and zero
findings is also what a clean repo produces. Every report must therefore carry **two lists: what
was found, and what never ran.** A report with no second list is not trustworthy and must not be
written.

So before anything else:

    for t in semgrep osv-scanner gitleaks trufflehog nuclei bandit selene; do
      printf '%-14s %s\n' "$t" "$(command -v $t || echo MISSING)"
    done

`nix search nixpkgs <name>` finds what is packaged; `nix shell nixpkgs#<name> -c <name> --version`
runs one without installing it. Never record a nixpkgs attribute from memory — several in the
research notes are inferred rather than confirmed, and a wrong attribute reads as "not available"
when the tool is right there.

## 1. Blast radius, before the first command

| Target | Allowed |
| --- | --- |
| A repo on this disk | everything — SAST, dependency, secrets |
| A staging deployment | everything, including active scans |
| **A live site customers use** | **passive only** — ZAP baseline, TLS checks, header inspection |

Nothing active ever points at production. Nuclei and a ZAP active scan against a
Cloudflare-fronted live site trip the WAF, generate real attack-shaped load, and can take the
site down — and the findings that matter on a deployed site (headers, cookie flags, TLS, exposed
paths) are all passive anyway. If he asks for an active production scan, say what it will do and
ask him to confirm the window; this is his decision, not yours.

Scanning infrastructure he owns is fine — Contabo documents it. Scanning anything else is not.

## 2. Web and application surface

| Tool | Invocation | Reads |
| --- | --- | --- |
| semgrep | `semgrep scan --config p/default --config p/secrets --metrics=off --json -o sg.json .` | `results[].check_id`, `path`, `start.line`, `extra.severity`, `extra.message` |
| osv-scanner | `osv-scanner scan --format json -r . > osv.json` | lockfile CVEs; logs go to stderr, so redirect only stdout |
| pip-audit / npm audit | `pip-audit -f json` · `npm audit --json` | cheaper first gate than osv-scanner |
| gitleaks | `gitleaks git --report-format json --report-path gl.json .` | secrets in history and worktree |
| trufflehog | `trufflehog filesystem . --results=verified,unknown --json` | newline-delimited JSON, verified secrets |
| bandit | `bandit -r . -f json -o bandit.json` | Python: `shell=True`, pickle, weak crypto, SQL concat |
| nuclei | `nuclei -u <url> -severity medium,high,critical -jsonl-export n.jsonl -silent` | exposed `.env`/`.git`, default panels, known CVEs |
| testssl.sh | `testssl.sh --jsonfile tls.json <host>` | TLS and cipher configuration at the edge |

**Semgrep cannot see Svelte templates.** It has no `.svelte` grammar, so it reads the `<script>`
block only if pointed at extracted TS — it will never find `{@html}` XSS. Run
`eslint-plugin-svelte` for templates (`svelte/no-at-html-tags`, `svelte/no-target-blank`) and say
in the report that Svelte markup was covered by ESLint, not Semgrep. Claiming Semgrep covered the
frontend is the most plausible-sounding false clean in this stack.

**Never `--config auto`.** It refuses to run with `--metrics=off` — "Cannot create auto config
when metrics are off" — because resolving it uploads project metadata to semgrep.dev. His code
is not telemetry, so name the rule packs explicitly and keep metrics off. Verified on
semgrep 1.x: explicit packs work fine with metrics disabled.

**osv-scanner needs a lockfile, not a manifest.** A `pyproject.toml` with no `uv.lock` or
`requirements.txt` beside it yields `No package sources found` and an **empty output file** — so
the summary reads as a clean repo. Check that each target actually produced findings or an
explicit "clean", and list a repo with no lockfile under not-covered rather than under clean.

**The free Semgrep CLI matches within a single file.** No cross-file taint tracing, so a value
tainted in one module and used unsafely in another is invisible. Say so rather than implying full
coverage.

**A secret that was found is live until it is rotated.** Rotation is his — it is a credential —
so a found secret becomes a `my_todo`, never a line in the report that implies it is handled. Do
not print the secret itself; print the path, the line and what kind it is.

## 3. NixOS has no scanner. Read it yourself.

There is no checkov equivalent for the Nix language. `statix` and `deadnix` are lint and
dead-code tools, not security tools. So read the modules and check, by hand:

- Any service bound to `0.0.0.0` that should be on `127.0.0.1`. Firewall rules are the only thing
  standing in front of it, and they are one edit from not being.
- `openFirewall = true` anywhere it is not deliberate, and every port in `allowedTCPPorts`.
- Secrets reaching the **world-readable `/nix/store`** at build time instead of being decrypted
  at runtime through agenix. This is the classic Nix footgun and it leaks to every user on the
  box.
- `systemd-analyze security <unit> --json=pretty` per unit for the hardening it is missing.

Also check, because no tool concludes it for you: whether the origin IP is reachable directly
past Cloudflare (`curl --resolve <host>:443:<ip>`), whether crt.sh or historical DNS publishes
it, and whether the Caddy admin API on `:2019` is bound anywhere but loopback.

## 4. Roblox: the scanners find nothing relevant

`selene --display-style=json src/` and `luau-analyze` find **correctness** bugs — nil access,
shadowing, type errors. They find no security bugs at all. Reporting them as a security pass
would be a lie; run them, and label them lint.

The actual exploit classes are all manual review. For every one, the only real defence is
server-side:

1. **Every remote is an attacker-controlled entry point.** An exploiter calls any
   RemoteEvent/RemoteFunction with any arguments at any rate. Inventory them all, then check each
   handler validates type, range and game state in that order before acting. Client-side checks
   are cosmetic.
2. **Client-trusted values.** Any handler reading damage, currency, score or speed *from the
   client* instead of computing it server-side.
3. **`ProcessReceipt` idempotency.** Grant once per `PurchaseId`, persisted. Without a ledger, a
   disconnect mid-purchase grants twice.
4. **Economy and duplication.** Tool reparenting, trade races, DataStore write races.
5. **Rate limiting on the server**, per player per remote, with rejections logged.

**Never use a script executor to test this, and never suggest he does.** Roblox treats it as
exploiting and bans for it, including when the stated reason is testing your own game. Simulate a
malicious client from Studio's command bar or a LocalScript you wrote.

## 5. The report

Write `docs/security-audit-<YYYY-MM-DD>.md`:

1. **What ran and what did not** — tool, version, and for anything missing, why.
2. **Findings**, highest severity first: tool, `path:line`, one sentence on what an attacker does
   with it, and a verdict of **real**, **accepted** (with the reason) or **false positive** (with
   the reason). An untriaged dump is not an audit — scanners are noisy and a list nobody triaged
   gets ignored wholesale.
3. **Manual findings**, which is where the Nix and Roblox items land.
4. **Not covered** — cross-file taint, Svelte templates if ESLint did not run, object-storage
   ACLs, anything the blast-radius rule kept you away from.

Rotations and deploys go to `my_todos` with `why_yours`; everything you can fix becomes a
`claude_todo`. Never write a verdict like "the project is secure" — report what was checked.
