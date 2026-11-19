# When karchy does not boot

Start at the top. Each section is one problem and what to do about it.

karchy's disk layout, which the commands below rely on:

- Partition 1 is the 4 GiB EFI partition, mounted at `/boot`.
- Partition 2 is LUKS2-encrypted. One password unlocks it.
- Inside is one btrfs filesystem with the subvolumes `@ @home @root @srv @cache @log @tmp @swap`.

## Back up the LUKS header now, while everything works

The LUKS header is the first 16 MiB of partition 2. It holds the key slots. If it is damaged, the password no longer opens the disk and the data is lost. A backup of the header is small and takes a second to make.

1. Find the encrypted partition. Its `PARTLABEL` is `karchy` and its type is `crypto_LUKS`:

   ```sh
   lsblk -o NAME,SIZE,FSTYPE,PARTLABEL
   ```

2. Write the backup. Use your partition in place of `/dev/nvme0n1p2`:

   ```sh
   sudo cryptsetup luksHeaderBackup /dev/nvme0n1p2 --header-backup-file karchy-luks-header.img
   ```

3. Move the file off the computer, to the NAS or a USB stick. Delete the local copy.

Keep the backup away from the laptop. A backup on the encrypted disk is lost together with the disk. Treat the file as a secret: with the file and the password, someone can open a copy of the disk.

Make a new backup after you change the disk password. Then destroy the old backup, because the old backup still opens the disk with the old password.

