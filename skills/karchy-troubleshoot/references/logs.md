# Logs and core dumps

## Where each part logs

| Part | Command |
| --- | --- |
| The shell (Quickshell: bar, panels, menu, lock, notifications) | `journalctl -t karchy-shell -b` |
| Hyprland and what it starts | `journalctl --user -b -u 'wayland-wm@hyprland.desktop.service'` |
| A karchy user unit | `journalctl --user -b -u <unit>` |
| A system unit | `journalctl -b -u <unit>` |
| The kernel | `journalctl -k -b` |
| Errors of this boot | `journalctl -b -p err` |
| The previous boot | add `-b -1` in place of `-b` |
| DNS changes by karchy | `journalctl -t karchy-network-dns` |
| The Wi-Fi country helper | `journalctl -t karchy-wifi-regdomain` |
| The VPN policy, once the VPN is set up | `journalctl -t karchy-vpn` |
| Package changes | `/var/log/pacman.log` |

The shell logs to the journal because `karchy-launch-shell` starts Quickshell through `systemd-cat -t karchy-shell`. Quickshell's own log file lives in a runtime folder that a reboot clears, so use the journal. The same tag carries the launcher's lines: "Karchy shell exited with status N; relaunching." and "Giving up on the Karchy shell after N relaunches in under a minute." The second line means the shell stays down until `karchy-restart-shell` or the next login.

karchy's user units: `karchy-nightlight.service`, `karchy-sleep-lock.service`, `karchy-recover-internal-monitor.service`, `karchy-update-check.service` with its timer, `karchy-disk-health.service`, `karchy-sleep-shares.service` and `karchy-clipboard-persist.service` (wl-clip-persist: what was copied stays pasteable after the app that copied closes; if a paste comes up empty once that app is gone, check this unit). The clipboard history is not a unit: it is part of the shell (`journalctl -t karchy-shell`), fed by one `wl-paste --watch` process (`pgrep -af 'wl-paste --watch'`). If copies stop showing in the history, check that process and that `~/.config/karchy/shell.json` does not set `clipboard.history` to `false`; an empty history after a restart or a new login is how it works, since only pinned entries are kept. List what is on the machine with `systemctl --user list-units 'karchy-*'` and `systemctl list-units 'karchy-*'`.

Narrow a search by time with `--since "10 min ago"`. Reproduce the fault while `journalctl -f -t karchy-shell` runs to see only the new lines.

## karchy's own log files

All are under `~/.local/state/karchy/`.

| File | Content |
| --- | --- |
| `migrations/<name>.log` | Output of a migration that failed. A migration that succeeds leaves an empty mark file `migrations/<name>` and no log. |
| `quick-install.log` | The last Quick install action from the window, with pacman's errors. |
| `last-update` | Unix time of the last finished `karchy update`. |

`karchy update` writes no log file of its own. Its package steps are in `/var/log/pacman.log`, and a failed migration is named in the update's summary and retried at the next update. `karchy-migrate status` prints `done` or `pending` per migration.

## Hyprland

```bash
hyprctl configerrors      # errors in the loaded configuration
hyprctl version
hyprctl monitors
```

Hyprland's own log is `$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/hyprland.log`. It is gone after a logout, so copy the relevant lines before the user logs out.

A config error after an edit to `~/.config/hypr/` is the user's file. Fix the file, then `karchy-restart-hyprctl`. karchy's packages pause Hyprland's auto-reload during a pacman transaction (`karchy-hyprland-reload-guard`), so a config error that appears only during an update and clears after it is not a fault.

## Core dumps

karchy keeps systemd-coredump's defaults with a 1 GiB total limit (`/usr/lib/systemd/coredump.conf.d/10-karchy.conf`). Dumps are in `/var/lib/systemd/coredump` and systemd drops them after about 3 days.

```bash
coredumpctl list --since today
coredumpctl info <pid>           # signal, command line, and a stack trace when symbols allow
coredumpctl list quickshell
coredumpctl list Hyprland
```

- Match a dump's time to the journal lines just before it.
- `coredumpctl info` prints the command line and environment-derived paths. Treat the output as private.
- `coredumpctl debug <pid>` needs `gdb`. Installing it is a package change. Ask first.
- No dump for a shell that vanished is normal when the Wayland connection failed: Qt leaves without a signal, and the launcher's "exited with status" line is the only trace.
- A core dump file holds the process's memory. Never attach one to a bug report.

## What to hand to the next step

Keep the exact failing lines with their timestamps, the unit or tag they came from, and the command that reproduces the fault. Remove private data before any of it leaves the machine. See [reporting.md](reporting.md).
