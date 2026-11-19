# Ownership audit: what karchy takes from Omarchy

Status: **approved 2026-11-13** (D-46 to D-49). Outcomes: every Drop and Simplify item approved. Of the Your-call items, the webcam overlay, Wi-Fi band and QR, safe LUKS password change and Hyprland reload guard are **kept**; tmux theme sync is **dropped**. Hardware-specific items are dropped for now and come back from upstream when that hardware is in use. Based on the Omarchy v4.5.0 files currently vendored in this repo (747 files).

Decided so far (2026-11-13):
- karchy owns this code, with no upstream sync; a review helper shows what upstream changed in files we took.
- Full rebrand to karchy.
- English only.

## The size of what we own

| Part | Size | Where the value is |
|---|---|---|
| Quickshell shell (QML/JS) | 38,786 lines in 167 files | Almost all of it: bar, panels, menu, notifications, lock, OSD, clipboard, image picker, plugin host |
| Commands (bash) | 14,310 lines in 220 commands | Mostly: the theme engine, capture, the bar CLI, plugins, the keybinding viewer, monitors, security setup |
| Hyprland Lua modules | 24 files | Per-monitor workspaces, floating mode, helpers, look and feel |
| Themes, templates, fonts, English strings | 23 themes (78 MB, mostly wallpapers), 24 templates | Theme system |

**The thin wrappers are not the debt.** There are 42 commands of 6 lines or fewer, about 150 lines in total. They are the shell's command interface (`omarchy-hyprland-monitor-focused`, `omarchy-toggle-enabled`, …). Merging or inlining them would mean editing QML callers for almost no gain. Proposal: keep them, renamed.

**The real debt is code for hardware, platforms and apps karchy doesn't have.** That code still runs, still has to be read, and still breaks. About 1,300 lines can go without losing anything on karchy's machines (the RTX 5080 desktop, the Framework 13 AMD and the VM).

## Drop: nothing lost on karchy's machines

| Command(s) | Lines | What it does | What you lose |
|---|---|---|---|
| `hw-platform` | 183 | Detects ARM families (Apple Silicon, Snapdragon, NVIDIA N1x, GB10) | ARM support. karchy is x86-only |
| `lifecycle-dispatch` | 133 | Hands boot and LUKS operations to ARM platform packages | Nothing on x86. Its callers (`drive-password`, fingerprint setup and removal) take the generic path, which they already use on x86 |
| `brightness-display-apple`, `hyprland-monitor-focused-apple` | 82 | Brightness for Apple Studio Display and Pro Display XDR | Brightness keys on Apple monitors |
| `theme-set-keyboard`, `-asus-rog`, `-f16` | 39 | RGB keyboard backlight follows the theme on ASUS ROG and Framework 16 | The Framework 13 has no RGB keyboard, so nothing. **Restored 2026-11-14** at the user's request, so a later machine with one follows the theme |
| `audio-tuning` (+ `default/audio`, its user service) | 247 | Speaker EQ profiles; ships profiles only for the ASUS ProArt P14 (N1X) and Dell XPS 2026 | Nothing for your hardware |
| `theme-set-hermes`, `-pi`, `-hunk`, `-herdr-machines`, `-obsidian`, `-fcitx5`, `restart-helix` | 350 | Theme sync for Hermes, Pi, hunk, herdr, Obsidian, fcitx5 and Helix | Those apps' colors following the theme. None of them are in karchy; add one back if you start using it. **`-pi` and `-obsidian` restored 2026-11-14** (the user installs them later) |
| `restart-xcompose`, `setup-input` | 40 | Apply XCompose and pick CJK input methods (fcitx5) | CJK input-method setup. fcitx5 and XCompose were dropped |
| `locale-generate` | 39 | Generates system locales for the 54 Omarchy languages (needs a NOPASSWD sudo rule) | Switching the system language from the shell (English only now) |
| `theme-bg-boot-intro` (+ intro code in `BackgroundIntro.qml` and the image picker) | 174 | Plays a theme's intro video at boot and on theme switch | Nothing: intro videos aren't shipped and intros were dropped |
| `toggle-animations` | 14 | Turns animations on or off | The command. Its menu entry was already dropped; Hyprland config still works |

