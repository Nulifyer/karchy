# Docs audit: boot chain and disk

Date: 2026-11-16. Scope: Limine and limine-snapper-sync, mkinitcpio (systemd hooks, sd-encrypt, microcode), LUKS2, TPM2, Secure Boot (sbctl, D-31), the kernel command line, the btrfs layout and mount options, snapper and snap-pac, the swap file and zswap (D-10), hibernation (D-32), TRIM on LUKS, scrub, bees (D-30/D-39), `/tmp` (D-11), and data disks in fstab (D-24).

Method: read-only. I compared karchy's files against the Arch Wiki (raw pages fetched 2026-11-16), upstream docs installed on this host (the same package versions karchy installs: limine 12.9.6, limine-mkinitcpio-hook 1.40.0, limine-snapper-sync 1.32.1, snapper 0.13.2, snap-pac 3.0.1, mkinitcpio 42.2, systemd 262.2, btrfs-progs 7.3, bees 0.11), man pages, kernel docs, and upstream sources on GitHub. I also read the kernel configs of linux-cachyos 7.3.3 and linux-cachyos-lts 6.18.60 on this host. Every claim below names its source. Claims I could not confirm are marked **unverified**.

Wiki short names used below:
- Limine wiki: https://wiki.archlinux.org/title/Limine
- mkinitcpio wiki: https://wiki.archlinux.org/title/Mkinitcpio
- dm-crypt wiki: https://wiki.archlinux.org/title/Dm-crypt/Encrypting_an_entire_system, /System_configuration, /Specialties
- Btrfs wiki: https://wiki.archlinux.org/title/Btrfs
- Snapper wiki: https://wiki.archlinux.org/title/Snapper
- Hibernate wiki: https://wiki.archlinux.org/title/Power_management/Suspend_and_hibernate
- Secure Boot wiki: https://wiki.archlinux.org/title/Unified_Extensible_Firmware_Interface/Secure_Boot
- fwupd wiki: https://wiki.archlinux.org/title/Fwupd
- NVIDIA wiki: https://wiki.archlinux.org/title/NVIDIA and https://wiki.archlinux.org/title/NVIDIA/Tips_and_tricks
- fstab wiki: https://wiki.archlinux.org/title/Fstab; NTFS wiki: https://wiki.archlinux.org/title/NTFS; tmpfs wiki: https://wiki.archlinux.org/title/Tmpfs; SSD wiki: https://wiki.archlinux.org/title/Solid_state_drive

## Findings, most severe first

None of the findings is breaks-boot or data-loss on its own. Four are broken features that matter on the real machines.

### F1. Booting a snapshot from the Limine menu gives a read-only root

- **Severity:** broken-feature. Snapshot boot is karchy's recovery path after a bad update.
- **What karchy does:** `system/mkinitcpio.conf.d/karchy.conf:3` sets `HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems fsck)`. It has no overlay hook. snapper's snapshots are read-only (snapper default; karchy's template `system/snapper/root` doesn't change that), so a snapshot entry boots with `/` (including `/etc` and `/var/lib`) read-only. `.agents/STATUS.md` says booting a snapshot entry from the menu has never been tested.
- **What the docs say:**
  - Limine wiki, "Snapper snapshot integration for Btrfs", Enable OverlayFS tip: "For mkinitcpio, manually add the `btrfs-overlayfs` or `sd-btrfs-overlayfs` hook after the `filesystems` hook. Both are provided by limine-mkinitcpio-hook. When using the systemd hooks, use `sd-btrfs-overlayfs`, as `btrfs-overlayfs` is incompatible."
  - Snapper wiki, "Booting into read-only snapshots": "Many services, such as a desktop manager, require a writable /var directory, and will fail to start when booted from a read-only snapshot."
  - `/usr/share/doc/limine-snapper-sync/README.md`, Troubleshooting, "Some display managers fail to boot into read-only snapshots": "Option 1: Use OverlayFS ... This is the recommended solution for two restore methods: replace or rsync." karchy uses `replace` (the default; `/etc/limine-snapper-sync.conf`).
  - The hook is safe on normal boots. `/usr/lib/limine/overlayfs-setup` returns early unless `/sysroot` is a read-only btrfs subvolume whose source path contains `/snapshot`.
- **Fix:** `HOOKS=(base systemd autodetect microcode modconf kms keyboard sd-vconsole block sd-encrypt filesystems sd-btrfs-overlayfs fsck)`, then `limine-update`. The README says only snapshots taken after the change boot with the overlay ("Create a new snapshot (older ones won't work)"), so ship it before the owner's install.
- **Check:** VM. Boot a snapshot entry, then confirm that greetd, Hyprland, NetworkManager and `limine-snapper-restore` work. Also run one full `limine-snapper-restore` (replace) in the VM. It has never been run either.

