# When karchy does not boot

Start at the top. Each section is one problem and what to do about it.

karchy's disk layout, which the commands below rely on:

- Partition 1 is the 4 GiB EFI partition, mounted at `/boot`.
- Partition 2 is LUKS2-encrypted. One password unlocks it.
- Inside is one btrfs filesystem with the subvolumes `@ @home @root @srv @cache @log @tmp @swap`.

An install made without disk encryption has the btrfs filesystem directly on partition 2. `lsblk -o NAME,FSTYPE` tells which you have: partition 2 is `crypto_LUKS` on an encrypted install and `btrfs` on a plain one. On a plain install, skip the LUKS header backup below, and in "Get into the system from the install media" skip the unlock step and use partition 2 itself as `root` (the note there says how).

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

karchy asks for the disk password on a splash screen (Plymouth): karchy's mark and a password box. A wrong password turns the box red and asks again. Escape switches between the splash and the boot messages; the password can be typed in either. The splash stays until the desktop appears, and returns at shutdown.

If the splash does not appear, the screen stays black where the password box should be, or keys do nothing there, boot once without it:

1. In the boot menu, select `linux-cachyos` and press `e`.
2. Go to the end of the `cmdline:` line (it wraps over several rows) and add ` plymouth.enable=0`.
3. Press F10 to boot.

The password is then asked as text, at the bottom left of a screen with karchy's name; a wrong password asks again on the next line, and Tab hides the dots. Deleting the word `splash` from the line does the same. If Plymouth stops by itself while it waits for the password, this text prompt takes over without a restart. To turn the splash off for good, delete `splash` from `KERNEL_CMDLINE[default]` in `/etc/default/limine` and run `sudo limine-mkinitcpio`.

The text screen is decoration too: if its logo is missing, or the prompt is a single line on a black screen, the prompt works the same. A failed unit still prints its error. A step that waits longer than 25 seconds prints what it waits for.

To see every message for one boot:

1. In the boot menu, select `linux-cachyos` and press `e`.
2. On the `cmdline:` line, delete `quiet splash loglevel=3 systemd.show_status=auto`.
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

   On an install without disk encryption there is nothing to unlock: set `root=$luks` instead, and leave out `cryptsetup close` at the end.

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

## The login screen does not appear

After logging out (and at boot on an install without disk encryption) karchy shows its own login screen. When it can't start, greetd's text login takes its place by itself: type your username and password there. `journalctl -t karchy-greeter` says why the screen fell back.

To get the text login on purpose:

- for one boot: in the boot menu press `e` on the entry, add ` karchy.greeter=text` at the end of the `cmdline:` line, then F10 (the editor is off under Secure Boot);
- for every boot: `sudo touch /etc/karchy/greeter-text`. Remove the file to get the screen back.

Ctrl+Alt+F2 opens a text console with its own login at any time.

## Someone can't sign in

- **A person forgot their password.** An administrator opens Settings › Users, opens that person's row and chooses "Reset password…" (or runs `sudo passwd <name>`). They can sign in again with the new one.
- **Saved passwords after a reset.** Where the login screen asks for a password (every install but an encrypted one that logs in by itself), the keyring (saved passwords) is locked with the login password. A reset can't give it the new one, so it stays locked with the old: saved passwords can't be read and apps can't save new ones. At their next login the person gets a notification, "Your saved passwords are locked", and Settings › Security shows "Locked". Two ways out, both in their own session:
  - they don't remember the old password: Settings › Security › Saved passwords › Reset… (or `karchy keyring reset`) erases the keyring. What apps saved in it is gone for good: Brave's saved passwords and its sign-ins, VS Code's sign-ins, passwords for network shares, remembered SSH key passphrases. Files, Wi-Fi passwords and the login password are not touched. The page then says "Empty until you log in again" and offers Log out; the next login starts an empty keyring;
  - they remember it: before resetting, `oo7-cli --keyring ~/.local/share/keyrings/v1/login.keyring change-secret` asks for the keyring's secret (the old password) and the new one (the new password). Then log out and in, and nothing is lost.
- **Saved passwords are locked and no password was reset.** `karchy keyring status` says `locked`; `journalctl -b -t karchy-keyring` says what the login did about the keyring. This is what taking the system back to a snapshot can leave, because the keyring is in the home folder, which a snapshot doesn't take back, while the password and the keyring's key are in the system. Don't reset the keyring for this; nothing is lost yet:
  - the computer logs in by itself again, and the keyring got the login password after the snapshot was taken (automatic login was turned off since): log out and in once at the login screen. That login gives the keyring its key back;
  - the password went back to an older one: change it to the newer one again (Settings › Security), then log out and in;
  - the key changed after the snapshot was taken (automatic login was turned off and on again since): the newer key is in the system the restore replaced, which is kept as a snapshot. `sudo cat /.snapshots/<number>/snapshot/etc/credstore/karchy.keyring.$(id -u)` shows it; save it to a file, run `karchy keyring-key import <file>` and restart.
- **Too many wrong tries.** The account unlocks by itself after two minutes. A reset from Settings › Users also clears the count; so does `sudo faillock --user <name> --reset`.
- **The only administrator forgot theirs.** On an encrypted computer that logs in by itself, the desktop still starts; sudo and Settings need the password, so set a new one from the install media: follow [Get into the system from the install media](#get-into-the-system-from-the-install-media) up to `arch-chroot`, then `passwd <name>`. The disk password is a separate one and still opens the disk.
- **Automatic login, by hand.** Whether the computer logs someone in after the disk password is the `[initial_session]` part of `/etc/greetd/config.toml` (`command = "/usr/lib/karchy/session"`, `user = "<name>"`). Settings › Users writes it; taking the part out gives the login screen at every start, and it is read when the computer starts. karchy only offers it on an encrypted disk with one account.

## A data disk the installer encrypted

A disk you chose to "erase and encrypt" at install opens at boot with a key file on the system disk (`/etc/cryptsetup-keys.d/luks-<UUID>.key`, named in `/etc/crypttab`) and is mounted at `/mnt/data`. Your install password opens it as well:

```sh
sudo cryptsetup open /dev/sdb1 data      # asks for the password
sudo mount /dev/mapper/data /mnt/data
```

Use this from the install media, in another computer, or after reinstalling the system disk (the key file is gone with the old system, the password still works). Back up its LUKS header as for the system disk. If the disk is taken out for good, delete its line from `/etc/crypttab` and from `/etc/fstab`; until then a boot goes on without it.

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