## Simplify: same feature, less code

| Command(s) | Now | Change | What you lose |
|---|---|---|---|
| `launch-about` | 239 | `fastfetch` in a terminal with karchy's logo (about 15 lines) | Omarchy's animated logo and branding |
| `theme-set` | 432 | Call theme hooks only for apps karchy ships or you use (foot, GTK, browser, VS Code, Claude Code, T3 Code, OpenCode, btop, gum, glass), instead of 17 no-op stubs | Nothing |
| `drive-password`, `setup-security-fingerprint`, `remove-security-fingerprint` | 593 | Remove the `lifecycle-dispatch` (ARM) branches | Nothing on x86 |
| `hw-*` predicates | 370 | Keep only the predicates kept code calls (laptop, lid, fingerprint, NVIDIA, displays) | ARM and vendor predicates |
| `omarchy` router + `bin/karchy` | 971 + 25 | One `karchy` router (Omarchy's metadata-driven one, renamed). `karchy update` becomes one of its groups | Nothing |

## Your call: features with a real cost or real value

| Feature | Lines | What it does | If dropped, you lose |
|---|---|---|---|
| Webcam overlay in recordings | 137 + part of `capture-screenrecording` | Puts your webcam in a corner of screen recordings, resizable with keys | Picture-in-picture webcam in recordings |
| Wi-Fi band pinning (`network-band`) | 130 | Network panel row that pins the active Wi-Fi to 2.4, 5 or 6 GHz | Pinning a band from the panel (still possible with `nmcli`) |
| Wi-Fi QR code (`network-qr`) | 65 | Shows a QR code so a phone can join the current Wi-Fi | Sharing Wi-Fi by QR |
| tmux theme sync (`theme-set-tmux`) | 106 | tmux colors follow the theme | Only matters if you use tmux |
| Safe LUKS password change (`drive-password` + `luks-rekey.sh`) | 356 + helper | Changes the disk password with a journal that survives a crash or power loss mid-change, and verifies the old password no longer works | The alternative is a ~30-line `cryptsetup luksChangeKey` wrapper without crash recovery |
| Hyprland reload guard (`hyprland-reload-guard`) | 94 | Pauses Hyprland's config auto-reload while pacman updates files, so you don't get half-updated reloads | Needs two small pacman hooks; without it, a Hyprland reload can catch a mid-update config |

## Keep as-is (renamed)

These are the reason for taking Omarchy's code at all:
- **Shell and plugin system:** `shell`, `shell-config`, `plugin-*` (9 commands then; since D-106 only `list`, `enable` and `disable`, as add-ons became packages), `bar`, `bar-text-color`, `osd`, `notification-send`, `menu`, `menu-select`, `menu-images`, `menu-plugin` (dropped by D-106), `menu-timezone`, `menu-keybindings` (the Super+K viewer).
- **Theme engine:** `theme-set-templates`, `theme-color`, `theme-osc`, `theme-install`/`-remove`/`-list`/`-extras`/`-refresh`, `theme-bg-*` (except the intro), `theme-switcher`, `theme-colors-from-alacritty` (installs older community themes), `theme-set-browser`(+`-policy`), `-gnome`, `-glass`, `-foot`, `-vscode`, `-claude`, `-t3code`.
- **Hyprland:**
  - monitors: `-monitor-*`, `-monitor-scaling`, clamshell, internal display and mirroring for docking
  - workspace layouts
  - window helpers: `-window-*`
  - toggles, session-lock helpers
  - `display-text-size`
- **Capture:** screenshot (Omasnap), screen recording, region picker.
- **Hardware controls:** audio (`audio-*` except tuning), brightness (`-display`, `-ddc`, `-keyboard`), bluetooth, battery, power profiles, input devices, lid and sleep (`system-*`), hibernation check.
- **Packages and apps:** `pkg-*` pickers, web apps, default apps, launchers (`launch-*`), `remove-launcher-entry`.
- **Security setup:** fingerprint, FIDO2, sshd, SSH agent (with the ARM branches removed).
- **Small utilities:** reminders, disk and network speed tests, `cmd-*`, `state`, `hook`, `sudo-keepalive`, `show-*`, `git-url-check`, `update-firmware`, `update-time`, `restart-*` (audio, bluetooth, wifi, trackpad, shell, hyprctl, terminal, btop, gum, opencode), `i18n`, `language` (read-only use).

## Shell (QML) trims

| Change | What you lose |
|---|---|
| Remove the DNS provider section from the network panel (D-44) | Switching DNS presets in the panel |
| Remove intro playback from `BackgroundIntro.qml`; keep its background switch | Theme intros (not shipped anyway) |
| Remove leftover references to dropped plugins (weather anchor, Dropbox tray mapping, night-light and remote-session service IDs) | Nothing |

Total effect if every Drop and Simplify is approved: about 1,800 fewer bash lines (13%). The shell stays essentially whole. The rename then runs on what's left.

## Omarchy's system tuning (`etc/`), audited 2026-11-13

The audit above covered the files karchy vendored. Omarchy also ships an `etc/` tree that was never vendored, so it was never audited. Testing the packaged install found four pieces of it that kept karchy code depends on. They are now in karchy-settings:

| File | Why it's needed |
|---|---|
| `logind.conf.d/10-ignore-power-button.conf` | karchy binds the power key to the power menu; without this, logind powers off as soon as the key is pressed |
| `logind.conf.d/20-inhibit-delay.conf` | The lock-before-sleep unit needs up to 15 s; logind's default 5 s can let a laptop suspend unlocked |
| `xkb/rules/evdev`, `xkb/symbols/karchy` | `default/hypr/input.lua` sets the `karchy:shift_caps_compose` option (Shift + Caps Lock is Compose); without these files it silently did nothing |
| `sudoers.d/karchy-theme-browser` | Every theme switch asked for a password to recolor the browser |
| `fontconfig/50-karchy.conf` (simplified from `default/fontconfig/conf.avail/50-omarchy.conf`) | Without it the system monospace font was Noto Sans Mono while the terminal used JetBrainsMono, and `karchy-font-set` assumes a package default under it. Kept: monospace, system-UI aliases, emoji fallback. Dropped: CJK and Arabic language rules and the Liberation fonts (English only, D-49) |

The rest are tuning choices, all decided (the remaining skips accepted by the user 2026-11-16). The network rows were **decided 2026-11-14** (networking plan, step 1) and ship in karchy-settings under `/usr/lib`, so a file in `/etc` wins. Recommendations or decisions in the last column.

| File | What it does | What you lose without it | Recommendation |
|---|---|---|---|
| `NetworkManager/conf.d/*-wifi-powersave.conf` | Wi-Fi power save off | Idle latency spikes of 20–300 ms; some Intel firmware drops the link | **Decided: kept** as `/usr/lib/NetworkManager/conf.d/30-karchy-wifi-powersave.conf` |
| `sysctl.d/90-*-arp.conf` | ARP answers only for the interface's own address | Docked with Ethernet and Wi-Fi on one network, traffic can stay on Wi-Fi | **Decided: kept** in `/usr/lib/sysctl.d/60-karchy-network.conf` |
| `sysctl.d/99-*-sysctl.conf` | TCP MTU probing, BBR + fq; plus swap tuning written for zram | Some SSH flakiness on bad links; more bufferbloat | **Decided: network part kept** in `/usr/lib/sysctl.d/60-karchy-network.conf`, with `/usr/lib/modules-load.d/karchy-bbr.conf` loading `tcp_bbr` (a module in Arch's and CachyOS's kernels); the zram swap values dropped (karchy uses zswap) |
| `resolved.conf.d/10-disable-multicast.conf` | resolved's mDNS/LLMNR off | Two mDNS responders (resolved and avahi) can conflict | **Decided: kept** as `/usr/lib/systemd/resolved.conf.d/10-karchy-multicast.conf`; avahi answers `.local` |
| `system.conf.d/10-faster-shutdown.conf`, `user@.service.d/10-faster-shutdown.conf` | Stop timeouts 5 s instead of 90 s | A hung service can hold shutdown for 90 s | Done 2026-11-14 as CachyOS's 10 s (system and user units); the 5 s user-session limit is left out, since it would cut off running VMs |
| `system.conf.d/20-mount-events.conf` | Higher mount-event rate limit | Rare boot delays with many mounts | Done 2026-11-14 |
| `system.conf.d`, `user.conf.d/20-*-nofile.conf` | Higher open-file limits | Some games and dev tools hit the default limit | Done 2026-11-14 |
| `udev/rules.d/60-*-io-scheduler.rules` | Kyber I/O scheduler on whole disks | Interactive reads can stall behind big writes (updates, copies) | Done 2026-11-14 as CachyOS's per-type rules (Kyber NVMe, mq-deadline SSD, BFQ HDD) |
| `security/faillock.conf` | 10 failed logins before lockout instead of 3 | Three typos lock sudo and the TTY for 10 min (the lock screen already allows 10) | Done 2026-11-14 (installer sets `deny = 10`; the lock screen shares the tally) |
| `mpv/mpv.conf` | GPU video decoding in mpv | Higher CPU use playing video | Done 2026-11-14 (`/etc/mpv/mpv.conf`) |
| `gnupg/dirmngr.conf` | Several keyservers, short timeouts | Key fetches (gpg, pacman-key) fail when one keyserver is down | Done 2026-11-14 (`/etc/gnupg/dirmngr.conf`) |
| `mkinitcpio.conf.d/thunderbolt_module.conf` | Thunderbolt in the initramfs | A dock keyboard may not type at the disk password prompt | Done 2026-11-14 |
| `systemd/user/wayland-wm@hyprland.desktop.service.d/10-keep-shell.conf` | Stops Hyprland before its shell at logout | The wallpaper vanishes a moment early during logout | Done 2026-11-14 |
| `modprobe.d/*-usb-autosuspend.conf` | USB autosuspend off everywhere | Some USB devices drop out when idle | **Decided 2026-11-16: kept** as the udev rule `/usr/lib/udev/rules.d/90-karchy-usb-autosuspend.rules` (usbcore is built into the kernel, so a modprobe option wouldn't apply) (costs a little laptop battery) |
| `NetworkManager/conf.d/*-connectivity.conf` | Captive-portal check against `ping.omacom.io` (Basecamp's server) over HTTP | Hotel/airport sign-in pages may not open automatically with Arch's default check | **Decided: skipped.** Detection stays on Arch's default check; the panel's "Sign in to network" opens `http://neverssl.com` (Arch's host is HSTS-preloaded, so a portal can't intercept it) |
| `sudoers.d/*-tzupdate` | Set the timezone from the menu without a password | One password prompt when changing timezone | Skip |
| `sudoers.d/*-locale-generate` | Generate a new language's locale without a password | — (English only, D-49) | Skip |
| `tmpfiles.d/*-zswap.conf` | Turns zswap off (Omarchy uses zram) | — (karchy uses zswap, D-10) | Skip |
| `fastfetch/config.jsonc` | About screen layout | — (`karchy-launch-about` passes its own logo) | Skip |
| `mkinitcpio.conf.d/i2c_hid_of_module.conf` | Keyboard at the disk prompt on Snapdragon laptops | — (no ARM target) | Skip |
| `plocate-updatedb.service.d/ac-only.conf` | plocate only indexes on AC | — (plocate not installed) | Skip |
| cups, docker, mise, sddm, plymouth, limine-entry-tool, Omarchy's mkinitcpio hooks, kitty, `nopasswd-sudo`, `dns` sudoers | Features karchy dropped or replaced | — | Skip (cups returns with the Printers optional feature, D-38) |

## VS Code theming (D-23), changed 2026-11-14

Omarchy's `theme-set-vscode` wrote `workbench.colorTheme` into `settings.json` on every theme switch, and for themes that name a marketplace theme it installed that extension. D-23 rules both out (`settings.json` may be a dotfile). karchy now always generates the "Karchy" color-theme extension from the current theme's colors and never edits settings or installs extensions. **What you lose:** the hand-picked marketplace themes some themes named (for example Gruvbox Material for gruvbox); you get colors generated from the palette instead. Pick "Karchy" once in VS Code.