### F2. Hibernation on the NVIDIA desktop is set up and offered, but early-loaded NVIDIA modules break it

- **Severity:** broken-feature. A failed resume loses the session and any unsaved work. This affects the RTX 5080 desktop. The Framework (AMD) is not affected.
- **What karchy does:**
  - `system/nvidia/mkinitcpio.conf:6` puts `nvidia nvidia_modeset nvidia_uvm nvidia_drm` in the initramfs (karchy-nvidia and karchy-nvidia-580xx).
  - `install/base.sh:182` puts `resume=UUID=… resume_offset=…` on every machine's command line.
  - `bin/karchy-hibernation-available:35` then reports hibernation as available, and the menu and idle code offer it.
- **What the docs say:**
  - NVIDIA wiki, "Early loading": "Early loading the modules will break hibernation, as video memory preservation is enabled by default."
  - NVIDIA/Tips and tricks, "Preserve video memory after suspend": "When using early KMS, i.e. when the loading of `nvidia` module happens in the initramfs, it has no access to `NVreg_TemporaryFilePath` which stores the previous video memory: early KMS should not be used if hibernation is desired."
- **Fix:** pick one of these and record it in a decision:
  - (a) drop the `MODULES+=` early load on NVIDIA machines and keep hibernation. The wiki says "For basic functionality, just adding the kernel parameter should suffice", and modeset is on by default from driver 560.
  - (b) keep early KMS and make hibernation unavailable on NVIDIA machines: no `resume=` from the installer, and `karchy-hibernation-available` returns false when `karchy-hw-nvidia` is true.
  - D-32 only asks for hibernation on laptops, so (b) costs the desktop nothing it was promised.
- **Check:** real hardware (RTX 5080). The VM has no NVIDIA GPU.
- **Related, outside my area (pass to the GPU audit):** `install/setup.sh:93-95` enables `nvidia-suspend/resume/hibernate.service`. NVIDIA/Tips and tricks says: "The aforementioned services are disabled by default on 595+ drivers, as per upstream requirements, as video memory preservation is now handled by kernel suspend notifiers". The repos carry nvidia-utils 620.70.06 (`pacman -Si nvidia-utils`, 2026-11-16).

### F3. Firmware updates through fwupd fail once karchy's Secure Boot keys are enrolled

- **Severity:** broken-feature. BIOS updates for the Framework 13 come through LVFS/fwupd (Framework 13 AMD wiki, "Firmware": "fwupd is support is offered by Framework").
- **What karchy does:** `bin/karchy-update-firmware:13-18` copies the unsigned `/usr/lib/fwupd/efi/fwupdx64.efi` to `/boot/EFI/arch/` and runs `fwupdmgr update`. `install/base.sh:212-225` (Secure Boot) neither signs fwupd's EFI binary nor sets `DisableShimForSecureBoot`.
- **What the docs say:** fwupd wiki, "Secure Boot": "Currently, fwupd relies on shim to chainload the fwupd EFI binary on systems with Secure Boot enabled". For your own keys: `# sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi`, "Then after each update of fwupd, the UEFI executable will be automatically signed, thanks to the sbctl pacman hook", and "Finally, you have to set `DisableShimForSecureBoot` in `/etc/fwupd/fwupd.conf`" under `[uefi_capsule]`.
- **Fix:** in `base_secureboot` (or `karchy-update-firmware` when `KARCHY_SECUREBOOT=yes`), run `sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi` and write `[uefi_capsule]` `DisableShimForSecureBoot=true`. Better as a drop-in if fwupd 2.x reads `/etc/fwupd/fwupd.conf.d/` (**unverified**). The `install … /boot/EFI/arch/fwupdx64.efi` copy came from Omarchy, and no doc I found asks for it. fwupd places its own binary on the ESP (**unverified**), so review whether the copy is still needed.
- **Check:** real hardware (a Framework BIOS capsule). In the VM, OVMF with Secure Boot can show whether `fwupdx64.efi.signed` is used, but it has no capsule to apply.

### F4. Keys are enrolled without the firmware's built-in OEM certificates

