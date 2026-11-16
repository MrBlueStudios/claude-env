# agenix-multi-recipient

**Question:** How do we add and remove recipients on shared agenix secrets, what does removal actually protect, and what breaks with bad keys or mixed key types?

**Answer:** Adding a recipient is one edit to the rules file plus `agenix -r`, run by anyone holding a private key that is in the *current* ciphertext's recipient list; every listed `.age` file is decrypted and re-encrypted, there is no per-file shortcut. Removing a recipient the same way only stops them opening *future* ciphertext; anyone who pulled the repo before can decrypt the old files forever, so a departure means rotating the secret values at the provider. Bad keys fail loudly before anything is written, but a rekey that fails mid-list leaves earlier files re-keyed and later files not, so the runbook must check the exit code.

**Confidence:** high — every claim below was reproduced in a throwaway repo with agenix 0.15.0 and age 1.2.1, the exact versions on Léon's machine.

**What would change our decision:**
- Wanting per-person revocation *without* rotating the secrets. No file-based scheme can do that; it would need a server that checks identity on every read (a self-hosted Vaultwarden, or the providers' own team features), which is a different design.
- Friends keeping their SSH private key behind a passphrase or hardware token. age prompts for the passphrase; hardware keys need `age-plugin-*`. Neither was tested here.

## Findings

All commands below were run in a scratch repo with five freshly generated ed25519 keys (`leon`, `ryan`, `kish`, `almar`, `host5`) and two secrets, `EDITOR="cp /dev/stdin"` so `agenix -e` reads stdin.

1. **Adding a fifth recipient.** Append the public key to the rules file and the recipient list, then `agenix -r -i <your private key>`. Output is one `rekeying <file>...` line per file in the rules; afterwards the ciphertext carries one `-> ssh-ed25519` stanza per recipient (2 → 3 in the test) and the new key decrypts every file. A file that is listed in the rules but does not exist yet is skipped with `<file> wasn't created.` and the rest continue. What the maintainer needs locally: the repo checkout, the `agenix` CLI (from the flake), and a private key that can open the *existing* files. Source: local test; [agenix README, "Rekeying"](https://github.com/ryantm/agenix#rekeying).

2. **Who may rekey is decided by the old ciphertext, not the new rules.** After removing `almar` from the rules, `agenix -r -i almar` still succeeded, because the files on disk were still encrypted to him. Conversely, a key that is in the new list but not the old one (a brand-new maintainer) gets `age: error: no identity matched any of the recipients` on the first file. Consequences: any current recipient can add a sixth; the real access control on the secrets repo is git (make it private, protect `main`, require a review on changes to the rules file). Source: local test.

3. **Removal does not revoke.** With `almar` removed and the files re-keyed, his key fails on the new files (`no identity matched any of the recipients`) but still decrypts the copy of the old ciphertext he pulled earlier, and git history keeps every old version anyway. Rewriting history is pointless — he already has it. Removing a person therefore means: edit rules, `agenix -r`, **then rotate every value he could read** (HubSpot private-app token, Stripe restricted key, Cloudflare API token, Moneybird token, …) and `agenix -e` each one with the new value. Source: local test; [Nix-Book, agenix key rotation](https://ekala-project.github.io/nix-book/ch10-08-secrets-management.html).

4. **A failed rekey is partial.** With three files where the second was encrypted only to `ryan`, `agenix -r -i leon` re-keyed the first (2 → 3 stanzas), errored on the second, and left the third untouched (still 2 stanzas), exit 1. The CLI stops at the first failure and does not roll back. Rules for the runbook: the maintainer key must be a recipient of every file in the rules (keep per-person files in a separate rules file), and always check the exit code and `git diff --stat` before committing. Source: local test.

5. **Malformed keys fail before anything is written.** A truncated base64 body and a key with a line break inside both produce
   `age: error: malformed SSH recipient: "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA ryan@lab": ssh: no key found`
   on the first file, and both existing files were unchanged and still decryptable afterwards (same byte size, same plaintext). The quoted recipient in the error shows exactly where the key got cut, which is the fast way to spot a key that was pasted through a chat client. Source: local test.

6. **User keys, host keys and `age1` keys can all be recipients of one file.** A file encrypted to four user keys plus a host key (`host5`) and an `age1` X25519 recipient decrypts with any of them (`-i <ssh private key>` or `-i keys.txt`). The NixOS module decrypts with `age.identityPaths`, default `/etc/ssh/ssh_host_ed25519_key` and `ssh_host_rsa_key`; the home-manager module (`agenix.homeManagerModules.default`) defaults to `~/.ssh/id_ed25519` and `~/.ssh/id_rsa`; the CLI tries the same two user keys unless `-i` is given. Source: local test; `modules/age.nix` line 241 and `modules/age-home.nix` line 180 of the agenix revision locked in `/etc/nixos`.

7. **The `ssh-to-age` trap is real.** A recipient written as the `age1…` conversion of an SSH public key *cannot* be opened by that SSH private key: `agenix -d … -i ryan` → `no identity matched any of the recipients`. Always paste the raw `ssh-ed25519 AAAA… comment` line into the rules file. Léon's own `secrets.nix` already documents this trap; this confirms it. Source: local test.

8. **Which module to use for Blitsol credentials.** The crew's shared secrets are used by Claude Code and CLI tools running as the user, not by system services, so the home-manager agenix module fits: it decrypts with the user's own `~/.ssh/id_ed25519` — exactly the key each friend sent — at `home-manager switch` time, and nothing needs their host keys. The NixOS module would require collecting four *host* keys as well. Source: finding 6; design input for `secrets-delivery`.

9. **Rules-file naming is changing upstream.** The pinned CLI (0.15.0) reads `./secrets.nix` through `RULES` with no warning. The current README says newer versions look for `agenix-rules.nix` and `AGENIX_RULES`, still accept the old names with a deprecation warning, and will drop them later. Name the file `agenix-rules.nix` in the new repo so the next agenix bump is a no-op. Source: [agenix README](https://github.com/ryantm/agenix) — UNVERIFIED on a newer binary; 0.15.0 behaviour verified locally.

## Not checked

- Passphrase-protected or hardware-backed (YubiKey, `age-plugin-yubikey`) identities.
- `agenix-rekey`, a separate project that automates re-keying with a master key; not needed at four files and four people.
- sops-nix as an alternative. The recipient semantics (file-based, no revocation) are identical, so the conclusion would not change.
- Behaviour when two maintainers rekey concurrently; git merge conflicts on binary `.age` files resolve by re-running `agenix -r` on the merged rules.
