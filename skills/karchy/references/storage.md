# Storage, bees, disks and kept mounts

Read this before you mount or unmount storage, change `/etc/fstab`, switch background deduplication, check a disk, or change an encryption password. Partitioning, formatting and `/etc/fstab` edits are large changes: plan them with the user first.

## Reading the state

`karchy-settings-storage` is the Settings › Storage page's command. Nothing in it runs as root.

- `karchy-settings-storage status` prints JSON: every disk with its volumes, space and mount points, what karchy keeps mounted, each disk's health, the measured btrfs figures, and current disk-health warnings.
- `karchy-settings-storage shares` prints the network shares kept at `/mnt`, each `connected`, `idle` or `unreachable`. It never waits on a server that is away. Prefer it to `df` or `ls /mnt/<share>`, which can block for about 30 seconds on an unreachable share.
- `karchy-settings-storage bees` prints whether deduplication is on, running, and how far it is.
- `karchy settings storage` opens the page.
- `karchy-drive-info <drive>` prints one drive's size, model and partitions.

## The system disk layout

- Partition 1 is the EFI partition at `/boot`. Partition 2 is LUKS2 with one btrfs filesystem inside.
- The subvolumes are `@ @home @root @srv @cache @log @tmp @swap`. Mount options are `noatime,compress=zstd:1`.
- Do not change the subvolume layout, the system lines in `/etc/fstab`, or the swap file. Snapshots, hibernation and recovery depend on them.

## Space figures

btrfs shares and compresses data, so `du` and `df` disagree. Use the measured figures in `status`.

- A root job measures every night at 04:00 and writes `/var/lib/karchy/storage/measurement.json`. `karchy-settings-storage measure` starts a measurement now.
- "Your files" is what files reference. "Stored on disk" is what those extents take. "Saved by sharing" covers reflink copies and all deduplication, not only bees. "Held only by snapshots" is space that returns when snapper deletes old snapshots.
- When the disk is full, check "Held only by snapshots" before you delete user files. Read `snapshots.md` to remove snapshots.

## bees (background deduplication)

bees deduplicates the system disk as `karchy-bees.service`, with limits set by the package: one thread, idle CPU and I/O. On a laptop it runs on AC power only.

- Switch it with `karchy-settings-storage bees on|off`. No password for the person at the computer. `off` writes `ENABLED=no` to `/etc/karchy/bees.conf` and stops the service. Space already shared stays shared.
- Do not run `systemctl enable|disable karchy-bees.service` yourself. The switch above keeps the config and the service in step.
- karchy's defaults are in `/usr/share/karchy/bees.conf`. The user's `/etc/karchy/bees.conf` is read last and wins. Change options there only when the user asks, and keep the edit small: bees does not start with an option it does not know.
- `on` is refused while the packaged default is `ENABLED=no`. karchy ships that when a kernel release is unsafe with bees. Do not work around it.
- Do not delete bees' state (`.beeshome`). A VM disk image or database is safe: karchy's options keep preallocated space and never rewrite read-only snapshots.

## Mounting

| Need | Command |
| --- | --- |
| Mount or unmount one volume | `karchy-settings-storage mount <device>`, `unmount <device>` |
| Unmount and power off a removable disk | `karchy-settings-storage eject <disk>` |
| Unlock an encrypted volume | `karchy-settings-storage unlock <device>` (opens a terminal for the password) |

USB drives mount by themselves through udisks. Do not add fstab lines for removable drives.

## Kept mounts

A kept mount is a line in `/etc/fstab` that karchy wrote. Use the commands. Do not write those lines by hand.

- Internal data disk: `karchy-settings-storage keep <device>` opens a terminal that runs `karchy-disk-keep <device>`. The disk mounts at `/mnt/<label>` with `nofail`. `karchy-disk-keep --remove <device>` unmounts it and takes the line out again. `karchy-disk-keep --ignore <device>` stops the "new disk" notification for it.
- `karchy-disk-fstab list` shows data partitions that have no fstab line yet. At login `karchy-disks-check` offers them in a notification.
- Network share: `karchy-mount-keep smb://server/share` keeps an SMB share at `/mnt/<share>`. It writes an automount line tagged `# karchy-kept-mount` and the credentials to `/etc/karchy/smb/<server>-<share>.cred`, readable by root only. `karchy-mount-keep --remove [folder]` undoes both.
- `karchy-disk-keep` and `karchy-mount-keep` use sudo and ask questions. Run them in a terminal with the user present. Never read or print a `.cred` file.
- If you must edit `/etc/fstab` for something else, keep `nofail` on every line that is not the system disk. A wrong fstab line is the usual cause of a boot that stops in emergency mode.

## Network shares and sleep

Shares opened in the file manager (gvfs) are disconnected before sleep by `karchy-sleep-shares.service`, because a program reading from one blocks the sleep. They open again from the bookmark after wake. This is expected. Shares kept at `/mnt` stay mounted across sleep. For a share the user works on all the time, suggest a kept mount.

## Disk health

- smartd watches every disk. A btrfs scrub of `/` runs each month (`btrfs-scrub@-.timer`). Warnings land in `/var/lib/karchy/disk-health` and show as notifications that stay until dismissed.
- `karchy-disk-health check` shows warnings not shown before. `karchy-disk-health details <warning>` opens the disk's SMART report or the scrub's result and needs the password.
- `karchy-settings-storage check <mount point>` runs a scrub now in a terminal and says what it found.
- Treat a SMART or scrub warning as urgent. Tell the user to back up first. Do not clear warnings, and do not run `btrfs check --repair`.
- `karchy-disk-speedtest [target-dir]` measures read and write speed. It writes scratch files in the target and removes them.

## Encryption password

`karchy-drive-password` changes a drive's LUKS password. It is interactive and uses sudo. The user must run it and type the passwords. Never take a disk password as an argument, in a file, or in chat. After a change, remind the user to make a new LUKS header backup. `docs/recovery.md` in the karchy repository describes the backup.
