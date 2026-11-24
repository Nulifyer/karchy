---
name: karchy
description: Use when customizing, configuring or operating a karchy system (the Arch-based Hyprland desktop with a Quickshell shell). Covers files in ~/.config/karchy, ~/.config/hypr and ~/.local/state/karchy, the karchy-* commands and the `karchy` router, the Settings window and its karchy-settings-* commands, themes, fonts, backgrounds, keybindings, the bar and shell plugins, updates, release channels, packages, Quick install and the AUR, network, trusted networks, DNS and sharing, storage, disks and kept mounts, power, idle and notifications, privilege (pkexec helpers, sudo) and snapshots. Use it before editing anything under /usr/share/karchy. For faults, crashes, logs, boot failures and bug reports use karchy-troubleshoot. Virtual machines and containers have their own skills (karchy-vms, karchy-containers) when those features are installed.
---

# karchy

karchy is an Arch-based desktop: Hyprland, a Quickshell shell, and about 250 `karchy-*` commands. It ships as pacman packages. Everything karchy owns is in `/usr/share/karchy` (`$KARCHY_PATH`). Everything the user owns is in the home folder.

## Find the owning command first

Change a setting through the command that owns it. Edit a file by hand only when no command owns the setting.

- `karchy` lists the command groups. `karchy <group> --help` lists a group. `karchy <group> <command> --help` shows usage, arguments and examples.
- `karchy commands` lists every public command with its summary. Add `--all` for the hidden ones, such as the `karchy-settings-*` commands that the Settings window calls. Add `--json` for a machine-readable list.
- `karchy theme set <name>` and `karchy-theme-set <name>` are the same program. The router maps words to the dashes of the file name.
- Each command is a script in `/usr/share/karchy/bin`. Its `# karchy:summary=` and `# karchy:args=` header lines say what it does. The comment block under them explains what it writes and why. Read that block before you run a command that you do not know.

## Match the care to the change

Small, reversible, user-level changes need no plan and no backup. Examples are one setting, one keybinding, a theme, a font, a bar widget.

1. Make the change through the owning command, or in the user's file under `~/.config`.
2. Tell the user what changed and how to undo it: the previous value, the reset command, or the line to delete.

Large or system-level changes need a plan and a snapshot. Examples are installing or removing many packages, a rework of the desktop or the Hyprland config, anything in `/etc`, system services, the bootloader, disks or partitions, the VPN or the firewall.

1. Write the plan: what changes, in which order, and what can go wrong. Get the user's agreement before you apply anything.
2. Take a snapshot of the system: `sudo snapper -c root create --print-number --cleanup-algorithm number --userdata important=yes --description "before <change>"`. `root` is the only snapper config on karchy. Tell the user the number that it prints.
3. Apply the plan.
4. Tell the user how to roll back: boot the snapshot from the boot menu's `Snapshots` entry, then run `sudo limine-snapper-restore`. Read [references/snapshots.md](references/snapshots.md) for the details.

A snapshot covers the system, not `/home`. If a large change rewrites files in the home folder, copy those files first and name the copy in your report. pacman takes its own snapshots before and after each transaction (snap-pac), so a package change through `karchy update` or `karchy pkg` is already covered.

If you cannot tell which kind a change is, treat it as large.

## Leave the VPN alone

karchy's VPN (WireGuard with a kill switch, part of karchy) is the user's to change: not its mode, its configuration, its profiles, its kill switch or its units, and don't work around the kill switch. You may read `karchy-vpn status` to explain why the internet is blocked (`connecting`, `failed` or `paused` blocks ordinary traffic on purpose). Then tell the user, who changes the VPN in the network panel or in Settings › Network › VPN.

## Never write under /usr/share/karchy

Read `/usr/share/karchy` freely. It is the best documentation of how a feature works. Do not change anything in it, and do not change `/usr/bin/karchy-*` or `/usr/lib/karchy`.

- pacman owns those files. The next `karchy update` replaces them, so an edit there is lost without notice.
- karchy updates a machine in place and never reinstalls it. Updates change the defaults in `/usr/share/karchy`. They never rewrite the user's files in `~/.config`. A user's file holds only the differences from the defaults, so the rest keeps following the defaults as they improve.
- Root runs code from there. A changed file is a security problem as well as a lost edit.

Put the change in the user layer instead: the owning command, a file in `~/.config/karchy` or `~/.config/hypr`, or a hook. If the user layer cannot express the change, say so and propose a report to the karchy repository. Do not patch the packaged file.

Do not copy a whole default file into `~/.config` to change one value. Write only the difference. A full copy stops that file from following later defaults.

## Privilege

- If a karchy command or the Settings window can make the change, use it. Those go through karchy's own root helpers (pkexec), which accept fixed choices only.
- Otherwise use `sudo` in a terminal, with the user present to type the password. Do not ask for the password, store it or pipe it.
- Never add a sudoers rule, a `NOPASSWD` entry or a polkit rule, and never widen an existing one, to save the user a prompt.

Read [references/privilege.md](references/privilege.md) before any change that needs root.

## Read the reference for the task

| Read | When the task |
| --- | --- |
| [references/layout.md](references/layout.md) | needs to know where a file lives, who owns it, or whether an edit survives an update. Also for hooks, the menu extension and dev mode |
| [references/settings.md](references/settings.md) | changes something the Settings window shows: displays, input, power, notifications, default apps, security (passwords, fingerprint, FIDO2), SSH and git, date and time, appearance, fonts |
| [references/keybindings.md](references/keybindings.md) | adds, changes, removes or looks up a keyboard shortcut. karchy has its own keybinding system with layers; use `karchy-settings-keybindings` |
| [references/hyprland.md](references/hyprland.md) | touches `~/.config/hypr`, window rules, monitors, autostart, the bar, shell plugins, or needs a reload |
| [references/themes.md](references/themes.md) | sets, installs, makes or adjusts a theme, a background, the font or the text size |
| [references/privilege.md](references/privilege.md) | needs root, or meets a password prompt it did not expect |
| [references/packages.md](references/packages.md) | installs or removes software, runs an update, changes the release channel, or uses Quick install or the AUR |
| [references/network.md](references/network.md) | changes Wi-Fi, trusted networks, DNS, sharing or the firewall |
| [references/storage.md](references/storage.md) | touches disks, mounts, network shares, deduplication (bees) or disk health |
| [references/power.md](references/power.md) | changes idle times, lid or power-button actions, sleep, hibernation, power profiles or notifications behaviour |
| [references/snapshots.md](references/snapshots.md) | takes, lists, boots or restores a snapshot |

## After a change

- Check that it took effect: read the value back with the command's `status`, or run `hyprctl configerrors` after a Hyprland edit.
- Report the change, the file or command used, and the undo step.
- If something broke, switch to the karchy-troubleshoot skill.
