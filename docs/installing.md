# Installing karchy

karchy installs from the stock Arch Linux ISO. The installer erases one disk and sets up:

- a 4 GiB EFI partition
- LUKS2 encryption
- btrfs with the subvolumes `@ @home @root @srv @cache @log @tmp @swap`
- a swap file sized to RAM, with zswap
- `linux-cachyos` plus `linux-cachyos-lts` (and the NVIDIA driver when an NVIDIA GPU is detected)
- Limine, with snapshot boot entries (snapper + snap-pac + limine-snapper-sync)
- NetworkManager and systemd-resolved
- your user, with fish as the login shell

It also clones karchy into `~/.local/share/karchy`.

## From the Arch ISO

1. Boot the Arch ISO in UEFI mode and connect to the network (`iwctl` for Wi-Fi).
2. Run:

   ```sh
   pacman -Sy --noconfirm git
   git clone https://github.com/Nulifyer/karchy.git
   karchy/install/karchy-install
   ```

3. Answer the form: disk (typed confirmation), keyboard, username, one password for both the disk and your login, name and email for git, computer name, timezone, and bees (off by default).
4. When it says it's done, remove the install media and reboot. At boot, type the password at the disk prompt.

Every step is logged to `/var/log/karchy-install.log`, which is copied into the installed system.

## Unattended installs

`karchy-install --config FILE` reads the answers from FILE instead of showing the form. FILE sets `KARCHY_DISK`, `KARCHY_USER`, `KARCHY_PASSWORD`, `KARCHY_HOSTNAME` and `KARCHY_TIMEZONE`, and optionally `KARCHY_KEYMAP`, `KARCHY_FULL_NAME`, `KARCHY_EMAIL` and `KARCHY_BEES`. `tests/vm-install.conf` is the VM test example; its credentials are for throwaway VMs only.

## Testing in a VM

```sh
tools/vm fetch
tools/vm new --name inst
tools/vm run --name inst --iso
# in the VM:
mkdir -p /root/src /mnt/karchy
mount -t 9p -o trans=virtio,version=9p2000.L,ro karchy /mnt/karchy
cp -r /mnt/karchy/. /root/src/ && umount /mnt/karchy
/root/src/install/karchy-install --config /root/src/tests/vm-install.conf
# then stop the VM and boot it without --iso
```

The installer clones the committed `HEAD` of the checkout it runs from, so commit before testing.

## Known limitations

- **Desktop:** the base install has no desktop yet. Desktop setup is the next phase 1 step.
