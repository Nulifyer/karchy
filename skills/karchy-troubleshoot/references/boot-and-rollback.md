# Boot problems and rollback

The full procedures are in karchy's `docs/recovery.md` (github.com/Nulifyer/karchy). This file is the map. When the machine does not boot, the agent is not running on it: give the user the steps to carry out and wait for what they see.

## Layout the steps rely on

- Partition 1 is the 4 GiB EFI partition, mounted at `/boot`. Partition 2 is LUKS2. One password unlocks it. An install made without disk encryption has btrfs directly on partition 2 and asks no disk password: `lsblk -o NAME,FSTYPE` shows `btrfs` there instead of `crypto_LUKS`, and `/etc/karchy/install.conf` has `KARCHY_ENCRYPT=login`. That is a choice made at install, not a fault.
- Inside is one btrfs filesystem with the subvolumes `@ @home @root @srv @cache @log @tmp @swap`.
- The boot loader is Limine. Its menu shows for 3 seconds. An arrow key stops the countdown.
- The disk password is asked on a splash screen (Plymouth, theme `karchy`: the mark and a password box). The kernel line carries `splash` for it. Without `splash`, or with `plymouth.enable=0`, the password is asked as text on a screen with karchy's name. Escape on the splash shows the boot messages.
- After logging out, and at boot on an install with `KARCHY_ENCRYPT=login`, greetd shows karchy's login screen (`/usr/lib/karchy/greeter`: Quickshell in a Hyprland of its own, as the `greeter` user). When it can't start, greetd's text login (agreety) replaces it.
- snapper's config is `root`. snap-pac takes a snapshot before and after every pacman transaction, and limine-snapper-sync lists them in the boot menu under `Snapshots`.
- `/home` is not in a snapshot. A rollback keeps the user's files and the user's `~/.config` as they are now.

## Pick the route

| Situation | Route |
| --- | --- |
| An update broke the desktop or the system, and the boot menu still works | Boot a snapshot from before the update, then restore it. |
| Only the new kernel misbehaves | Boot `linux-cachyos-lts` from the menu. Same system, other kernel. |
| No password box, a black screen where it should be, or keys do nothing there | Boot once without the splash: press `e` on the entry, add ` plymouth.enable=0` at the end of the `cmdline:` line, then F10. The text prompt asks instead. For good: delete `splash` from `KERNEL_CMDLINE[default]` in `/etc/default/limine`, then `sudo limine-mkinitcpio`. |
| Dark screen or a stall during boot | For one boot, press `e` on the entry and delete `quiet splash loglevel=3 systemd.show_status=auto` from the `cmdline:` line, then F10. The editor is off under Secure Boot. Escape on the splash also shows the messages. |
| "You are in emergency mode" | Press Enter for a root shell. `journalctl -xb` shows what failed. A wrong `/etc/fstab` line is the usual cause. |
| The text login appears where the login screen should be, or the login screen is black | `journalctl -b -t karchy-greeter` says why it fell back. For the text login on purpose: ` karchy.greeter=text` on the kernel line for one boot, or `sudo touch /etc/karchy/greeter-text`. Ctrl+Alt+F2 is a text console either way. |
| The password is right but the login screen says "Wrong password" or names a locked account | Ten wrong tries lock the account for 2 minutes (`faillock --user <name>` shows the tally; `sudo faillock --user <name> --reset` clears it). Check the keyboard layout named at the bottom left of the screen. |
| Saved passwords are not available after login | `karchy-keyring status` says `open`, `locked` or `none`. Where the login screen asks for a password the keyring opens with the login password (`pam_oo7` in `/etc/pam.d/karchy-login`); on an encrypted computer that logs in by itself, with a key in `/etc/credstore`. `journalctl -b -t karchy-keyring` says what the login did about it, `journalctl -b --user -u oo7-daemon` whether the secret fitted ("Invalid secret"). `locked` after the system was taken back to a snapshot is repairable without loss (the keyring is in the home folder, the password and the key are not): see `docs/recovery.md` › Someone can't sign in; on a computer that logs in by itself, one log out and login at the login screen often puts it right. `locked` after a password reset by an administrator (Settings › Users, or `sudo passwd <name>`) is expected: the keyring keeps the old password, and only its owner can reset it (Settings › Security › Saved passwords › Reset…, or `karchy-keyring reset`), which erases what apps saved. Never run the reset for the user unasked. |
| A data disk at `/mnt/data` is missing after boot | `systemctl status 'systemd-cryptsetup@*'` and `journalctl -b -u 'systemd-cryptsetup@*'`. Its line in `/etc/crypttab` names a key file in `/etc/cryptsetup-keys.d`; the install password opens the disk by hand (`docs/recovery.md`, "A data disk the installer encrypted"). |
| No menu entry works | Boot the karchy or Arch ISO, unlock, mount and chroot. Follow `docs/recovery.md`, "Get into the system from the install media", exactly. |
| The firmware lost the boot entry | The machine still boots from the fallback path. `sudo limine-install` puts the named entry back. |
| Resume from hibernation fails | `journalctl -b -k \| grep -i -E 'hibernat\|resume\|PM:'`. See `docs/recovery.md` for turning hibernation off. |

