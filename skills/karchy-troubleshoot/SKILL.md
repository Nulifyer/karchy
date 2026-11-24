---
name: karchy-troubleshoot
description: Use when something on a karchy system is broken, crashes, hangs, fails to boot or needs a bug report. Covers logs (journalctl, journalctl -t karchy-shell for the Quickshell shell, the Hyprland unit, ~/.local/state/karchy update, migration and Quick install logs, /var/log/pacman.log), core dumps (coredumpctl), boot failures, booting and restoring a snapshot (Limine Snapshots entries, snapper, limine-snapper-restore, karchy-snapshot-boot), hardware checks (karchy-hw-*, karchy-disk-health, karchy-secureboot), network diagnosis (karchy-network-status, karchy-network-dns, karchy-trusted-networks, nmcli), the karchy-restart-* commands, and reporting a bug to github.com/Nulifyer/karchy. Do not use to customize or configure a working system (karchy), or to change karchy's VPN (the user's to change).
---

# karchy-troubleshoot

Find the cause before changing anything.

## Rules

- Diagnosis only reads. Reading logs, status commands and files under `/usr/share/karchy` needs no permission from the user.
- A fix is a change. Follow the `karchy` skill's change rules: a small, reversible user-level change is applied and reported with its undo, and a large or system-level change needs a plan, the user's OK and a snapshot first.
- A `karchy-restart-*` command is a small change. Say which one ran.
- Do not edit files under `/usr/share/karchy` or `/usr/lib/karchy` to test a fix. A package update replaces them.
- Commands that read system logs or disks may need `sudo`. Run them in a terminal with the user present. Do not add sudoers or polkit rules.
- Treat log content as private. Show the user an excerpt, not the whole journal, and never send any of it off the machine without the user's OK.

## First facts

Collect these before reading logs:

```bash
karchy version            # release and channel, or the dev checkout's commit
systemctl --failed
systemctl --user --failed
uname -r
```

Ask what changed last: an update, a new package, a config edit, new hardware. `grep -E 'upgraded|installed|removed' /var/log/pacman.log | tail -n 40` shows recent package changes. `karchy-migrate status` lists migrations as `done` or `pending`.

## Route by symptom

| Symptom | Read |
| --- | --- |
| The bar, panels, menu, lock screen or a Settings window misbehaves or is gone; an app crashed; an update or migration failed | [references/logs.md](references/logs.md) |
| The system does not boot, boots to a dark screen or emergency mode, a kernel misbehaves, or an update broke the system and it must go back | [references/boot-and-rollback.md](references/boot-and-rollback.md) |
| Slow desktop, graphics, NVIDIA, monitors, audio, Bluetooth, trackpad, disks, battery, firmware, Secure Boot | [references/hardware.md](references/hardware.md) |
| No internet, no name lookups, a sign-in page that does not open, a blocked port, slow network | [references/network.md](references/network.md) |
| The user wants to file a bug, or the cause is karchy's own code | [references/reporting.md](references/reporting.md) |

If `karchy-vpn status` shows `connecting`, `failed` or `paused`, a blocked internet connection is the VPN's kill switch. That is the VPN working as designed: don't change it. Tell the user, who changes the VPN in the network panel or in Settings › Network › VPN. While it shows `protecting`, NetworkManager calls the physical link "limited" (its check can't leave past the kill switch); the internet works through the tunnel.

## Quick restarts

Use one of these when the log shows a hung component, not as a substitute for reading the log. Each is safe to run in the session.

| Command | Effect |
| --- | --- |
| `karchy-restart-shell` | Restarts the Quickshell shell (bar, panels, menu, notifications). |
| `karchy-restart-hyprctl` | Reloads Hyprland's configuration. |
| `karchy-reload-desktop` | Reloads Hyprland, then restarts the shell. `karchy update` ends with it. |
| `karchy-restart-audio` | Restarts the audio services and recovers stuck USB audio devices. |
| `karchy-restart-bluetooth` | Unblocks and restarts Bluetooth. |
| `karchy-restart-wifi` | Unblocks and restarts Wi-Fi. |
| `karchy-restart-trackpad` | Unbinds and rebinds the trackpad's driver. |
| `karchy-restart-terminal` | Reloads supported terminals after a config change. |

If a restart fixes the symptom, still record the log lines from before it. They are the evidence for a bug report.

## Done

State the cause and the evidence for it, what was changed and how to undo it, and what was not checked. If the cause is unknown, say so and list what was ruled out.
