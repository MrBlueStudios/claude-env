# roblox-on-nvidia-kde

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Léon's module, which Kish could not see:** Vinegar is the native `pkgs.vinegar` 1.9.3 installed system-wide in `modules/system/roblox.nix` (not the Flatpak, which is kept only as a fallback and whose login is unusable), `programs.nix-ld.enable = true` is already set, the Studio prefix is `~/.local/share/vinegar`, and the module does not write Vinegar's `config.toml`, so a per-machine `[studio] gpu` entry would not be overwritten. Window placement is handled in `modules/home/hyprland.nix`, which is desktop-specific and must not travel; on a single-screen KDE laptop it is unnecessary. `roblox-wine` is a flake-level package used only by the StudioMCP wrapper.
>
> **What this changes:** the pre-flight checklist stands; items 1–4 belong in the Legion's host config, not the shared module, and the Roblox module ships as opt-in with a `gpuIndex` option. Who runs the checklist is now Ryan or Almar, whichever owns the Legion (the inventory says Almar).

---

*Owner: Ryan (guessed from the handle — reassign if wrong) · researched 16 Nov 2026 · web research only; nothing was run on the Legion.*

**Question:** Will a home-manager module that runs Roblox Studio through Vinegar, built on Intel graphics under Hyprland, work on a Lenovo Legion with an RTX 2060 Mobile under KDE Plasma 6 Wayland on NixOS 26.05?