- **Severity:** broken-feature, with a brick risk on some firmware. The docs name Framework laptops.
- **What karchy does:** `bin/karchy-secureboot:98` runs `sbctl enroll-keys --microsoft`. The installer runs it too (`install/base.sh:224`). There is no `--firmware-builtin`.
- **What the docs say:**
  - Secure Boot wiki, "Assisted process with sbctl": `# sbctl enroll-keys -m -f`, then this warning: "Some firmware is signed and verified with Microsoft's or your OEM's (for example, Framework laptops) keys when secure boot is enabled. Not validating devices could prevent you from upgrading the firmware, boot other applications (especially Windows), or - in extreme cases - even brick your device. … To enroll without the keys your OEM has built into your PC's firmware, drop the -f option. Only do this if you know what you are doing."
  - sbctl(8) 0.18 (https://man.archlinux.org/man/sbctl.8.en): `-f, --firmware-builtin`: "Enroll signatures from dbDefault, KEKDefault or PKDefault. This is usefull if sbctl does not vendor your OEM certificates, or doesn't include all of them."
  - The Framework 13 wiki ("Secure Boot") says custom keys can be enrolled "without any Option ROM concerns". That covers option ROMs, not OEM-signed firmware tools.
- **Fix:** `sbctl enroll-keys --microsoft --firmware-builtin` when `/sys/firmware/efi/efivars/dbDefault-*` or `KEKDefault-*` exist; plain `--microsoft` otherwise. This adds the OEM's db/KEK and keeps karchy's PK. The desktop board gains the same protection for its vendor tools.
- **Check:** real hardware. Look for `dbDefault`/`KEKDefault` on both machines before installing. OVMF also exposes default-key variables, so the code path can be tested in `karchy-sb`.

### F5. `/root` probably ends up mode 0755, and `/var/tmp` 0755 until first boot

- **Severity:** suboptimal (security). **Unverified:** the VM can confirm it in one command.
- **What karchy does:** `install/disk.sh:55-56` creates every subvolume with `btrfs subvolume create` and mounts them before `pacstrap`. A new subvolume's top directory gets the default directory mode (0755 under umask 022).
- **What the docs and sources say:**
  - The filesystem package wants `/root` at 0750. This host shows `750 /root` (`stat`).
  - pacman only warns when an existing directory's mode differs. libalpm's string is "warning: directory permissions differ on %s, filesystem: %o  package: %o" (`strings /usr/lib/libalpm.so`).
  - systemd's `/usr/lib/tmpfiles.d/provision.conf:20` is `d- /root :0700 root :root -`. tmpfiles.d(5), Mode: "if prefixed with ':', the configured access mode is only applied when creating new inodes, and if the inode the line refers to already exists, its access mode is left in place unmodified." So nothing fixes `/root` later.
  - `/var/tmp` is fixed at the first boot by `q /var/tmp 1777 root root 30d` (`/usr/lib/tmpfiles.d/tmp.conf`, no `:`).
- **Fix:** after `disk_mount`, run `chmod 0700 "$KARCHY_MNT/root"` and `chmod 1777 "$KARCHY_MNT/var/tmp"`, or set the modes right after `btrfs subvolume create`. Check the install log for "directory permissions differ".
- **Check:** VM: `stat -c '%a %n' /root /var/tmp /srv /var/log /var/cache` on an installed guest.

### F6. The `/tmp` drop-in drops systemd's per-user quota

- **Severity:** suboptimal.
- **What karchy does:** `system/systemd/tmp.mount.d/karchy.conf:4` sets `Options=mode=1777,strictatime,nosuid,nodev,size=100%%,nr_inodes=1m`. It replaces systemd 262's `Options=mode=1777,strictatime,nosuid,nodev,size=50%%,nr_inodes=1m,x-systemd.graceful-option=usrquota` (`/usr/lib/systemd/system/tmp.mount`).
- **What the docs say:** tmpfs wiki, "write() failed with EDQUOT": "systemd enables a disk quota on /tmp and /dev/shm by default, and each user gets a quota of 80% of the tmpfs size."
- **Fix:** append `,x-systemd.graceful-option=usrquota` to the drop-in's `Options=`.
- **Check:** VM (`findmnt -no OPTIONS /tmp` shows `usrquota`).

### F7. With Secure Boot off, the firmware's fallback Limine is never updated

- **Severity:** suboptimal.
- **What karchy does:** `install/base.sh:183-188` writes `/etc/default/limine` without `ENABLE_LIMINE_FALLBACK` and runs `limine-install --fallback` once. With Secure Boot on, `95-karchy-limine-fallback` keeps `EFI/BOOT/BOOTX64.EFI` current. With it off, the hook exits at line 23, so the fallback copy stays at the Limine version from install day.
- **What the docs say:** `/usr/share/doc/limine-entry-tool/README.md`, "Default Boot Fallback":
  - `"yes"` means "Always create, update, or overwrite the fallback on each limine-update"
  - `"" or commented out` means "Create the fallback only if it is not present. If a fallback exists, leave it untouched."
  - The same section explains why the fallback matters: "BIOS, firmware, or Windows updates may remove custom Linux UEFI entries".
- **Fix:** when `KARCHY_SECUREBOOT != yes`, add `ENABLE_LIMINE_FALLBACK=yes` to `/etc/default/limine`. Leave it unset under Secure Boot, where the README warns that limine-update doesn't sign the fallback and karchy's hook handles it.
- **Check:** VM. Install without Secure Boot, upgrade `limine`, and compare `cmp /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI`.

### F8. No autodetect-free (fallback) initramfs exists, though the boot order names one

- **Severity:** suboptimal. `BOOT_ORDER` lists entries that never exist, which is cosmetic.
- **What karchy does:** `install/base.sh:186` sets `BOOT_ORDER="*, *lts, *fallback, Snapshots"` and never sets `MKINITCPIO_FALLBACK`. `limine-mkinitcpio-install` builds the fallback image only when `MKINITCPIO_FALLBACK` is `yes` or the kernel's name (`/usr/share/libalpm/scripts/limine-mkinitcpio-install:268`). Both kernels' images therefore pass through `autodetect`, built from the live ISO's view of the hardware.
- **What the docs say:**
  - mkinitcpio wiki, Troubleshooting: "If you transfer your /boot directory to another machine and the boot sequence fails during early userspace, it may be because the new hardware is not detected … To fix, first try choosing the fallback image from your boot loader, as it is not filtered by autodetect."
  - The limine-snapper-sync README, "Fallback initramfs is huge", gives the cost: disable it "if you do not plan to use the same disk on multiple different devices".
- **Fix:** either set `MKINITCPIO_FALLBACK=linux-cachyos-lts`, which gives one rescue image at some ESP cost, or drop `*fallback` from `BOOT_ORDER`. The LTS entry already covers a broken main kernel. It doesn't cover a module missing from autodetect, such as a new NVMe or USB controller after moving the disk.
- **Check:** VM (`limine-list` shows whether a fallback entry exists).

### F9. Data disks: 5 s device timeout, no fsck pass for ext4, no scrub for a btrfs data disk

- **Severity:** suboptimal.
- **What karchy does:** `bin/karchy-disk-fstab:68-74` writes `nofail,x-gvfs-show,x-systemd.device-timeout=5s` with passno `0 0` for every type. A btrfs or ext4 disk gets only `noatime`. `install/base.sh:198` enables `btrfs-scrub@-.timer` for `/` only.
- **What the docs say:**
  - systemd.mount(5), `nofail`: "the boot will continue without waiting for the mount unit". `x-systemd.device-timeout=`: "how long systemd should wait for a device to show up before giving up on an entry". The fstab wiki's external-device example uses `nofail,x-systemd.device-timeout=5` "because the default device timeout is 90 seconds". That is for a disk that may be absent. With `nofail` the boot doesn't wait anyway, so the 5 s only means that a slow internal HDD (3.6 TB, spin-up during SATA probe) is given up on, and the disk stays unmounted for that boot. Whether the drive appears in time is **unverified**.
  - fstab wiki: "`<fsck>` … For other partitions it should be 2, or 0 to disable checking." karchy disables it for ext4, exfat and vfat.
  - Btrfs wiki, Scrub: "Enable the timer with an escaped path, e.g. `btrfs-scrub@-.timer` for / and `btrfs-scrub@home.timer` for /home". Scrub works per filesystem, so a separate btrfs data disk needs its own timer.
- **Fix:**
  - drop `x-systemd.device-timeout=5s` for internal disks (`nofail` already keeps boot from waiting), or raise it to about 30 s
  - use passno 2 for ext4, exfat and vfat
  - for a btrfs data disk, enable `btrfs-scrub@$(systemd-escape -p /mnt/<label>).timer` and consider `compress=zstd:1` to match the system disk
- **Check:** real hardware (the desktop's 3.6 TB disk: `journalctl -b | grep -i 'timed out waiting for device'`).

### F10. A dirty NTFS volume can't be repaired from karchy

- **Severity:** suboptimal.
- **What karchy does:** data disks mount with `ntfs3` (`bin/karchy-disk-fstab:70`). No NTFS userspace tools are installed: none of the PKGBUILDs or `install/packages/base.txt` lists `ntfsprogs` or `ntfs-3g`. `bin/karchy-disk-keep:43` tells the user only about Windows Fast Startup.
- **What the docs say:** NTFS wiki: "There are no userspace utilities alongside the ntfs3 kernel driver. To format partitions and perform maintenance, you can install the ntfsprogs package". In "Unable to mount with ntfs3 with partition marked dirty": "ntfs3 will not mount a partition where the volume is marked dirty without the force option … You can try passing the `--clear-dirty` argument to ntfsfix". Volumes also go dirty after an unclean unplug or crash, not only after Fast Startup. The kernel doc on `force` (https://docs.kernel.org/filesystems/ntfs3.html): "Not recommended for use."
- **Fix:** offer `ntfsprogs` (Arch extra 2026.9.28) when an NTFS data disk exists, and mention `ntfsfix --clear-dirty` in the failure message. The NTFS wiki also says the new in-kernel `ntfs` driver exists "since Linux 7.1" and that "There is no objectively best driver". Keeping ntfs3, which udisks also prefers, is fine.
- **Check:** real hardware or VM (attach an NTFS image marked dirty).

### F11. Five snapshots cover only about two package transactions

- **Severity:** suboptimal. D-09 sets "keep 5" deliberately, so this is a suggestion, not a defect.
- **What karchy does:** `system/snapper/root:8-9` sets `NUMBER_LIMIT="5"` and `NUMBER_LIMIT_IMPORTANT="5"`. snap-pac's default `important_packages` is `[]`.
- **What the docs say:** snap-pac(8): snap-pac makes "the pair of snapshots" (pre and post) per transaction. `important_packages`: "names of packages that if involved in a pacman transaction will add important=yes … Default: []". snapper-configs(5): "The number of normal and important snapshots are counted independently."
- **Fix (optional):** ship `/etc/snap-pac.ini` with `[root]` `important_packages = ["linux-cachyos", "linux-cachyos-lts", "limine", "systemd", "mkinitcpio"]`. Kernel and boot changes then sit in the separate important pool and aren't pushed out by app installs.
- **Check:** VM.

### F12. dm-crypt work queues are left on for an SSD

- **Severity:** suboptimal (performance only, optional).
- **What karchy does:** `install/base.sh:180` sets `rd.luks.options=discard` only.
- **What the docs say:** dm-crypt wiki, Specialties, "Disable workqueue for increased solid state drive (SSD) performance": Cloudflare's research found that "bypassing the queue and writing data synchronously doubled the throughput and cut the SSD drives' IO await operations latency in half". "With LUKS2 you can set `--perf-no_read_workqueue` and `--perf-no_write_workqueue` as default flags for a device by opening it once with the option `--persistent`."
- **Fix (optional):** in `disk_encrypt`, open with `--allow-discards --perf-no_read_workqueue --perf-no_write_workqueue --persistent`. The flags then live in the LUKS2 header, and `rd.luks.options=discard` becomes redundant.
- **Check:** VM for the flags (`cryptsetup luksDump` shows `Flags:`). Real hardware to see any speed gain.

### F13. The mkinitcpio pacman hook from limine-mkinitcpio-hook triggers on fewer paths than mkinitcpio's own

- **Severity:** cosmetic for now; this is an upstream packaging gap. Impact **unverified**.
- **What karchy does:** karchy installs `limine-mkinitcpio-hook`, which ships `/etc/pacman.d/hooks/90-mkinitcpio-install.hook`. A hook there replaces mkinitcpio 42.2's `/usr/share/libalpm/hooks/90-mkinitcpio-install.hook`.
- **What the sources say:** compared on this host, the limine version lacks the stock targets `usr/lib/modprobe.d/`, `usr/lib/systemd/systemd-udevd`, `usr/lib/libcryptsetup.so` and `usr/lib/modules/*/vmlinuz` (it uses `modules.builtin` instead). NVIDIA/Tips and tricks notes that modprobe.d changes need a rebuilt initramfs with early KMS. karchy-nvidia early-loads NVIDIA modules, whose options come from `/usr/lib/modprobe.d`. An nvidia-utils update usually also changes `usr/lib/firmware/*`, which is still a trigger.
- **Fix:** report it upstream (limine-entry-tool / limine-mkinitcpio-hook on GitLab), or have karchy-nvidia ship a small hook that runs `limine-mkinitcpio` on `usr/lib/modprobe.d/*` changes. Resolving F2 option (a) removes the NVIDIA reason.
- **Check:** VM (`pacman -S nvidia-utils` with only modprobe.d changed; not easy to stage).

### F14. TRIM is done twice

- **Severity:** cosmetic.
- **What karchy does:** `install/base.sh:198` enables `fstrim.timer`. btrfs also mounts with `discard=async` by default, and genfstab writes the mount options it sees.
- **What the docs say:** SSD wiki: "If you want to use TRIM, use either periodic TRIM or continuous TRIM." Btrfs wiki: asynchronous discard "is enabled by default as of linux 6.2".
- **Fix:** none needed; the overlap is harmless. Optionally keep `fstrim.timer` for the ESP and the data disks and leave btrfs on `discard=async`.

### F15. The `@swap` mount's "no compression" has no effect

- **Severity:** cosmetic.
- **What karchy does:** `install/disk.sh:67-69` mounts `@swap` with `noatime` only, apparently to avoid compression.
- **What the docs say:** Btrfs wiki, Compression: "Compression mount options are shared across all mount points of the same filesystem (including different subvolumes and bind mounts)". The swap file isn't compressed anyway, because `mkswapfile` makes it NOCOW (Btrfs wiki, Swap file) and "The nodatacow option also disables compression".
- **Fix:** none needed. Drop the special case, or reword the comment so nobody relies on it.

## Decisions that the docs show to be risky

These are deliberate decisions. I'm not proposing to reverse them, only to cover the documented risk.

### R1. Secure Boot leaves no unenrolled fallback loader and no boot-menu editor (D-31, 95-karchy-limine-fallback)

- **The decision:** with Secure Boot on, `EFI/BOOT/BOOTX64.EFI` is kept identical to the enrolled, signed Limine (`system/limine/95-karchy-limine-fallback`). The reason, an unenrolled signed fallback booting any edited config, is sound.
- **What the docs say:**
  - Limine wiki: enrolling "will prevent booting if you modify limine.conf and forget to re-enroll it afterward, due to Limine security restrictions. Disabling Secure Boot does not help in this case. Make sure you have a reliable fallback boot loader (without signing and enrollment) for recovery before enabling this."
  - Upstream `/usr/share/doc/limine/USAGE.md`, "Secure Boot", lists the policies applied "When Limine detects that UEFI Secure Boot is active … and a config BLAKE2B checksum is enrolled". They include "The config editor is unconditionally disabled". It also says "If no config checksum is enrolled, Limine treats Secure Boot as inactive".
  - The two sources disagree on whether disabling Secure Boot restores booting. **Unverified** which one is right for Limine 12.9.
  - The limine-snapper-sync README's rescue step for a snapshot that won't boot ("Press E to edit the kernel_cmdline … add 1") can't be done under Secure Boot.
  - `.agents/STATUS.md` already notes the power-loss window, where the main binary is briefly unsigned.
- **Risk on the owner's machines:**
  - Any kernel-parameter workaround on new hardware (RTX 5080, Framework) must be added from a booted system or the ISO, not from the menu.
  - The ISO doesn't boot with Secure Boot on (Framework 13 wiki: "the official installation image does not support Secure Boot").
- **Recommendation:** test in `karchy-sb`. Corrupt `limine.conf`, turn Secure Boot off in OVMF, and see whether Limine boots. Then write the recovery steps into the docs: firmware Secure Boot off, Arch ISO, `cryptsetup open`, mount `@`, `arch-chroot`, `limine-update`. Fix F1 before relying on snapshot entries. Consider installing without Secure Boot first and enrolling later, once the hardware-specific parameters are settled.

### R2. `/tmp` is sized to all of RAM, and the swap file is sized to RAM (D-11 with D-10/D-32)

- **What the docs say:**
  - Kernel tmpfs doc (https://docs.kernel.org/filesystems/tmpfs.html): "The default is half of your physical RAM without swap. If you oversize your tmpfs instances the machine will deadlock since the OOM handler will not be able to free that memory."
  - systemd-oomd can't reclaim tmpfs pages either.
- **The extra risk on the laptop:** a full `/tmp` can push RAM-sized data into the RAM-sized swap file. The hibernation image then may not fit. The Hibernate wiki says "The suspend image cannot span multiple swap partitions and/or swap files. It must fully fit in one". suspend-then-hibernate then falls back to staying suspended (`SYSTEMD_SLEEP_ACTION=suspend-after-failed-hibernate`, Hibernate wiki).
- **Recommendation:** keep D-11 if the owner wants it, but restore the per-user quota (F6). On laptops, consider a swap file of RAM plus some headroom, or a `/tmp` cap below 100%.

## Checked and consistent with the docs

1. ESP: 4 GiB FAT32 at `/boot` with `fmask=0077,dmask=0077` (`install/disk.sh:29,50,74`). limine-snapper-sync README: "at least 4 GiB is recommended". limine-entry-tool needs FAT32 and at least 1 GiB.
2. GPT types `ef00` (ESP) and `8309` (Linux LUKS) via sgdisk (`install/disk.sh:29-30`).
3. `cryptsetup luksFormat --type luks2` (`install/disk.sh:42`), as in the dm-crypt wiki.
4. `HOOKS` match the dm-crypt wiki's systemd-initramfs line exactly, apart from F1 (`system/mkinitcpio.conf.d/karchy.conf:3`; dm-crypt wiki, "Configuring mkinitcpio").
5. `keyboard` after `autodetect`: the mkinitcpio wiki note asks for it before autodetect when keyboards differ between boots. Here `usbhid`, `hid_generic`, `xhci_pci`, `atkbd` and `i8042` are built into linux-cachyos 7.3.3 (`/proc/config.gz`). The Framework keyboard is i8042 (Framework 13 AMD wiki, "Keyboard"). So nothing is lost.
6. Thunderbolt drop-in: mkinitcpio resolves `KERNELVERSION` before sourcing drop-ins (`/usr/bin/mkinitcpio:1073,1143`), so `modinfo -k` targets the right kernel. `CONFIG_USB4=m` in both kernels.
7. limine-mkinitcpio calls `mkinitcpio` without `-c`, so `/etc/mkinitcpio.conf.d/` drop-ins load (`/usr/share/libalpm/scripts/limine-mkinitcpio-install:185-190`; mkinitcpio wiki on drop-ins).
8. Microcode: `amd-ucode`/`intel-ucode` chosen by CPU vendor, the `microcode` hook after `autodetect` (only this CPU's microcode), and no separate `initrd=` on the command line. Microcode wiki: "mkinitcpio and dracut generate combined initramfs files by default."
9. `rd.luks.uuid=` with `root=/dev/mapper/luks-<uuid>`. dm-crypt/System configuration: "The mapped device name is automatically derived from the UUID … /dev/mapper/luks-XXXX".
10. `rd.luks.options=discard` plus `--allow-discards` at install match dm-crypt/Specialties, "Discard/TRIM support".
11. `rootflags=subvol=/@` and fstab mounts by path with `subvolid=` stripped (`install/base.sh:60`). Btrfs wiki: "It is preferable to mount using subvol=… rather than the subvolid, as the subvolid may change when restoring".
12. genfstab writes `/swap/swapfile none swap defaults` and uses passno 0 for btrfs (arch-install-scripts `genfstab.in`, handle swaps; `fstab-helpers` `fsck_types[btrfs]=0`). That matches the Btrfs and fstab wikis.
13. The swap file is on its own `@swap` subvolume, made with `btrfs filesystem mkswapfile --uuid clear`, on the default single data profile (Btrfs wiki, Swap file: subvolume, NOCOW and preallocation handled).
14. `resume_offset` comes from `btrfs inspect-internal map-swapfile -r` (Hibernate wiki: "For Btrfs, do not try to use the filefrag tool").
15. `resume=UUID=<btrfs fs UUID>` uses persistent naming (Hibernate wiki). With the `systemd` hook, "a resume mechanism is already provided and no further hooks are required".
16. Kernel lockdown is off in both kernels (`CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y`), so Secure Boot doesn't block hibernation (Hibernate wiki: "Enabling kernel lockdown prevents hibernation"; Secure Boot wiki: Arch kernels don't lock down under Secure Boot).
17. zswap is on with zstd. `CONFIG_ZSWAP_DEFAULT_ON=y` and `CONFIG_ZSWAP_COMPRESSOR_DEFAULT="zstd"` in both kernels, so `zswap.enabled=1 zswap.compressor=zstd` is redundant but harmless. No zram, as D-10 decided (Zswap wiki; Hibernate wiki says zram swap can't hibernate).
18. `HibernateDelaySec=2h` with `HandleLidSwitch=suspend-then-hibernate` (`system/laptop/*`) matches systemd-sleep.conf(5).
19. RTC wake for suspend-then-hibernate on AMD s2idle: `rtc_cmos.use_acpi_alarm` is already `Y` by default on this AMD host (upstream commit 3d762e21, https://lkml.iu.edu/hypermail/linux/kernel/2311.0/04594.html). Omarchy's `rtc_cmos.use_acpi_alarm=1` isn't needed. Confirm `cat /sys/module/rtc_cmos/parameters/use_acpi_alarm` on the Framework.
20. limine-snapper-sync: `limine-snapper-sync.service` is enabled (README step 3), snap-pac is installed (README step 4), and its XDG autostart restore notification runs under uwsm (uwsm README: XDG autostart entries become `app-*@autostart.service` units).
21. A nested `/.snapshots` inside `@` differs from the Snapper wiki's suggested `@snapshots`. The limine-snapper-sync README documents `/@/.snapshots` as its auto-detected default and recommends `replace` for "a root subvolume (typical for most Arch-based installations)". Not a defect, but run one restore in the VM (see F1).
22. Separate `@cache`, `@log`, `@tmp`, `@home`, `@srv`, `@root`, and pacman's database kept in `@`, as the Snapper wiki tip recommends. VM images live in `~/VMs` with `chattr +C` (`bin/karchy-feature-vms:44`), not in `/var/lib/libvirt` inside `@`.
23. Snapper template: number cleanup only, no timeline, `snapper-cleanup.timer` enabled. The keys and defaults match snapper-configs(5).
24. `btrfs-scrub@-.timer` enabled for `/` (Btrfs wiki, Scrub); scrub covers the whole filesystem.
25. `fstrim.timer` enabled (SSD wiki, Periodic TRIM); with `--listed-in /etc/fstab` it also covers the ESP and data disks.
26. Limine hooks: `95-karchy-limine-fallback` runs last and its exit code is what limine reports. `run_boot_hooks` returns the last hook's code (`/usr/lib/limine/limine-common-functions:380-396`), so the comment in the hook is right. The pre hook `10-limine-reset-enroll` and post hook `90-limine-enroll-config` are present, as limine-entry-tool's README requires for snapper.
27. sbctl 0.17 and later carry Microsoft's 2023 certificates, including "microsoft option rom uefi ca 2023". GitHub commit 6df94e4c8e "certs: import 2023 Microsoft keys" is contained in tags 0.17 and 0.18; Arch ships 0.18. `--microsoft` therefore covers the RTX 5080's option ROM, which the Secure Boot wiki says needs the 3rd-party CA ("UEFI CA 2011 … and Microsoft UEFI CA 2023 … for … option ROMs").
28. Lifting the immutable flag on efivars before enrolling (`bin/karchy-secureboot:95-97`) matches the Secure Boot wiki's `chattr -i` note.
29. Setup Mode detection by reading byte 4 of `SetupMode-8be4df61…` (`install/lib.sh:189-192`, `bin/karchy-secureboot:67-69`) matches limine's own `check_secure_boot`.
30. Secure Boot is installed last and enrolling is its last action (`install/karchy-install:99-101`), so a failure leaves the machine in Setup Mode and bootable.
31. bees: `/etc/bees/<UUID>.conf` with `UUID=` and `DB_SIZE` matches `beesd.conf.sample`. 256 MiB suits a laptop or desktop system disk (bees `docs/config.md`: "1TB | 256MB | 64K", and "Double or half the optimium size usually works just as well"). D-39's "7.x kernels aren't covered" matches `docs/btrfs-kernel.md`, which recommends up to 6.12 (the 6.18 LTS isn't listed either). Its "one unfixed kernel-hang case" matches the table's "5.4 | - | kernel hang when multiple threads are running LOGICAL_INO and dedupe/clone". bees stays opt-in.
32. bees on AC only: `ConditionACPower=true` plus a `Mains` udev rule that calls `systemctl --no-block` (`system/laptop/*`) is consistent with the upstream `beesd@.service`.
33. `/tmp` tmpfs aging: `q /tmp 1777 root root 10d` (`/usr/lib/tmpfiles.d/tmp.conf`) matches D-11's "files age out after 10 days". `%%` escaping in the drop-in is correct.
34. A trailing `# karchy-data-disk` comment after the passno field parses cleanly: `findmnt --verify --tab-file` on a sample line reported "0 parse errors".
35. NTFS data disks mount as `ntfs3` with `windows_names`, and `nofail` keeps boot going (NTFS wiki; kernel ntfs3 doc).
36. Data-disk detection skips removable/hotplug disks, mounted partitions, ESP, Windows recovery, LUKS and BitLocker (`bin/karchy-disk-fstab:48-59`), so the installer USB and the target disk are never picked.
37. I/O schedulers match CachyOS's `cachyos-settings` 1.4.4 rules on this host (`/usr/lib/udev/rules.d/60-ioschedulers.rules`).
38. TPM2/systemd-cryptenroll isn't used: the disk opens with a passphrase only (D-08). No karchy file references `cryptenroll`, so there is nothing to check against the systemd-cryptenroll docs.
39. Only one Limine config exists, at `$ESP/limine.conf`, as both READMEs require ("remove any alternative Limine config files").

Items checked and consistent: 39. Findings: 15 (four broken-feature, eight suboptimal, three cosmetic), plus 2 decision risks.
