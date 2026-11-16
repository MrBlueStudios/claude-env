# nixos-version-matrix

**Question:** Can one shared flake serve a home-manager module and a NixOS module to machines on NixOS 25.05 and 26.05, and what does it cost Léon to move to 26.05?

**Answer:** Yes, and it was tested rather than read: Léon's actual Claude home-manager module and the guard NixOS module were evaluated against both releases. The NixOS module passes on both unchanged; the home-manager module passes on 25.05 and fails on 26.05 on exactly one line (`pkgs.nodePackages.prettier`, removed in nixpkgs 26.05), and the fix must be release-guarded because `pkgs.prettier` does not exist on 25.05. The shared flake should expose modules only and never pin home-manager; Léon's own upgrade is a branch bump for three inputs plus two package-attribute fixes, with `stateVersion` left alone — and it is overdue, because the 25.05 branch he is on stopped receiving updates at the end of 2025.

**Confidence:** high for module compatibility (evaluated, not inferred); medium for the upgrade cost (only the Claude modules were evaluated on 26.05, not the whole system).

**What would change our decision:**
- A full-system evaluation of `/etc/nixos` on 26.05 (command in finding 9) showing breakage in stylix, nixvim or the AGS widgets beyond a branch bump. Then Léon stays on 25.05 a little longer and the flake simply keeps supporting both, which it must anyway.
- Ryan or Kish moving to nixos-unstable. Then the guard becomes "25.05 or newer", not "25.05 or 26.05".

## Findings

1. **The Claude home-manager module evaluates on home-manager 26.05 after one fix.** Scratch flakes were built with only `nixpkgs` and `home-manager` as inputs, one per release, importing a copy of `/etc/nixos/modules/home/claude` into `homeManagerConfiguration` and evaluating `activationPackage.drvPath`. Results (2026-11-16, nixpkgs 25.05 rev `ac62194`, 26.05 rev `f1e5c35`):

   | release | result |
   |---|---|
   | 25.05 | evaluates |
   | 26.05 | `error: nodePackages has been removed. Many packages are now available at the top level (e.g. pkgs.package-name)` |
   | 26.05 with `pkgs.prettier` | evaluates, plus one deprecation warning (finding 3) |

   The offending line is `hooks.nix:30`, the prettier format hook. Source: local evaluation; scratch flakes under the session scratchpad `hm-matrix/`.

2. **The fix needs a guard, because the two releases disagree on the attribute name.** On 25.05 `pkgs.prettier` does not exist ("Did you mean prettierd?"); on 26.05 `pkgs.nodePackages` throws on access. `pkgs.prettier or pkgs.nodePackages.prettier` works on both: the `or` only touches `nodePackages` when `prettier` is missing. Source: local evaluation on both scratch flakes.

3. **Second attribute to guard: `nixfmt-rfc-style`.** 26.05 warns `nixfmt-rfc-style is now the same as pkgs.nixfmt which should be used instead` (from `hooks.nix:40`). On 25.05 `pkgs.nixfmt` is the *old* Haskell formatter (0.6.0) and `nixfmt-rfc-style` is the new one (1.1.0); on 26.05 both are 1.5.0. So `pkgs.nixfmt` is wrong on 25.05 and `pkgs.nixfmt-rfc-style` only warns on 26.05. Keep `nixfmt-rfc-style` until 25.05 is dropped, or guard on `lib.versionAtLeast lib.version "25.11"`. Source: `nix eval …nixfmt.version` on both scratch flakes.

4. **The guard NixOS module evaluates unchanged on both releases.** `claude-code-policy.nix` was evaluated in a minimal `nixosSystem` (one filesystem, no bootloader) on nixpkgs 25.05 and 26.05; both produce a toplevel derivation with no warnings. The module only uses `pkgs.writeShellApplication` and reads `guard.sh` by relative path, so it has nothing to break on. Source: local evaluation, `hm-matrix/sys-*`.

5. **A modules-only shared flake never triggers home-manager's release check.** The check lives in the consumer's home-manager, comparing its own release with the nixpkgs used for `lib` and for `pkgs`. It is a *warning*, not an error, printed at build time, and the exact text is:

   > You are using
   >   Home Manager version: X
   >   Nixpkgs version used to evaluate Home Manager: Y
   >   Nixpkgs version used for packages (`pkgs`): Z
   > Using mismatched versions is likely to cause errors and unexpected behavior. … If you insist then you can disable this warning by adding `home.enableNixpkgsReleaseCheck = false;` to your configuration.

   A flake that exports `homeManagerModules.default = ./modules/home` and `nixosModules.default = ./modules/system` carries no nixpkgs or home-manager input at all; each friend's own flake supplies both, so the versions always match their system. Source: [home-environment.nix, release-26.05](https://github.com/nix-community/home-manager/blob/release-26.05/modules/home-environment.nix) lines 549–615; [Discourse thread with the warning in the wild](https://discourse.nixos.org/t/nixpkgs-and-home-manager-version-mismatch-warning/68485).

