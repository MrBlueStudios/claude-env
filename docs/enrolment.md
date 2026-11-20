# Enrolment: adding and removing a Blitsol-tier friend

Every command says which directory to run it in. The examples use `ryan`; substitute the
person's short name, lowercase and no spaces, because it becomes a Nix identifier.

This covers the shared Blitsol secrets only. The rest of the environment needs no enrolment at
all: a friend adds the flake, sets `claude-env.tier`, and gets the same tools everyone else has.
That part is [the guide](./guide.md).

## What the tier actually gets them

Three different mechanisms, and only the first one is what this document is about:

| Thing | How it reaches them | Who grants it |
|---|---|---|
| Shared Blitsol secrets (`/run/agenix/*`) | `blitsol-secrets`, re-keyed to their host key | this runbook |
| claude.ai connectors (HubSpot, Stripe) | an invite to the real account, which they then connect with their own login | Léon, in each billing account |
| Everything else — servers, skills, hooks, guard | `claude-env.tier = "blitsol"` in their own config | nobody; it is just a build |

A secret is never copied to anyone. The ciphertext is public — it lives in a git repo — and what
enrolment changes is who holds a key that opens it.

## Before the first enrolment

The `blitsol-secrets` repo does not exist yet (`q-secrets-repo` chose it; `mt-collect-keys` is
collecting the keys). Until it does, the secrets live in `/etc/nixos/secrets/` with Léon's keys as
the only recipients, and nothing below can be run.

**Run in: `~/Projects`**

```bash
gh repo create MrBlueStudios/blitsol-secrets --private --clone
cp /etc/nixos/secrets/secrets.nix blitsol-secrets/
```

Then trim that copy to the Blitsol-shaped secrets, leaving the host-shaped ones
(`borg-passphrase`, `caldav-google`, `tailscale-authkey`, everything `smac-*`) where they are.
The split is its own test: a secret only Léon's laptop ever needs is not a crew secret, and
putting it in a repo three other people can clone makes it one for no reason.

Expect the copy to list more than you can move. `/etc/nixos/secrets/secrets.nix` declares
sixteen secrets and four `.age` files exist, so most of those names are waiting for a value
rather than holding one. `firecrawl-api-key.age` is one of them — the firecrawl MCP module is
written against that path and its wrapper says so at startup — and creating it is
`agenix -e firecrawl-api-key.age -i ~/.ssh/id_ed25519`, run in the secrets directory.

> The repo is private, and that matters less than it looks: age ciphertext is safe to publish, so
> the privacy is defence in depth. What must never be in it is a decrypted file. Add
> `*.age.tmp`, `*.decrypted` and `/plain/` to `.gitignore` before the first commit.

## Adding a friend

### 1. Get the right public key from them

Two keys, and which one you need depends on what they will do:

| They will… | Key you need | Where it is |
|---|---|---|
| …have secrets appear on their laptop at activation (everyone) | the **host** key | `/etc/ssh/ssh_host_ed25519_key.pub` |
| …also edit or add secrets (Léon, and whoever deputises) | their **personal** key | `~/.ssh/id_ed25519.pub` |

**They run in: anywhere on their own laptop**

```bash
cat /etc/ssh/ssh_host_ed25519_key.pub
```

If that file does not exist, their NixOS has not generated a host key yet, which means
`services.openssh` has never been enabled. They generate one:

**They run in: anywhere on their own laptop**

```bash
sudo ssh-keygen -t ed25519 -f /etc/ssh/ssh_host_ed25519_key -N ""
```

Paste the whole `ssh-ed25519 AAAA… root@hostname` line into chat. It is a public key; it is
meant to be shared, and asking for it over chat is correct.

> **Use the raw `ssh-ed25519` line. Do not convert it with `ssh-to-age`.** agenix decrypts on the
> target machine with `age -i /etc/ssh/ssh_host_ed25519_key`, which only opens `ssh-ed25519`
> stanzas. An `age1…` recipient derived from the same key cannot be opened that way, and the
> failure arrives as `no identity matched any of the recipients` during their activation, which
> reads like a corrupt secret and is not. `/etc/nixos/secrets/secrets.nix` says the same thing at
> the top, for the same reason: it has already cost someone an evening.

### 2. Add them as a recipient

**Run in: `~/Projects/blitsol-secrets`**

Edit `secrets.nix`. Add one `let` binding and one entry in the list:

```nix
  # Ryan's laptop. Host key, so secrets decrypt during his activation.
  ryan = "ssh-ed25519 AAAAC3Nza… root@ryan-laptop";

  allKeys = [
    mr-blue
    leon-new
    leon-new-ssh
    ryan          # ← added 2026-11-20
  ];
```

Keep the comment with the date. The list is the access-control list, and six months from now the
only question anyone asks of it is "who is this and when did they get in".

### 3. Re-key every secret

Adding a recipient does nothing until each file is re-encrypted to the new set.

**Run in: `~/Projects/blitsol-secrets`**

```bash
agenix -r -i ~/.ssh/id_ed25519
```

`-r` rekeys every `.age` file against the recipients in `./secrets.nix` — agenix reads that path
by default and takes `RULES` as an override, so run it from the directory holding both. It has to
decrypt each file first, which means it only works on a machine that is already a recipient:
Léon's. `no identity matched any of the recipients` means the `-i` path is wrong, not that the
file is damaged.