**Answer:** Probably yes, but not untouched: the driver side is straightforward (the RTX 2060 is supported by NVIDIA's open kernel module and by PRIME offload), while the likely trouble is Vinegar picking the integrated GPU on a hybrid laptop and a handful of open Studio-under-Wine bugs on KDE. Studio runs through XWayland by default, and 16 GB of RAM is twice Roblox's recommended figure. The module needs two things it did not need on Léon's machine: a per-machine GPU setting, and a check that Vinegar's bundled Wine can run on NixOS.

**Confidence:** medium-low — driver facts are from the NixOS wiki and Vinegar's own docs, but the KDE-specific problems are from open issue reports, the nixpkgs packaging was not inspected, and two of the four questions (download size, caching) have no sourced answer.

**What would change our decision:**
- If Vinegar on the Legion cannot be made to use the NVIDIA card (finding 3), Studio still runs on the integrated GPU with limited video memory — usable for scripting, poor for large places. That may be acceptable for an opt-in module.
- If the open KDE file-picker bug (finding 5) is still present, exporting and importing models from Studio is unreliable on Plasma, and the module should say so.

## Findings

1. **NVIDIA driver: use the open kernel module.** Since driver version 560, NixOS requires an explicit choice via `hardware.nvidia.open`. The wiki says the open modules are preferred and support Turing or newer — RTX 20 series onwards — so the RTX 2060 qualifies; set it to `true`. Minimum configuration per the wiki: `hardware.graphics.enable = true`, `services.xserver.videoDrivers = [ "nvidia" ]`, `hardware.nvidia.open = true`. This is system-level NixOS configuration, so it belongs in the flake's NixOS module or the Legion's host config, not the home-manager module. [NixOS wiki: NVIDIA](https://wiki.nixos.org/wiki/NVIDIA) · [same, on which GPUs](https://wiki.nixos.org/wiki/Nvidia)

2. **Hybrid graphics: PRIME offload is supported on this hardware.** Offload mode needs an NVIDIA GPU of the Turing generation or newer and an Intel CPU from Coffee Lake onwards or an AMD Ryzen. It requires the two PCI bus IDs (found with `lspci`) under `hardware.nvidia.prime`, and `offload.enableOffloadCmd = true` generates an `nvidia-offload` wrapper that sets the right environment variables. One thing to respect: reverse sync is not compatible with the open module. Whether this Legion has a BIOS switch for discrete-only graphics, which would sidestep offload entirely: UNVERIFIED. [NixOS wiki: NVIDIA](https://wiki.nixos.org/wiki/NVIDIA) · [reverse-sync note](https://wiki.nixos.org/w/index.php?diff=5663)

3. **Vinegar chooses the GPU itself — and may choose wrong.** Vinegar's debug log shows it enumerating the cards, picking one by index, and setting the offload variables on its own. In an open August 2026 issue (from a NixOS user) Studio kept initialising on the integrated GPU, capping the video memory it believed it had at about 2 GB. The reported fix is a config entry:

   ```toml
   [studio]
   gpu = "0"
   ```

   where the number is an index into Vinegar's GPU list — machine-specific, so it cannot be hard-coded in a shared module. One participant said it still did not work for them. Older Vinegar versions used names like `prime-discrete` instead of an index. The module should expose this as an option and the Legion should set it after reading the debug log. [Vinegar issue #954](https://github.com/vinegarhq/vinegar/issues/954) · [older config syntax](https://github.com/vinegarhq/vinegar/issues/461)

4. **Wayland: Studio uses XWayland, and that is the supported path.** Vinegar's troubleshooting page lists "using Wine's Wayland driver" as discouraged, and describes a cursor-lock problem that exists because Xwayland only locks the cursor when it is hidden — fixed by Vinegar's own Wine build ("Kombucha"), which it uses automatically. So: yes, Studio needs XWayland; Plasma provides it. The Vinegar maintainer has said most Wayland rough edges come from Wine rather than Vinegar. [Vinegar troubleshooting (official)](https://vinegarhq.org/Vinegar/Troubleshooting.html) · [maintainer comment](https://github.com/vinegarhq/vinegar/issues/778)

5. **Known issues on KDE specifically.**
   - **Studio is killed after 10 seconds when a file picker is left open** — reported July 2026 on KDE Plasma under both Wayland and X11, with a second user confirming on another KDE distribution. This hits model import and export. Status at time of reading: open. [Vinegar issue #927](https://github.com/vinegarhq/vinegar/issues/927)
   - **Undocked panels do not re-dock** — a developer-forum thread reports this on Fedora KDE Wayland, under Vinegar and plain Wine alike. An annoyance, not a blocker. [Roblox developer forum](https://devforum.roblox.com/t/how-to-run-roblox-studio-on-linux-with-bottles/4763691)
   - **A Vulkan-related crash on Wayland** and several "Studio crashes opening places" reports appear in the open issue list for September–November 2026; I read only the titles. [Vinegar issue list](https://github.com/vinegarhq/vinegar/issues)
   - **An older "Studio not opening on KDE Wayland" report** from 2024 is closed. [issue #448](https://github.com/vinegarhq/vinegar/issues/448)
   - **The hybrid-graphics failure in Vinegar's docs applies only to the Flatpak** with NVIDIA drivers; a native install avoids it. If Léon's module uses the nixpkgs package rather than Flatpak, this one does not apply. [Vinegar troubleshooting (official)](https://vinegarhq.org/Vinegar/Troubleshooting.html)

6. **NixOS-specific: Vinegar's bundled Wine and nix-ld.** A nixpkgs issue from late October 2026 (on unstable) shows Vinegar refusing to start with the message that NixOS cannot run dynamically linked executables intended for generic Linux, pointing at nix-ld; the failing piece was Vinegar's own downloaded Wine. The reporter later closed it as a local glitch fixed by clearing configs, with no maintainer analysis. Whether the 26.05 package wraps this properly, and whether Léon's module already enables `programs.nix-ld` or supplies a Nix-built Wine: UNVERIFIED — check the module. [nixpkgs issue #577947](https://github.com/NixOS/nixpkgs/issues/577947)

7. **16 GB RAM is enough on paper.** Roblox's own setup page lists 3 GB minimum and 8 GB recommended for Studio. Claude Code and a browser fit in the other half for ordinary projects. Two cautions: the Vinegar maintainer acknowledges memory leaks with Studio under Wine, and one open issue describes crashes when reopening intensive projects. Expect to restart Studio during long sessions. The 6 GB of video memory on the 2060 is not a constraint once Studio actually uses that card. [Roblox Studio setup (official)](https://create.roblox.com/docs/studio/setup) · [maintainer on leaks](https://github.com/vinegarhq/vinegar/issues/778)

8. **First-launch download size: not found.** UNVERIFIED. No source gave a figure for Studio's download or for Vinegar's Wine build.

9. **Is the download cached across rebuilds? Almost certainly yes — because it is not in the Nix store.** Vinegar's logs show Studio installed under its own data directory in a per-version folder (`…/vinegar/versions/version-<hash>/`), with the Wine build and prefix alongside. For a native install that is under the user's home directory, which `nixos-rebuild` does not touch. The flip side: the Roblox toolchain is only partly reproducible — Studio itself and Vinegar's Wine are fetched at run time, and Studio updates itself on Roblox's schedule regardless of the flake's pin. The exact path for a non-Flatpak install is inferred from Flatpak logs: UNVERIFIED. [log excerpt showing paths](https://github.com/vinegarhq/vinegar/issues/927)

10. **The command-line tools are not the risk.** rojo, selene, stylua and luau-lsp are ordinary native programs with no dependence on GPU or desktop. Nothing found suggests they behave differently on this machine. (Not separately researched.)

## Pre-flight checklist

Run in order on the Legion; stop at the first failure.

| # | Check | Pass looks like |
|---|---|---|
| 1 | `lspci \| grep -Ei 'vga\|3d'` | Two entries: an integrated GPU and the RTX 2060. Note both bus IDs. |
| 2 | Host config has `hardware.graphics.enable`, `videoDrivers = [ "nvidia" ]`, `hardware.nvidia.open = true`, and `prime.offload` with the bus IDs | Rebuild succeeds. |
| 3 | `nvidia-smi` | Lists the RTX 2060 and a driver version. |
| 4 | `nvidia-offload vulkaninfo --summary` | Shows the NVIDIA device. |
| 5 | Does the module install Vinegar from nixpkgs (not Flatpak)? | Yes. If Flatpak, expect the hybrid-graphics problem in finding 5. |
| 6 | Launch Vinegar once from a terminal | No "cannot run dynamically linked executables" message. If there is one, enable `programs.nix-ld` or see how Léon's machine handles Wine. |
| 7 | Read Vinegar's debug log for the "Using GPU index=…" line | The index points at the RTX 2060. If not, set `[studio] gpu = "<index>"` and relaunch. |
| 8 | Open Studio, open a place, move the camera | Renders; cursor stays locked while panning. |
| 9 | Inside Studio, open an import or export file dialog and leave it open for 15 seconds | Studio is still running. If it was killed, the KDE file-picker bug is present — record it as a known limitation. |
| 10 | `rojo serve` in a project and connect from the Studio plugin | Sync works. |
| 11 | With Studio, Claude Code and a browser open for an hour, check memory | Comfortably under 16 GB. If it climbs steadily, plan on restarting Studio. |
| 12 | `nixos-rebuild switch` again, then relaunch Vinegar | Starts without re-downloading Studio. Note the size of Vinegar's data directory — that answers finding 8. |

## Not checked

- **Nothing was run.** Every item on the checklist is untested; items 6, 7 and 9 are the ones I expect to matter.
- **Léon's module** — whether it uses the nixpkgs Vinegar package, how it provides Wine, and whether it writes Vinegar's config file (which would overwrite a per-machine GPU setting).
- **The nixpkgs `vinegar` package in 26.05** — version, and whether it bundles or wraps Wine.
- **The exact Legion model** — CPU vendor, and whether it has a BIOS graphics-mode switch.
- **Download sizes** for Studio and Vinegar's Wine build.
- **32-bit graphics libraries** (`hardware.graphics.enable32Bit`) — commonly enabled for Wine; whether current Studio needs them was not confirmed.
- **Vinegar's configuration reference** was not opened; the `gpu` key is taken from an issue thread, and its accepted values may have changed between versions.
- **Roblox's terms** on running Studio under Wine — Vinegar exists for this and is widely used, but the question was not looked at.