6. **One real portability gap found on the way: the module expects a module argument `inputs`.** The 25.05 evaluation first failed with `attribute 'inputs' missing`, because `skills.nix:138` reads `inputs.claude-web-stack` (supplied in `/etc/nixos` through `extraSpecialArgs`). For the shared flake this means either `claude-web-stack` becomes an input of `claude-env` and is passed in with `_module.args`, or the playbook is vendored. Consumers must not be required to set `extraSpecialArgs`. Source: local evaluation.

7. **No option the Claude module uses was renamed or removed in 25.11 or 26.05.** The home-manager 26.05 notes list, among others, `programs.ssh.matchBlocks` → `programs.ssh.settings`, `services.syncthing.passwordFile` removed, `programs.neovim.extraLuaConfig` → `initLua`, `services.swww` → `services.awww`, `programs.firefox.extensions` removed, `programs.man` split. `rg` over the module finds none of them. The `home.stateVersion`-gated defaults (zsh `dotDir`, `xdg.userDirs.setSessionVariables`, Hyprland `configType`, Neovim `withPython3`) only apply when a user *raises* their stateVersion; Léon's is `24.11` and should stay there. Source: [Home Manager 26.05 release notes](https://home-manager.dev/manual/26.05/release-notes.xhtml), read through a summariser — option names quoted from it, UNVERIFIED against the raw page.

8. **NixOS 26.05 changes that touch Léon's machine.** (a) Stage 1 is now systemd-based by default; the scripted initrd is deprecated and goes away in 26.11, so trying `boot.initrd.systemd.enable = false` is only a fallback. (b) The Bash `nixos-rebuild` is gone; the Python one has been the default since 25.05 and Léon sets no `system.rebuild.enableNg`, so nothing to do. (c) `fileSystems.<name>.fsType` no longer defaults; both of his `hardware-configuration.nix` files already set `ext4`. Source: [NixOS release notes](https://nixos.org/manual/nixos/stable/release-notes) (summarised, UNVERIFIED wording); `rg` over `/etc/nixos`.

9. **Léon's upgrade is three branch bumps.** Inputs tracking a release branch: `nixpkgs` (nixos-25.05), `home-manager` (release-25.05), `stylix` (release-25.05). `nixvim` already follows `nixpkgs-unstable`; `agenix`, `ags`, `astal`, `nix-colors`, `llm-agents` are pinned by tag or rev and independent. NixOS has no "one release at a time" rule, so 25.05 → 26.05 in one step is normal. Dry run before touching anything, from `/etc/nixos`:

   ```
   nix build .#nixosConfigurations.mr-blue.config.system.build.toplevel --dry-run \
     --override-input nixpkgs github:NixOS/nixpkgs/nixos-26.05 \
     --override-input home-manager github:nix-community/home-manager/release-26.05 \
     --override-input stylix github:nix-community/stylix/release-26.05
   ```
   Source: `/etc/nixos/flake.nix`; [NixOS upgrade procedure](https://nixos.org/manual/nixos/stable/#sec-upgrading).

10. **25.05 is end-of-life.** NixOS releases are supported for about seven months; 25.05 reached end of life on 2025-12-31 and Léon's lock is at `nixos-25.05` rev dated 2025-12-29, so the laptop has had no nixpkgs security updates for roughly ten months. Ryan and Kish on 26.05 are covered until 2026-12-31, when 26.11 will already be out. This moves the upgrade from "nice" to "soon". Source: [NixOS release schedule](https://nixos.org/manual/nixos/stable/release-notes) and the home-manager README's "26.05 support ends 2026-12-31" — exact dates UNVERIFIED, inferred from the release cadence; the lock date is from `nix flake metadata /etc/nixos`.

## Not checked

- Léon's full system on 26.05 (stylix, nixvim, AGS/Astal, Zenbook scripts). The dry run in finding 9 answers that in a few minutes and should be the first step of the upgrade, not of this research.
- Ryan's and Kish's actual configurations — only Léon's modules were tested.
- 25.11 as an intermediate stop; there is no reason to stop there.
- Whether a `home.stateVersion` bump is worth doing later. It is not required for the upgrade.
