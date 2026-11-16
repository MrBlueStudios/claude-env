# desktop-neutral-module

> **Reviewed by Claude at Léon's, 16 November 2026.** Kish ran this prompt in Claude web (Fable). Below the line is his write-up, unchanged; the verification that could only be done from Léon's machine is here.
>
> **Checklist run against the real module** (`/etc/nixos/modules/home/claude`): zero hits for `xdg.portal`, `wayland.windowManager`, `hyprctl`, `preferredNotifChannel`, `wl-copy`/`wl-paste`, `$TERMINAL`, `sessionVariables` and `XDG_CURRENT_DESKTOP`. The only `notify-send` call is `${pkgs.libnotify}/bin/notify-send -a "Claude Code" "Claude Code" "Task completed" -i dialog-information` — store path, app name, no urgency flag, no `-A`. It passes checks 1–9 as written.
>
> **The one real gap the checklist could not see from outside:** 35 Kitty-specific references in `modes.nix`, `scripts/claude-mode.sh` and `scripts/cmode.py`. The `claude-mode` layout engine is built on `kitten @` remote control (`launch`, `send-text`) and reads `KITTY_PID`; under Konsole it cannot work. It has to become opt-in in the shared flake, gated on a `modes.enable` option or on `programs.kitty.enable`. This is recorded as a fact and folded into the `desktop-neutral` feature.
>
> **Versions checked in both locked nixpkgs:** `wl-clipboard` 2.2.1 on 25.05, 2.3.0 on 26.05 — so the `ext-data-control` caveat is real on 25.05 only, and the module does not use wl-clipboard anyway. Plasma is 6.3.6 on 25.05 and 6.6.6 on 26.05. The status line uses plain Unicode (`·`, `—`, `⎇`, `│`, `◆`), not Nerd Font glyphs; only `⎇` (U+2387) is at any risk of a missing glyph. Checks 11 and 12 still need a Plasma machine.

---

*Owner: Kish · researched 15–16 Nov 2026 · web research only, nothing was run on a Plasma machine.*

**Question:** Which parts of a home-manager module built on Hyprland + Kitty break or need a guard when installed on KDE Plasma 6 (Wayland), NixOS 26.05?

**Answer:** `notify-send` itself should work on Plasma with no extra configuration; the things that break are the ones that leak Léon's desktop into the module. The one serious risk is any `xdg.portal` or `wayland.windowManager.hyprland` setting on the home-manager side, which hides the KDE portals that NixOS installs. The smaller risks are `wl-copy` (not present by default on KDE, and version-sensitive on KWin), a Kitty-only notification channel in shared settings, and `notify-send` flags that block a hook.

**Confidence:** medium — the portal and clipboard findings rest on issue trackers and docs, and nothing here was tested on real Plasma hardware.

**What would change our decision:**
- If Léon's module does not touch `xdg.portal`, Hyprland options, the clipboard, or `preferredNotifChannel`, almost nothing needs stripping and the checklist below becomes a five-minute grep.
- If NixOS 26.05 ships `wl-clipboard` older than 2.3.0, clipboard *watching* (`wl-paste --watch`) cannot work on Plasma and any tool using it needs a guard or a different mechanism.

## Findings

1. **`notify-send` works on Plasma 6 Wayland without configuration.** It sends to the standard freedesktop notification service, which Plasma's shell provides. A long-running KDE bug thread shows plain `notify-send test` producing popups on Plasma 6.0 through 6.6 under Wayland — the bug is about where the popup appears, not whether it appears. Expect occasional mis-positioned popups. [KDE bug 481736](https://bugs.kde.org/show_bug.cgi?id=481736)