To restore the header, boot the install media (see [Get into the system from the install media](#get-into-the-system-from-the-install-media), step 1) and run:

```sh
cryptsetup luksHeaderRestore /dev/nvme0n1p2 --header-backup-file karchy-luks-header.img
```

Restore a header only to the disk it came from. A header from another disk makes the data unreadable.

## The boot menu

Limine shows its menu for 3 seconds. Press an arrow key to stop the countdown. The menu lists, under "karchy":

- `linux-cachyos`, the normal entry
- `linux-cachyos-lts`, the same system with the older long-term kernel
- `Snapshots`, the system as it was before and after each package change

Enter opens a folder or boots an entry.

## An update broke the system

Boot a snapshot from before the update.

1. In the boot menu, open `Snapshots`.
2. Open the newest snapshot that is older than the update. Each snapshot shows its number, date and the packages that changed.
3. Boot `linux-cachyos` inside it. Type the disk password.

The desktop starts from the snapshot, and a notification says which snapshot is running, with a **Restore this snapshot** button. Changes you make now are temporary: the snapshot runs on a writable layer that is thrown away at the next boot. Your home folder is not part of a snapshot, so your files are as you left them.

If the snapshot works, make it permanent. See the next section.

A snapshot boot reports one failed unit, `systemd-remount-fs.service`. This is expected and harmless.

## Make a snapshot permanent (restore)

Do this while the snapshot from the previous section is running. The quickest way is the **Restore this snapshot** button on the notification: it opens a terminal that asks for your password and runs the restore. By hand:

1. Open a terminal and run:

   ```sh
   sudo limine-snapper-restore
   ```

2. Check the snapshot number and date it shows. Press `r` to restore.
3. Type a description for the backup, such as `before restore`. The broken system is kept under this name as a new snapshot.
4. Answer `Y` to reboot. The normal entry now boots the restored system.

If the restored system is worse, the system you replaced is in `Snapshots` under the description you typed. Boot it and restore it the same way.

## The new kernel does not boot or misbehaves

Boot `linux-cachyos-lts` from the boot menu. It uses the same system with a different kernel.

If the LTS kernel shows the same fault, the cause is not the kernel alone. Boot a snapshot instead.

## The screen stays dark or stops during boot

karchy boots quietly, so that kernel messages do not write over the disk password prompt. The prompt is at the bottom left of a screen with karchy's logo; a wrong password asks again on the next line, and Tab hides the dots. The logo is decoration: if it is missing, or the prompt is a single line on a black screen, the prompt works the same. A failed unit still prints its error. A step that waits longer than 25 seconds prints what it waits for.

To see every message for one boot:

1. In the boot menu, select `linux-cachyos` and press `e`.
2. On the `cmdline:` line, delete `quiet loglevel=3 systemd.show_status=auto`.
3. Press F10 to boot.

The editor is turned off when Secure Boot is on. In that case, use the install media.

If the boot ends at "You are in emergency mode", press Enter. karchy opens a root shell there without a password. `journalctl -xb` shows what failed. A wrong line in `/etc/fstab` is the usual cause.

## Resume from hibernation fails

- **The computer starts fresh instead of resuming.** The session is lost. Nothing else is damaged. `journalctl -b -k | grep -i -E 'hibernat|resume|PM:'` shows the reason.
- **The computer hangs while it resumes.** Hold the power button until it turns off, then start it again. If it hangs again, boot `linux-cachyos-lts`: a different kernel does not load the saved image, so the system starts fresh.

To turn hibernation off until the cause is found, create `/etc/systemd/sleep.conf.d/90-no-hibernate.conf` (karchy's own files there are numbered below 90, so this one wins):

```ini
[Sleep]
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
```

The lid then only suspends. A suspended laptop that stays closed for days drains its battery. Delete the file to turn hibernation on again.

## Get into the system from the install media

Use this when no entry in the boot menu works.

Boot the karchy ISO or the Arch Linux ISO. On the karchy ISO, press Esc at the installer's first question to get a root shell. If Secure Boot is on, turn it off in the firmware settings first, because the ISO is not signed. Do not erase the Secure Boot keys.

1. Find the disk. Partition 1 has the `PARTLABEL` `EFI` and partition 2 has `karchy`:

   ```sh
   lsblk -o NAME,SIZE,FSTYPE,PARTLABEL
   ```

   Set the two partitions. On a laptop with one NVMe disk they are:

   ```sh
   esp=/dev/nvme0n1p1
   luks=/dev/nvme0n1p2
   ```

   Name the partitions by disk, as above. Do not use `/dev/disk/by-label/karchy`: the LUKS partition and the filesystem inside it both have that label.

2. Unlock the disk under the name the installed system uses. Type the disk password:

   ```sh
   name="luks-$(cryptsetup luksUUID "$luks")"
   cryptsetup open "$luks" "$name"
   root=/dev/mapper/$name
   ```

3. Mount the subvolumes as the installer does:

   ```sh
   opts=noatime,compress=zstd:1
   mount -o "$opts,subvol=/@" "$root" /mnt
   mount -o "$opts,subvol=/@home" "$root" /mnt/home
   mount -o "$opts,subvol=/@root" "$root" /mnt/root
   mount -o "$opts,subvol=/@srv" "$root" /mnt/srv
   mount -o "$opts,subvol=/@cache" "$root" /mnt/var/cache
   mount -o "$opts,subvol=/@log" "$root" /mnt/var/log
   mount -o "$opts,subvol=/@tmp" "$root" /mnt/var/tmp
   mount -o noatime,subvol=/@swap "$root" /mnt/swap
   mount -o fmask=0077,dmask=0077 "$esp" /mnt/boot
   ```

   To copy files out, stop here. Your files are in `/mnt/home`. A snapshot is in `/mnt/.snapshots/<number>/snapshot`.

4. Enter the system:

   ```sh
   arch-chroot /mnt
   ```

5. Repair. The usual commands:

   ```sh
   limine-update                      # rebuilds the initramfs and the boot entries (and the signatures under Secure Boot)
   limine-install --fallback          # puts Limine back on the EFI partition and in the firmware's boot list
   snapper --no-dbus -c root list     # lists the snapshots with dates and descriptions
   pacman -Syu                        # finishes an interrupted update (needs the network)
   journalctl -D /var/log/journal -b -0 -p err   # shows the errors of the installed system's last boot
   ```

6. Leave cleanly:

   ```sh
   exit
   umount -R /mnt
   cryptsetup close "$name"
   ```

## The firmware lost the boot entry

A firmware reset or update can clear the firmware's boot list. karchy keeps a copy of Limine at the fallback path (`EFI/BOOT/BOOTX64.EFI`), so the computer still boots from the disk.

To put the named entry back, run this once on the running system:

```sh
sudo limine-install
```

## Add a kernel parameter

For one boot, edit the entry in the boot menu (`e`, see above). To keep the parameter:

```sh
echo 'KERNEL_CMDLINE[default]+=" amdgpu.dcdebugmask=0x10"' | sudo tee -a /etc/default/limine
sudo limine-update
grep -c dcdebugmask /boot/limine.conf
```

Reboot only if the last command prints a number above 0. To undo the change, delete the line from `/etc/default/limine` and run `sudo limine-update` again.