Verify before committing. The check that matters needs no decryption at all: an age file names
its recipients in the header, one `-> ` stanza each, so the count must equal the length of
`allKeys`.

**Run in: `~/Projects/blitsol-secrets`**

```bash
for f in *.age; do printf '%-32s %s recipients\n' "$f" "$(grep -ac '^-> ' "$f")"; done
```

`-a` is not optional: an age file is binary, and plain `grep -c` prints nothing at all on one
rather than a count, which looks like every file having zero recipients.

Before the add, every file in `/etc/nixos/secrets` reads `3`. After adding one person, every
file must read `4` — *every* file. One file left at `3` is a half-finished rekey, and it is the
file that person cannot open; one file at `5` means a key is in there twice.

### 4. Commit and push

**Run in: `~/Projects/blitsol-secrets`**

```bash
jj describe -m "feat(secrets): add ryan's host key as a recipient"
jj bookmark set main -r @
jj git push --bookmark main
```

### 5. They point their config at it

**They run in: their own nix-config (`/etc/nixos` on a NixOS laptop)**

Add the input and the secret they need:

```nix
# flake.nix
inputs.blitsol-secrets = {
  url = "git+ssh://git@github.com/MrBlueStudios/blitsol-secrets?ref=main";
  flake = false;
};
```

```nix
# the host module
age.secrets.firecrawl-api-key.file = "${inputs.blitsol-secrets}/firecrawl-api-key.age";
claude-env.tier = "blitsol";
claude-env.mcp.modules.firecrawl = true;
```

They need read access to the private repo, which is a GitHub collaborator invite, not a key.

**They run in: `/etc/nixos`**

```bash
nh os switch .
```

### 6. Confirm it worked, on their machine

**They run in: anywhere on their own laptop**

```bash
sudo test -r /run/agenix/firecrawl-api-key && echo "decrypted: ok"
claude mcp list
```

(Substitute whichever secret they were actually enrolled for — the point is a file under
`/run/agenix` that exists and is readable by the user or service that needs it.)

The first line proves the key reached the machine. The second proves the environment picked it
up: `firecrawl` should appear and connect. If the file is there and the server still fails, the
key itself is wrong or expired — that is a Firecrawl account problem, not an enrolment one.

## Removing a friend

Four steps, and the fourth is the one that is actually security rather than bookkeeping.

### 1. Remove the recipient and re-key

**Run in: `~/Projects/blitsol-secrets`**

Delete their `let` binding and their line in `allKeys`, then:

```bash
agenix -r -i ~/.ssh/id_ed25519
for f in *.age; do printf '%-32s %s recipients\n' "$f" "$(grep -ac '^-> ' "$f")"; done
```

Every file must read one fewer than before, and they must all agree.

### 2. Push, and take their repo access away

**Run in: `~/Projects/blitsol-secrets`**

```bash
jj describe -m "chore(secrets): remove ryan as a recipient"
jj bookmark set main -r @
jj git push --bookmark main
gh api -X DELETE repos/MrBlueStudios/blitsol-secrets/collaborators/<their-github-handle>
```

### 3. Remove the account invites

The connectors are not in any repo. Remove them as a user in HubSpot, Stripe, Cloudflare and
AdministratieX, in each account's own settings. Nothing in Nix can do this and nothing in Nix
will warn you that you forgot.

### 4. Rotate the secret values

**Re-keying does not un-leak anything.** They had the plaintext, and they may still have an old
clone of the repo whose ciphertext their key still opens. Until each value is changed at its
source, they still have it.

**Run in: `~/Projects/blitsol-secrets`**

```bash
agenix -e firecrawl-api-key.age -i ~/.ssh/id_ed25519
```

Paste a newly issued value — issued in the provider's console, not edited by hand. Then push, and
have everyone still on the tier switch so they pick up the new ciphertext.

Rotate in this order, worst first: anything that can spend money, then anything that can read
customer data, then the rest. For the current set that is Cloudflare and Stripe (both per-person
OAuth, so revoking their account access is the rotation), then `firecrawl-api-key`, then the
remainder.

## What to check once a quarter

**Run in: `~/Projects/blitsol-secrets`**

```bash
# every secret has the same recipients: a file left behind by a half-finished rekey
# is how someone keeps access nobody meant them to have
for f in *.age; do printf '%s %s\n' "$f" "$(grep -ac '^-> ' "$f")"; done | awk '{print $2}' | sort -u
# one line of output means they agree; two or more names the inconsistency to chase

# every declared secret exists, and every existing secret is declared
nix eval --impure --expr 'builtins.attrNames (import ./secrets.nix)' --json | jq -r '.[]' | sort > /tmp/declared
ls *.age | sort > /tmp/present
diff /tmp/declared /tmp/present || echo "declared and present differ — see above"
```

The second check is not hypothetical: `/etc/nixos/secrets/secrets.nix` declares sixteen secrets
and five of them exist. Eleven are names waiting for a value, which is fine as long as everyone
knows that is what they are, and misleading the moment someone reads the file as an inventory.