## Boot a snapshot

1. In the boot menu, open `Snapshots`.
2. Open the newest snapshot older than the fault. Each shows its number, date and the packages that changed.
3. Boot `linux-cachyos` inside it and type the disk password.

The snapshot runs on a writable layer held in memory. Every change outside `/home` is gone at the next boot, so do not install or repair anything in this state except the restore below. A notification says which snapshot is running and offers "Restore this snapshot". `karchy-snapshot-boot check` shows that notification again. One failed unit, `systemd-remount-fs.service`, is expected on a snapshot boot.

To tell whether the running system is a snapshot: the root subvolume on the kernel command line ends in `/.snapshots/<number>/snapshot`.

```bash
grep -o 'subvol=[^ ]*' /proc/cmdline
```

## Restore a snapshot

Restoring replaces the normal system with the running snapshot. It is a large change: confirm with the user first. Run it only while that snapshot is booted.

1. Use the notification's button, or run `sudo limine-snapper-restore` in a terminal.
2. Check the number and date it shows. Press `r`.
3. Type a description for the backup, such as `before restore`. The replaced system is kept as a new snapshot under that name.
4. Answer `Y` to reboot.

If the restored system is worse, boot the backup from `Snapshots` and restore it the same way.

## Inspect snapshots from the running system

```bash
sudo snapper -c root list
sudo snapper -c root status <before>..<after>     # files changed between two snapshots
sudo snapper -c root diff <before>..<after> /etc/<file>
```

Snapshots are in `/.snapshots/<number>/snapshot`, readable by root only. To get one file back, copy it out of the snapshot. Do not use `snapper rollback` or `snapper undochange` on the running system. karchy's rollback path is the boot menu plus `limine-snapper-restore`, which keeps the boot entries in step.

karchy keeps few snapshots (the number limit is 5, with no timeline snapshots), so the snapshot from before an old fault may be gone. Check the list before promising a rollback.

## After a repair from the install media

Inside the chroot, the usual commands are `limine-update` (rebuilds the initramfs and boot entries), `limine-install --fallback`, `snapper --no-dbus -c root list`, `pacman -Syu` to finish an interrupted update, and `journalctl -D /var/log/journal -b -0 -p err` for the last boot's errors. Leave with `exit`, `umount -R /mnt` and `cryptsetup close <name>`.

## Traps

- Never restore a LUKS header to a disk other than the one it came from.
- Do not name partitions by `/dev/disk/by-label/karchy`. The LUKS partition and the filesystem inside it share that label.
- With Secure Boot on, the ISO does not boot. The user turns Secure Boot off in the firmware and must not erase the keys. After a firmware reset clears keys, `karchy-secureboot enroll` puts karchy's keys back.
- A kernel parameter that must stay goes into `/etc/default/limine` followed by `sudo limine-update`. That is a system-level change.
