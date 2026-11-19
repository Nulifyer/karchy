# Storage, bees, disks and kept mounts

Read this before you mount or unmount storage, change `/etc/fstab`, switch background deduplication, check a disk, or change an encryption password. Partitioning, formatting and `/etc/fstab` edits are large changes: plan them with the user first.

## Reading the state

`karchy-settings-storage` is the Settings › Storage page's command. Nothing in it runs as root.

- `karchy-settings-storage status` prints JSON: every disk with its volumes, space and mount points, the partition and layers each volume sits on (`partition`, `layers`), the disk's other partitions (`others`), what karchy keeps mounted, the counted btrfs breakdown when there is one, and current disk-health warnings.
- `karchy-settings-storage usage` prints only the space figures, by filesystem UUID: `fsSize`, `fsUsed`, `fsAvail`, and for btrfs `onDisk` with `data` and `metadata` in bytes. It is instant and needs no root.
- `karchy-settings-storage health` prints each disk's SMART health, wear and temperature, asked of the disks now. No password for the person at the computer.
- `karchy-settings-storage subvolumes` prints, for each mounted btrfs filesystem by UUID, its top-level subvolumes with where each is mounted, and how many snapshots and nested subvolumes it has. btrfs lets only root list them: the person at the computer gets the full list without a password; anyone else gets the mounted ones and `null` counts. No size per subvolume exists: they share the filesystem's space.
- `karchy-settings-storage shares` prints the network shares kept at `/mnt`, each `connected`, `idle` or `unreachable`. It never waits on a server that is away. Prefer it to `df` or `ls /mnt/<share>`, which can block for about 30 seconds on an unreachable share.
- `karchy-settings-storage bees` prints whether deduplication is on, running, and how far it is.
- `karchy settings storage` opens the page.
- `karchy-drive-info <drive>` prints one drive's size, model and partitions.

## The system disk layout

- Partition 1 is the EFI partition at `/boot`. Partition 2 is LUKS2 with one btrfs filesystem inside. An install made without disk encryption has the btrfs filesystem directly on partition 2. `lsblk -o NAME,FSTYPE` shows which: `crypto_LUKS` or `btrfs`. `KARCHY_ENCRYPT` in `/etc/karchy/install.conf` records the install's answer (`encrypted` or `login`).
- A data disk the installer encrypted is one LUKS2 volume with btrfs, mounted at `/mnt/data` (`data2`, …). `/etc/crypttab` opens it at boot with a key file in `/etc/cryptsetup-keys.d` (root only). The install password opens it too. Do not delete the key file or the crypttab line while the disk is in use.
- The subvolumes are `@ @home @root @srv @cache @log @tmp @swap`. Mount options are `noatime,compress=zstd:1`.
- Do not change the subvolume layout, the system lines in `/etc/fstab`, or the swap file. Snapshots, hibernation and recovery depend on them.

## Space figures

btrfs shares and compresses data, so `du` and `df` disagree.

- For how full a disk is, use `karchy-settings-storage usage`. `onDisk.data + onDisk.metadata` is what btrfs has written to the disk (the "Used" of `btrfs filesystem usage`), snapshots included, and `fsAvail` is the room left, an estimate. These are btrfs's own running totals, so they are always current.
- The breakdown of where the space goes is not kept by btrfs and has to be counted from every file's metadata. Nothing counts it in the background. `karchy-settings-storage measure` starts the count (the page's "Measure now"); it takes from half a minute to many minutes and writes `/var/lib/karchy/storage/measurement.json`, which `status` then shows as `measured` with `measurement.time`. Ask the user before starting it on a large disk, and say how old the figures are when you quote them.
- "Your files" is what files reference. "Files on disk" is what those extents take. "Saved by sharing" covers reflink copies and all deduplication, not only bees. "Held only by snapshots" is space that returns when snapper deletes old snapshots.
- When the disk is full, check "Held only by snapshots" before you delete user files. Read `snapshots.md` to remove snapshots.

## bees (background deduplication)

bees deduplicates the system disk as `karchy-bees.service`, with limits set by the package: one thread, idle CPU and I/O. On a laptop it runs on AC power only.

- `dedupBytes` in `karchy-settings-storage bees` is bees' own count of data it has shared since it started (`since`). It restarts with the service and never goes down, so call it an estimate of bees' work, not the space saved now. "Saved by sharing" in the counted breakdown is the exact figure.

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

`karchy-drive-password` changes a drive's LUKS password. On a computer with no encrypted drive it says so and changes nothing; that is not an error, and the login password is changed with `passwd` (Settings › Security starts both). After it changes the system disk's password, it offers the new one to each other encrypted drive the old password still opens (the installer's encrypted data disks). A data disk's key file slot is not a password and is left alone. It is interactive and uses sudo. The user must run it and type the passwords. Never take a disk password as an argument, in a file, or in chat. After a change, remind the user to make a new LUKS header backup. `docs/recovery.md` in the karchy repository describes the backup.
