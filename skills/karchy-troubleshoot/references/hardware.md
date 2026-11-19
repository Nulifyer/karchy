# Hardware checks

karchy's `karchy-hw-*` commands answer one question each. Most print nothing and answer through the exit status: 0 is yes. Read a command's header in `/usr/share/karchy/bin/` before relying on an edge case.

## Graphics and slow desktop

```bash
karchy-hw-renderer             # which GPU draws the desktop, and whether it is software
karchy-hw-renderer --json      # adds reason and fix
```

A software renderer (llvmpipe) makes everything work but feel slow. The `reason` names the cause: a virtual machine without 3D graphics, a kernel update whose modules load only after a restart, or an NVIDIA card whose driver is not loaded or is too old for NVIDIA's current drivers. After a kernel update, compare `uname -r` with `pacman -Q linux-cachyos`. A mismatch means a restart is pending.

| Command | Answer |
| --- | --- |
| `karchy-hw-nvidia` | Exit 0 when the machine has an NVIDIA GPU. |
| `karchy-hw-nvidia-generation` | Prints the driver the GPUs need: `open`, `580xx` or `unsupported`. |
| `karchy-hw-nvidia-display` | Exit 0 when NVIDIA drives the display, not a hybrid integrated GPU. |
| `karchy-hw-nvidia-gsp`, `karchy-hw-nvidia-without-gsp` | Whether the card has GSP firmware. |

Match the generation to the installed driver package: `pacman -Q karchy-nvidia karchy-nvidia-580xx 2>/dev/null`. `unsupported` cards run on nouveau. Then `journalctl -k -b | grep -i -E 'nvidia|nouveau|drm'`.

## Monitors and laptop lid

| Command | Answer |
| --- | --- |
| `hyprctl monitors` | What Hyprland sees, with modes and scale. |
| `karchy-hw-external-monitors` | Exit 0 when an external monitor is physically connected. |
| `karchy-hw-laptop`, `karchy-hw-laptop-closed`, `karchy-hw-clamshell` | Laptop, lid closed, clamshell mode active. |
| `karchy-hw-display` | The backlight device used for brightness. |
| `karchy-hw-recover-internal-monitor` | Removes the toggle that disables the internal monitor when no external display is connected. It changes state. |

A laptop with a black internal screen after undocking: run `karchy-hw-recover-internal-monitor`, then `karchy-restart-hyprctl`. `karchy-recover-internal-monitor.service` runs the same command for the session.

## Audio, Bluetooth, input

- Audio: `wpctl status` shows devices and the defaults. `journalctl --user -b -u pipewire -u wireplumber`. `karchy-restart-audio` restarts the services and recovers stuck USB audio devices.
- Bluetooth: `rfkill list`, `bluetoothctl show`, `journalctl -b -u bluetooth`. `karchy-restart-bluetooth` unblocks and restarts it.
- Trackpad: `hyprctl devices`. `karchy-restart-trackpad` rebinds the driver.
- Fingerprint: `karchy-hw-fingerprint` exits 0 when a reader is present.

## Disks

smartd and the monthly btrfs scrub write warnings to `/var/lib/karchy/disk-health`, and `karchy-disk-health.service` shows each as a notification that stays until dismissed.

```bash
ls /var/lib/karchy/disk-health            # one file per open warning; empty means none
karchy-disk-health details <warning>      # the warning, then smartctl -a or the scrub's report; asks for the password
systemctl status smartd
sudo btrfs device stats /
sudo btrfs scrub status /
karchy-drive-info <drive>
karchy-disk-speedtest [target-dir]        # writes a test file to measure read and write speed
df -h; sudo btrfs filesystem usage /
```

- A SMART warning about failing blocks is a reason to back up now. Say so before anything else.
- A full disk on btrfs: snapshots hold old data. `sudo snapper -c root list` shows them. Deleting snapshots removes rollback points, so it needs the user's OK.
- `karchy-disks-check` offers to mount internal data disks that have no mount. It is interactive and for the user, not a diagnostic.

## Power and battery

`karchy-battery-status` prints the charge and the power draw. `karchy-powerprofiles-list` lists the power profiles on a laptop with `karchy-laptop`. Sleep problems: `journalctl -b -1 -k | grep -i -E 'PM:|suspend|hibernat'` for the boot that slept. `karchy-hibernation-available` exits 0 when the machine supports hibernation.

## Firmware and Secure Boot

- `fwupdmgr get-devices` and `fwupdmgr get-updates` only read. `karchy-update-firmware` installs firmware updates with fwupd: a system-level change that needs the user's OK and mains power.
- `bootctl status` shows whether Secure Boot is on and whether the firmware is in Setup Mode. `sbctl status` works only after `karchy-secureboot setup` installed sbctl.
- `karchy-secureboot check` runs at login and prints nothing. On a machine where Secure Boot was set up, it sends a notification when a firmware update or reset cleared the keys, or when Secure Boot is off. `karchy-secureboot setup` and `enroll` change firmware keys: large changes.

## Load

`karchy-system-stats` prints the CPU and memory figures the bar uses. `btop` is installed for a live view. `systemd-cgtop` shows which unit uses the resources.