2. **Critical urgency behaves differently on Plasma.** The man page says Plasma ignores `--expire-time` for critical notifications, so `-u critical -t 5000` stays on screen until dismissed. An older KDE report (Plasma 5.18) also says critical notifications show through Do Not Disturb. If hooks use `-u critical` for routine "task finished" messages, Plasma users get sticky popups. [notify-send(1)](https://man.archlinux.org/man/notify-send.1.en) · [KDE bug 423970](https://www.mail-archive.com/kde-bugs-dist@kde.org/msg460655.html) (old; Plasma 6 behaviour UNVERIFIED)

3. **`--action` / `-A` blocks.** The man page states `-A` implies `--wait`, so the command does not return until the user clicks or the notification closes. In a Claude Code hook that means the hook hangs. This is true on any desktop, but combined with finding 2 (critical never expires on Plasma) it can hang indefinitely. [notify-send(1)](https://man.archlinux.org/man/notify-send.1.en)

4. **`notify-send` needs the session D-Bus address.** It works when the hook is launched from a terminal inside the Plasma session (the Claude Code case). It fails from cron or a system-level systemd unit unless `DBUS_SESSION_BUS_ADDRESS` is exported. Relevant only if any hook is ever run by a timer. [LinuxQuestions thread](https://www.linuxquestions.org/questions/slackware-14/kde-plasma-notifications-from-cron-4175692441/) (forum source)

5. **On Plasma the hook is the only notification path.** Claude Code's built-in desktop notifications work out of the box only in Kitty, Ghostty and iTerm2; in other terminals (so: Konsole) the default `auto` channel does nothing. Léon on Kitty gets a built-in notification *plus* the hook; Kish and Ryan on Konsole get only the hook. Also: if the shared settings pin `preferredNotifChannel` to `kitty`, that is wrong for Konsole — leave it at `auto` or unset. [Guide summarising the Claude Code docs](https://contextbolt.com/blog/claude-code-notifications/) — the official page, `code.claude.com/docs/en/terminal-config`, could not be opened from this session, so this is UNVERIFIED against the primary source.

6. **Clipboard: KWin speaks a different protocol from Hyprland.** KWin offers `ext-data-control-v1`; the wlroots `wlr-data-control` protocol was reportedly removed in Plasma 6.5. `wl-clipboard` only learned `ext-data-control` in version 2.3.0 (March 2026); before that, `wl-paste --watch` fails on KDE with a "requires a compositor that supports the data-control protocol" error. [Clipboard manager compatibility write-up](https://clipmer.app/blog/best-clipboard-manager-wayland) · [research note with Plasma version history](https://github.com/aveterosystems/seam/issues/60) · [bug report confirming wl-clipboard 2.3.0 works on KWin](https://github.com/anomalyco/hex/issues/719). Which `wl-clipboard` version NixOS 26.05 ships: UNVERIFIED.

7. **`wl-copy` is not there by default on KDE.** `wl-clipboard` is wlroots-ecosystem tooling and KDE installs don't include it; a script that shells out to `wl-copy` fails silently when it is missing. The module must add `pkgs.wl-clipboard` itself (or call it by store path) rather than assume it. [Bug report describing exactly this failure](https://github.com/airvzxf/telora/issues/189)

8. **Portals are the real trap.** When home-manager sets `xdg.portal.extraPortals`, it points `NIX_XDG_DESKTOP_PORTAL_DIR` at the user profile, which hides every portal NixOS installed system-wide — on a Plasma machine that means `xdg-desktop-portal-kde` disappears and file pickers / screen sharing / open-URI break. The home-manager Hyprland module turns `xdg.portal` on and adds the Hyprland portal by itself, so merely enabling `wayland.windowManager.hyprland` in a shared module triggers this. [home-manager issue #7124](https://github.com/nix-community/home-manager/issues/7124) · [NixOS Discourse: Hyprland HM module breaks portal discovery for other desktops](https://discourse.nixos.org/t/hyprland-home-manager-module-breaks-portal-discovery-for-other-desktop-environments/78042) · [the commit that added it](https://github.com/nix-community/home-manager/commit/5dc1c2e40410f7dabef3ba8bf4fdb3145eae3ceb)

9. **`$TERMINAL` and terminal detection.** UNVERIFIED. I found no authoritative source on whether Plasma sets `$TERMINAL` (my understanding is that it does not, and neither does Hyprland unless the user config does). Treat any script that reads `$TERMINAL`, calls `kitty @ …`, `kitten`, or `hyprctl` as desktop-specific until checked.

10. **Status-line script and CLI tools.** No source suggests these are desktop-dependent; they run inside the terminal. The only plausible difference is fonts (Nerd Font glyphs render as boxes if the Plasma users' Konsole font lacks them). This is inference, not a sourced finding.

## Checklist for the maintainer

Run these against the module source before it ships. Each is a grep plus a decision.

| # | Check | If found |
|---|---|---|
| 1 | `grep -rn "xdg.portal" .` and `grep -rn "wayland.windowManager" .` | Must not be in the shared module. Move to Léon's host config. This is the only item that breaks things outside Claude Code. |
| 2 | `grep -rnE "hyprctl\|hyprland\|HYPRLAND_" .` | Strip, or wrap in `lib.mkIf` on a module option such as `desktop = "hyprland"`. |
| 3 | `grep -rnE "kitty @\|kitten\|xterm-kitty\|KITTY_" .` | Same: guard or strip. |
| 4 | `grep -rn "preferredNotifChannel" .` | Leave unset / `auto`. Never `kitty` in shared settings. |
| 5 | `grep -rn "notify-send" .` → look at flags | No `-A`/`--action`/`--wait` in hooks. Use `-u normal` for routine events; keep `critical` for things that should stay on screen. Add `-a "Claude Code"` so Plasma groups them under one app name. |
| 6 | Is `notify-send` called by bare name? | Call it as `${pkgs.libnotify}/bin/notify-send` so it does not depend on what each person installed. |
| 7 | `grep -rnE "wl-copy\|wl-paste" .` | Call by store path (`${pkgs.wl-clipboard}/bin/wl-copy`). Confirm the 26.05 version is ≥ 2.3.0 if anything uses `wl-paste --watch`. |
| 8 | `grep -rn "TERMINAL" .` | Give it a fallback; don't assume it is set. |
| 9 | `grep -rnE "home.sessionVariables\|XDG_CURRENT_DESKTOP" .` | Shared module must not set desktop identity variables. |
| 10 | Status line: does it use Nerd Font glyphs? | Either ship the font via the module or use plain characters. |
| 11 | On a Plasma machine, after install: `notify-send -a "Claude Code" test body` from Konsole | Popup appears and auto-dismisses. Then trigger a real hook. |
| 12 | On a Plasma machine, after install: open a file picker from a Flatpak or browser | KDE dialog appears → portals intact. |

## Not checked

- **Nothing was run.** No Plasma 6 machine was available; every finding is from documentation or issue trackers. Checks 11 and 12 are the real test.
- **Léon's actual module.** I have not seen it, so I cannot say which of these it contains.
- **Which notification daemon Léon runs under Hyprland** (mako, dunst, swaync). "What differs from Hyprland" for icons and urgency depends entirely on that daemon, so the comparison is only described from the Plasma side.
- **Icons.** Whether `-i <name>` resolves the same icon under Breeze as under Léon's theme was not checked.
- **Versions in NixOS 26.05** of Plasma, KWin and `wl-clipboard`.
- **The official Claude Code terminal documentation** — blocked from this session; finding 5 relies on third-party summaries that all agree with each other.
