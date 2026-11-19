# Snapshots and rollback

Read this before a large or system-level change, to take a snapshot first, and when the user wants to undo a system change. To diagnose a system that does not boot, use the `karchy-troubleshoot` skill.

## What a snapshot covers

karchy has one snapper config, `root`, for the subvolume `@` mounted at `/`.

- A snapshot holds the system: `/usr`, `/etc`, `/var/lib`, `/opt` and the installed packages.
- A snapshot does not hold the home folder (`@home`), `/root`, `/srv`, `/var/cache`, `/var/log`, `/var/tmp` or the swap file. Those are separate subvolumes.
- A rollback therefore does not undo a change in `~/.config`. Before a large change to user configuration, also copy the files you will change, for example `cp -a ~/.config/hypr ~/.config/hypr.bak-$(date +%F)`, and name the copy in your report.
- `/boot` is the EFI partition and is not in the snapshot. limine-snapper-sync keeps what each snapshot needs to boot.

## Snapshots that karchy takes by itself

- snap-pac takes a snapshot before and after every pacman transaction. This includes `karchy update`, Quick install and `karchy-pkg-add`.
- There is no timeline. Nothing takes snapshots on a schedule.
- snapper keeps the 5 newest plain snapshots and the 5 newest important ones (`snapper-cleanup.timer`). A full upgrade (`pacman -Syu`) and changes to the kernel, limine, systemd, mkinitcpio, `karchy` or `karchy-settings` are marked important, so app installs do not push out the pre-update snapshot.
- Because a package change already takes a pre snapshot, a manual snapshot is needed only for changes pacman does not make: edits in `/etc`, services, the bootloader configuration, or a series of package changes that you want to undo as one.

## Take a snapshot before a large change

Run this in a terminal with the user present. It prints the new snapshot's number.

```sh
sudo snapper -c root create --print-number --cleanup-algorithm number --userdata important=yes --description "before <what you are about to change>"
```

- `--cleanup-algorithm number` lets snapper remove the snapshot later by the normal limits. Without it, the snapshot stays until someone deletes it.
- `--userdata important=yes` puts it among the 5 important snapshots, so the next app installs do not remove it.
- Write a description the user will recognize in the boot menu.
- Confirm with `sudo snapper -c root list` that the snapshot exists before you start the change. Tell the user its number.

## List and inspect

```sh
sudo snapper -c root list                 # number, type, date, cleanup, description
sudo snapper -c root status <number>..0   # files that changed between the snapshot and now
sudo snapper -c root diff <number>..0 /etc/<file>   # the change in one file
```

The files of a snapshot are readable as root under `/.snapshots/<number>/snapshot`. To restore one file, copy it from there with `sudo cp -a`. That is the smallest undo: prefer it when one config file is the problem.

## Roll back the whole system

A rollback returns `/` to the snapshot. Packages and `/etc` go back. The home folder stays as it is. Do it only with the user's agreement, and follow these steps in order.

1. Restart. In the Limine boot menu, open `Snapshots`, open the snapshot, and boot `linux-cachyos` inside it. The menu shows each snapshot's number, date and description.
2. Check that the system works. The snapshot runs on a writable layer in memory. Every change outside the home folder is lost at the next boot until you restore.
3. A notification names the running snapshot and offers "Restore this snapshot" (`karchy-snapshot-boot check` at login). The button runs `karchy-snapshot-boot restore` in a terminal. By hand, run `sudo limine-snapper-restore`.
4. In `limine-snapper-restore`, check the number and date, press `r`, and type a description for the backup. The system being replaced is kept as a new snapshot under that description.
5. Reboot. The normal entry now boots the restored system.

- Run `limine-snapper-restore` only from a booted snapshot. It decides what to restore from the kernel command line.
- If the restored system is worse, boot the backup snapshot from `Snapshots` and restore it the same way.
- A snapshot boot reports `systemd-remount-fs.service` as failed. This is expected.
- Do not use `snapper rollback` or `snapper undochange` on the running system. karchy's rollback path is the boot menu and `limine-snapper-restore`.
- An agent cannot drive the boot menu. Give the user steps 1 to 5 with the snapshot's number and description before the restart.

## A kernel problem is not a snapshot problem

If only the new kernel misbehaves, boot `linux-cachyos-lts` from the boot menu. It is the same system with the long-term kernel. Roll back only when the LTS kernel shows the same fault.

## Delete snapshots

Delete snapshots only when the user asks, or when the disk is full and the user agrees.

```sh
sudo snapper -c root delete <number>
```

Never delete the newest pre-update snapshot while the user still judges an update. Space comes back after btrfs cleans up, not at once.

## Secure Boot and recovery

- With Secure Boot on, the boot menu's entry editor is off. The user cannot add kernel parameters for one boot from the menu.
- Snapshot entries are signed with the rest: Limine's hooks sign and re-enroll after every change. Do not edit `/boot/limine.conf` by hand. Change `/etc/default/limine` and run `sudo limine-update`. This is a bootloader change: plan it, and take a snapshot first.
- The install media is not signed. To boot it, the user turns Secure Boot off in the firmware settings and must not erase the keys.
- `karchy-secureboot check` runs at login. If a firmware update cleared the keys, it offers to enroll them again (`karchy-secureboot enroll`, which asks for the password). `karchy-secureboot setup` turns Secure Boot on from Setup Mode. Both change firmware keys: run them only at the user's request.

## Source

`docs/recovery.md` in the karchy repository (github.com/Nulifyer/karchy) has the full recovery procedure, including repair from the install media and the LUKS header backup.
