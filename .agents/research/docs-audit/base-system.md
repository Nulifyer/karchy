# Docs audit: base system, security and updates

Date: 2026-11-16. Repo state: `main` at `7bfe00a`. Read-only audit; no file except this report was changed.

Scope: pacman.conf and repository order, signing and keyrings, mirror ranking, package cache, `karchy update`, snap-pac, sudo and faillock, sysctl, journald, coredumps, OOM handling, linux-firmware, microcode, locale/keymap/console font, timesyncd, ufw, AppArmor, user groups, and the pacstrap install (`install/base.sh`, `install/setup.sh`).

## How the sources were read

- Arch Wiki pages were fetched as raw wikitext (`https://wiki.archlinux.org/index.php?title=PAGE&action=raw`) on 2026-11-16. Citations below give the page URL and section; the quoted text is copied from the raw page.
- CachyOS: https://wiki.cachyos.org/features/optimized_repos/ (page dated "Last updated: Nov 14, 2026") and CachyOS's own repo script from https://mirror.cachyos.org/cachyos-repo.tar.xz (`cachyos-repo.sh`).
- pacman source at tag v7.1.0 (`src/pacman/callback.c`, `src/pacman/util.c`, `lib/libalpm/deps.c`, `etc/makepkg.conf.in`) and `pacstrap.in` from gitlab.archlinux.org.
- Man pages installed on this host (systemd 262.2, pacman 7.1.0, pacman-contrib 1.13.1, snapper 0.13.2, snap-pac 3.0.1).
- Package facts from this host's sync databases (read-only `pacman -Si`/`-Sl`/`-Ql`) and from the CachyOS `pacman-7.1.0.r9.g54d9411-6` package in this host's cache, extracted into the scratchpad. The host runs CachyOS, so its sync databases list both `[cachyos]` and Arch's repositories.

Severity scale: breaks-boot/data-loss, broken-feature, suboptimal, cosmetic. No breaks-boot or data-loss finding came up.

---

## Findings

### F1. The desktop keyboard layout never follows the installer's keyboard choice

- **Severity:** broken-feature. It affects anyone who picks a non-US keymap. With one password for LUKS and login (D-08), a password that contains a character on a different key in the two layouts unlocks the disk, but then fails at the lock screen and in sudo inside Hyprland.
- **What karchy does now:** `install/base.sh:129` writes only `KEYMAP=$KARCHY_KEYMAP` to `/etc/vconsole.conf`. Hyprland's layout comes from `XKBLAYOUT` in that same file (`default/hypr/keyboard.lua:1-3`, `35-37`, `45-53`; `config/hypr/input.lua` uses `keyboard.xkb(...)`) and falls back to `"us"` when the variable is missing. Nothing in `install/`, `bin/` or `system/` writes `XKBLAYOUT` (grep found it only in `default/hypr/*.lua`). Omarchy's provisioning, where this Lua came from, does write it: `reference/omarchy-v4.5.0/bin/omarchy-provision-owner:563-623` runs `systemd-firstboot --keymap`, then adds `XKBLAYOUT=` for keymaps that `kbd-model-map` doesn't cover.
- **What the docs say:**
  - https://wiki.archlinux.org/title/Linux_console/Keyboard_configuration#Persistent_configuration: "The `XKB*` variables in `/etc/vconsole.conf` are for Xorg/Keyboard configuration."
  - `localectl(1)`, `set-keymap`: "the selected setting is also applied as the default system keyboard mapping of X11, after converting it to the closest matching X11 keyboard mapping."
  - https://wiki.archlinux.org/title/Installation_guide#Configure_the_system (note): "Some systemd tools such as hostnamectl, localectl and timedatectl cannot be used inside a chroot".
  - That conversion table ships as `/usr/share/systemd/kbd-model-map`. On this host it maps, for example, `uk → gb pc105`, `de-latin1 → de pc105` and `fr → fr pc105`.
- **Fix:** in `base_locale`, look up the chosen keymap in the target's `/usr/share/systemd/kbd-model-map` and append `XKBLAYOUT`, `XKBMODEL`, `XKBVARIANT` and `XKBOPTIONS`. For keymaps the table lacks, carry over Omarchy's `keyboard_xkb_settings` fallback (colemak, cz, bg-cp1251 and the rest). Then fail the step unless the file reads back with `XKBLAYOUT` set, as Omarchy does.
- **Check:** VM. Install with `KARCHY_KEYMAP=de-latin1`, then confirm that `grep XKB /etc/vconsole.conf` shows `de` and that `hyprctl devices` reports layout `de`.

### F2. Firmware updates through fwupd will not apply on a Secure Boot install

- **Severity:** broken-feature, but only for machines that took the Secure Boot step (D-31).
- **What karchy does now:** `bin/karchy-update-firmware:13-14` copies the unsigned `/usr/lib/fwupd/efi/fwupdx64.efi` to `/boot/EFI/arch/fwupdx64.efi`, then runs `fwupdmgr update`. Nothing signs the fwupd EFI binary with the sbctl keys, and nothing sets `DisableShimForSecureBoot`. A grep for `fwupd` across `bin/`, `system/`, `install/` and `packaging/` finds only this script and the `karchy-desktop` dependency. karchy installs no shim.
- **What the docs say:** https://wiki.archlinux.org/title/Fwupd#Secure_Boot:
  - "Currently, fwupd relies on shim to chainload the fwupd EFI binary on systems with Secure Boot enabled".
  - Under "Assisted process with sbctl": "`# sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi` … after each update of fwupd, the UEFI executable will be automatically signed, thanks to the sbctl pacman hook".
  - Then: "Finally, you have to set `DisableShimForSecureBoot` in `/etc/fwupd/fwupd.conf` … `[uefi_capsule]` `DisableShimForSecureBoot=true`".
- **Fix:** in `base_secureboot`, after the keys are created, run `sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi`. Ship a `[uefi_capsule] DisableShimForSecureBoot=true` drop-in. fwupd 2.x reads `/etc/fwupd/fwupd.conf`; check whether it also reads a `.d` directory before choosing a drop-in path, because `fwupd.conf` belongs to the fwupd package. Drop the manual copy into `EFI/arch`: fwupd 1.9+ stages its own binary on the ESP. Unverified: whether fwupd 2.1.9 still needs `EFI/` to exist, which it does on karchy's ESP.
- **Check:** needs real hardware for an actual capsule update, such as the Framework's BIOS. A Secure Boot VM (`tools/vm --secureboot`) can show the plugin's state with `fwupdmgr get-devices` and `fwupdtool get-plugins`, and the signed file with `sbctl verify`.

### F3. `karchy update`'s advice for merging .pacnew files doesn't work on karchy

- **Severity:** broken-feature (small).
- **What karchy does now:**
  - `bin/karchy-update:270` prints `Merge them with: sudo DIFFPROG='code --wait --diff' pacdiff`.
  - The notification at `:272` says `Run: sudo pacdiff`.
- **What the docs say:**
  - `pacdiff --help` (pacman-contrib 1.13.1): "DIFFPROG override the diff program (default: 'vim -d', or 'nvim -d' if EDITOR=nvim)". karchy installs neither vim nor neovim (D-58: micro), so `sudo pacdiff` → (V)iew fails.
  - `pacdiff(8)`: "-s, --sudo Use sudo and sudoedit to merge/remove files". In `/usr/bin/pacdiff:122-123` this runs `SUDO_EDITOR="$diffprog" sudoedit`, so the diff program runs as the user.
  - VS Code started as root refuses with "You are trying to start Visual Studio Code as a super user which isn't recommended… add the argument `--no-sandbox` and specify an alternate user data directory" (quoted in https://bbs.archlinux.org/viewtopic.php?id=283358; forum source, not VS Code's docs).
- **Fix:** print and notify `DIFFPROG='code --wait --diff' pacdiff -s`, run without sudo in front. If VS Code was removed (D-71), fall back to `micro`, which cannot diff, or to `diff -u` with a view-only hint.
- **Check:** VM. Edit `/etc/mpv/mpv.conf`, reinstall karchy-settings, then run the printed command.

### F4. No emergency or rescue shell: root is locked and nothing forces sulogin

- **Severity:** suboptimal (recovery). An `fstab` or btrfs problem that drops boot into emergency mode leaves you with "the root account is locked" and no shell. The fix is then a snapshot entry or the ISO.
- **What karchy does now:** `install/base.sh:139` runs `passwd --lock root`. No `rescue.service` or `emergency.service` drop-in exists (`system/systemd/` has none).
- **What the docs say:**
  - https://wiki.archlinux.org/title/Sudo#Disable_root_login: "In case of system emergency, the recovery prompt is going to ask you for a root password, making it impossible to log into recovery shell. To automatically unlock the root account in case of emergency add `SYSTEMD_SULOGIN_FORCE=1` environment variable to `rescue.service` using a drop-in file".
  - https://wiki.archlinux.org/title/Mkinitcpio (systemd hook note): "The systemd hook disables the root account. To enable the emergency shell, temporarily add `SYSTEMD_SULOGIN_FORCE=1` to the kernel parameters."
  - The trade-off, https://wiki.archlinux.org/title/Security#Disable_emergency_shell: the emergency shell "is also a gadget that an attacker can use to access secure resources such as the TPM". karchy unlocks with a passphrase, not the TPM, and the emergency shell in the real root only appears after the disk is unlocked.
- **Fix:** ship `/usr/lib/systemd/system/rescue.service.d/10-karchy-sulogin.conf` and the same for `emergency.service`, each with `[Service] Environment=SYSTEMD_SULOGIN_FORCE=1`. If TPM unlock is ever added, revisit this.
- **Check:** VM. Boot with `systemd.unit=emergency.target` and confirm a root shell opens.

### F5. Snapshot retention keeps the pre-update snapshot only until the next app install

- **Severity:** suboptimal (rollback). The "before the update" boot entry that `karchy update`'s error message points to can already be gone.
- **What karchy does now:** `system/snapper/root:6-9` sets `NUMBER_LIMIT="5"` and `NUMBER_MIN_AGE="0"`. One `karchy update` runs up to three pacman transactions: the keyrings (`bin/karchy-update:236`), `-Syu` (`:246`), and paru's install of AUR builds (`:255`). Each transaction gets a snap-pac pre/post pair, so one update makes up to 6 snapshots. After the next cleanup, one more Quick install pair pushes out the `-Syu` pre snapshot.
- **What the docs say:**
  - `snapper-configs(5)`, NUMBER_LIMIT: "Defines how many snapshots the number cleanup algorithm should keep. The youngest snapshots will be kept." And: "The number of normal and important snapshots are counted independently."
  - `snap-pac(8)`: "important_commands - list of strings; parent commands that will add important=yes to the snapper userdata for the pair of snapshots". Its example: `[root] important_commands = ["pacman -Syu"]`.
- **Fix:** ship `/etc/snap-pac.ini` with `important_packages = ["linux-cachyos", "linux-cachyos-lts", "systemd", "glibc", "pacman"]` and `important_commands` matching `pacman -Syu --noconfirm`. Check in the VM how snap-pac matches the parent command. `NUMBER_LIMIT_IMPORTANT=5` then keeps the last five upgrade pairs apart from app installs. Raising `NUMBER_LIMIT` to 10 also works, at the cost of disk use.
- **Check:** VM. Run `karchy update`, then install two apps from Quick install, run `snapper-cleanup.service`, and look at `snapper list`.

### F6. AUR updates are built without review and without rebuild checks

- **Severity:** suboptimal (security).
- **What karchy does now:** `bin/karchy-update:255` runs `paru -Sua --noconfirm --skipreview`, so changed PKGBUILDs and `.install` files are built and installed with root rights without being shown. Nothing checks for AUR packages that a repository library bump broke.
- **What the docs say:** https://wiki.archlinux.org/title/Arch_User_Repository:
  - "Carefully check the PKGBUILD, any .install files, and any other files in the package's git repository for malicious or dangerous commands."
  - "If packages in the official repositories are updated, you will need to rebuild any AUR packages that depend on those libraries. The checkrebuild tool and rebuild-detector …"
- **Fix:** drop `--skipreview` and let paru show its diff, which needs a terminal (karchy update already runs in one). Or keep it for the AUR packages karchy itself ships and review the rest. After step 4, run `checkrebuild` (from rebuild-detector) and list what needs a rebuild.
- **Check:** VM.

### F7. Sync-then-install patterns that the Arch docs call partial upgrades

- **Severity:** suboptimal. A mirror sync during the install window can pair new packages with an older base. A failed channel switch leaves synced databases on a system that wasn't upgraded.
- **What karchy does now:**
  - `install/setup.sh:35`: `in_target pacman -Sy --needed --noconfirm --asdeps …`, then `pacman -S` at `:36` and `:44`. The target was pacstrapped minutes earlier, so this sync can pull a newer database than the installed base.
  - `install/base.sh:37-39` and `install/form.sh:36`: `pacman -Sy`, then `pacman -S jq` / `gum` on the live ISO. The ISO is thrown away, but on an old ISO a newly built `jq` or `gum` can need a newer glibc than the ISO has. Unverified for current builds.
  - `bin/karchy-channel:54-56`: on failure, `restore()` runs `pacman -Syy` and stops. `:69` and `:81` sync, then `-Su`. A failure in between leaves new databases without the upgrade. Quick install and `karchy-pkg-add` then install against them with plain `-S`.
- **What the docs say:** https://wiki.archlinux.org/title/System_maintenance#Partial_upgrades_are_unsupported:
  - "Do not use: `pacman -Sy package`, `pacman -Sy` followed by `pacman -S package` (instead, `-Su` should be used in the installation of the package)".
  - Note: "If `pacman -Syu` fails to complete the upgrade (i.e. the `-Su` part), the error must be resolved and the upgrade operation completed before other package management operations".
- **Fix:**
  - `setup.sh:35`: use `pacman -Syu --needed --noconfirm --asdeps …`.
  - `karchy-channel` `restore()`: after restoring the server file, run `pacman -Syyu --noconfirm` or leave the databases alone. Also set a flag that Quick install and `karchy update` read to say "finish the update first".
  - Live ISO: fine as long as the installer asks for a current ISO. Alternatively, install `jq` and `gum` with `-Syu` on the live system, which costs RAM there.
- **Check:** VM.

### F8. Updates run without the Arch news check, and pacman's notices scroll past

- **Severity:** suboptimal.
- **What karchy does now:** `bin/karchy-update:209-221` previews and asks, then `:246` runs `pacman -Syu --noconfirm`. Nothing shows Arch news. Messages from install scriptlets ("you must now …") pass by in the terminal, and the summary doesn't repeat them.
- **What the docs say:** https://wiki.archlinux.org/title/System_maintenance#Read_before_upgrading_the_system:
  - "Before upgrading, users are expected to visit the Arch Linux home page to check the latest news … When updates require out-of-the-ordinary user intervention … an appropriate news post will be made." It also suggests hooks such as `informant`.
  - #Act on alerts during an upgrade: "be sure to pay attention to the alert notices provided by pacman."
- **Fix:**
  - In step 1 (no root), fetch https://archlinux.org/feeds/news/ and list the titles of posts newer than the last update's timestamp (kept in `$state_dir`). Make a new post change the default choice to "Show details" or ask once more.
  - After step 3, print the `ALPM-SCRIPTLET` lines that `/var/log/pacman.log` gained during the run.
- **Check:** VM.

### F9. Core dumps are kept inside root snapshots

- **Severity:** suboptimal (disk use and privacy; a dump of a browser or the keyring daemon holds secrets).
- **What karchy does now:** no `coredump.conf` drop-in. Dumps go to `/var/lib/systemd/coredump`, which is on `@` (`install/disk.sh:6-13` makes `@cache`, `@log` and `@tmp` subvolumes, but not `/var/lib/systemd/coredump`). snap-pac snapshots of `@` keep dumps after systemd deletes them.
- **What the docs say:**
  - `coredump.conf(5)`: `Storage=` "When 'external' (the default), cores will be stored in /var/lib/systemd/coredump/". MaxUse "defaults to 10% of the total disk size, capped at 4GiB".
  - https://wiki.archlinux.org/title/Snapper#Suggested_filesystem_layout: "Consider creating subvolumes for other directories that contain data you do not want to include in snapshots and rollbacks of the @ subvolume, such as /var/cache … and other data directories under /var/lib/."
- **Fix:** create `/var/lib/systemd/coredump` as a nested subvolume at install, since snapshots don't descend into nested subvolumes. Or ship `/usr/lib/systemd/coredump.conf.d/10-karchy.conf` with `MaxUse=1G`. Either is cheap.
- **Check:** VM. Run `kill -SEGV` on a test process, take a snapshot, and look in `/.snapshots/N/snapshot/var/lib/systemd/coredump`.

### F10. The install stops if a key server is down

- **Severity:** suboptimal (install reliability on real hardware day).
- **What karchy does now:** `install/base.sh:18-21` fetches the Omarchy key from `keys.openpgp.org` and the CachyOS key from `keyserver.ubuntu.com`. Any failure aborts the step. karchy's own key already ships with the installer (`:22-29`).
- **What the docs say:** https://wiki.archlinux.org/title/Pacman/Package_signing#Adding_unofficial_keys gives two ways to add a key: receive it from a key server, or "If the key is found at a link, download it and run `pacman-key --add /path/to/downloaded/keyfile`" and then lsign it. CachyOS's own script uses the key server too (`cachyos-repo.sh:156-157`).
- **Fix:** commit both public keys next to `packaging/keyring/karchy.gpg`, check their fingerprints (they match: Omarchy's script `bin/omarchy-update-keyring:12` and CachyOS's docs and script `F3B607488DB35A47`), and add them with `pacman-key --add`. Fall back to the key server only when the file is missing.
- **Check:** VM, with the key servers blocked in the guest.

### F11. No `sof-firmware`, which many laptops need for audio

- **Severity:** suboptimal for karchy in general. It is not needed on the owner's two machines.
- **What karchy does now:** `install/packages/base.txt:10` has `linux-firmware` only. Nothing adds `sof-firmware` or `linux-firmware-marvell`.
- **What the docs say:**
  - https://wiki.archlinux.org/title/Installation_guide#Install_essential_packages: "specific firmware for other devices not included in linux-firmware (e.g. sof-firmware for onboard audio, linux-firmware-marvell for Marvell wireless …)". The Arch ISO itself carries both (`archiso/configs/releng/packages.x86_64` lines 55 and 103).
  - The Framework 13 AMD 7040 wiki page lists audio `1002:1640` as working, with no SOF note: https://wiki.archlinux.org/title/Framework_Laptop_13_(AMD_Ryzen_7040_Series).
- **Fix:** add `sof-firmware` to the detected tier when the machine has an Intel or AMD audio DSP (`/sys/bus/pci/drivers/sof-audio-pci-intel-*` or the `snd_sof*` modaliases), or install it always (about 10 MB).
- **Check:** real hardware (an Intel laptop); not the owner's machines.

### F12. The first system update swaps zlib for CachyOS's zlib-ng-compat

- **Severity:** cosmetic. It works, but the base install differs from the steady state, and the first update has an unexpected replacement in it.
- **What karchy does now:** `install/packages/base.txt` pulls `zlib` from `[core]` during pacstrap. `[cachyos]` carries `zlib-ng-compat 2.3.3-2` with "Provides: zlib libz.so=1-64; Conflicts With: zlib; Replaces: zlib" (host sync DB). pacstrap doesn't apply `Replaces`, so the first `-Syu` asks "Replace zlib with cachyos/zlib-ng-compat? [Y/n]". In `karchy update`, `--noconfirm` takes the default Y. The preview counts the two new packages as system components without mentioning the swap.
- **What the docs say:**
  - libalpm resolves a dependency from the target list first (`lib/libalpm/deps.c` v7.1.0, line 818: "check if one of the packages in the [*packages] list already satisfies this dependency"). It then takes literal names before providers (line 645, "1. literals").
  - Replacements are applied only in a sysupgrade (`sync.c`, `check_replacers`).
  - `callback.c:453-456` asks `Replace %s with %s/%s?` with `yesno`, so the default is Y.
  - The old multilib concern is closed: Arch issue lib32-zlib#1 ("Incompatibility with zlib-ng-compat", closed 2024-12-05), and `multilib/lib32-zlib 1.4-1` now depends on plain `zlib`.
- **Fix:** add `zlib-ng-compat` to `base.txt`, so pacstrap installs it as the zlib provider from the start.
- **Check:** VM. After install, `pacman -Qi zlib` should say not found and `checkupdates` should show no replacement.

### F13. Every pacman-mirrorlist update produces a .pacnew that `karchy update` flags

- **Severity:** cosmetic.
- **What karchy does now:** `bin/karchy-mirrors-rank:80-92` rewrites `/etc/pacman.d/mirrorlist`. That file is a backup file of `pacman-mirrorlist` (`pacman -Qii pacman-mirrorlist`: "Backup Files : /etc/pacman.d/mirrorlist [modified]"), so each package update leaves `mirrorlist.pacnew`. `bin/karchy-update:266-273` then warns about it and sends a notification every time.
- **What the docs say:** `pacman(8)`, HANDLING CONFIG FILES: when the original, current and new files all differ, pacman keeps the current file and installs the new one with a `.pacnew` extension. https://wiki.archlinux.org/title/Mirrors#Sorting_mirrors recommends a ranking tool, whose output supersedes the stock list.
- **Fix:** after a successful ranking, `karchy-mirrors-rank` removes `mirrorlist.pacnew`, since the ranking supersedes it. Or `karchy update` leaves `/etc/pacman.d/mirrorlist.pacnew` out of the count while `karchy-mirrors.timer` is enabled.
- **Check:** VM.

### F14. AUR builds use CachyOS's `-march=native -O3` flags; the drop-in's comment says Arch's

- **Severity:** cosmetic (documentation). Behaviour is acceptable for local builds.
- **What karchy does now:** `system/makepkg.conf.d/karchy.conf:1-3` says "Arch's /etc/makepkg.conf stays as shipped". Because `[cachyos]` comes first, the installed `pacman` package is CachyOS's (STATUS.md confirms this in the VM), and its `/etc/makepkg.conf` is CachyOS's.
- **What the docs say:** the CachyOS `pacman-7.1.0.r9.g54d9411-6` package's `etc/makepkg.conf` has `CFLAGS="-march=native -O3 -pipe …"` (line 46), `LTOFLAGS="-flto=auto"` (52) and `COMPRESSZST=(zstd -c -T0 -9 -)` (149). Arch's (`archlinux/packaging/packages/pacman` `makepkg.conf`) has `CFLAGS="-march=x86-64 -mtune=generic -O2 …"`. `makepkg.conf(5)` loads `/etc/makepkg.conf.d/*.conf` after it.
- **Fix:** correct the comment to say AUR builds are tuned for this CPU. If Arch's flags are wanted, set `CFLAGS`, `CXXFLAGS` and `LTOFLAGS` in the drop-in.
- **Check:** VM (`makepkg --printsrcinfo` isn't enough; build a small AUR package and read its `.BUILDINFO`).

### F15. Small inconsistencies in faillock and oomd

- **Severity:** cosmetic.
- **What karchy does now:**
  - `system/pam.d/karchy-lock-password:4,7` locks for `unlock_time=120`. `install/setup.sh:71` changes only `deny` in `/etc/security/faillock.conf`, so sudo, login and polkit keep the default 600 s on the same tally. After ten wrong tries the lock screen frees up after 2 minutes, but sudo stays locked for 10.
  - `default/systemd/user/app.slice.d/10-oomd.conf:10-13` says swap kill "uses the global SwapUsedLimit (90%) from /etc/systemd/oomd.conf.d/10-karchy.conf". That file doesn't set it; 90% is systemd's default.
- **What the docs say:**
  - https://wiki.archlinux.org/title/Security#Lock_out_user_after_three_failed_login_attempts: "`unlock_time` — the lockout time (in seconds, default 10 minutes)".
  - `oomd.conf(5)`: SwapUsedLimit "Defaults to 90%".
- **Fix:** set `unlock_time = 120` in faillock.conf too, or drop it from the lock-screen PAM file. Reword the oomd comment.
- **Check:** VM.

### F16. The console text is small on the Framework's HiDPI panel (unverified)

- **Severity:** cosmetic. Unverified: I couldn't confirm which font the kernel or `systemd-vconsole-setup` picks without `FONT=`.
- **What karchy does now:** `install/base.sh:129` writes no `FONT=` or `FONT_SCALE=`. The LUKS prompt and TTYs use the default font on a 2256×1504 or 2880×1920 13.5" panel.
- **What the docs say:**
  - `vconsole.conf(5)` (systemd 262): "FONT_SCALE= Specifies a font scaling factor … Specifying '2' or '200%' doubles the font size … Added in version 262."
  - https://wiki.archlinux.org/title/Installation_guide#Set_the_console_keyboard_layout_and_font suggests `setfont ter-132b` for HiDPI.
  - The CachyOS kernel is built with `CONFIG_FONT_TER16x32=y` (host `/proc/config.gz`).
- **Fix:** on laptops with more than about 200 PPI (read the EDID size from `/sys/class/drm/*/edid`, or just on Framework), write `FONT_SCALE=200%` or `FONT=ter-132b` (needs `terminus-font`). The initramfs is rebuilt later by `limine-update`, so the LUKS prompt picks it up.
- **Check:** real hardware (Framework 13).

---

## Decisions with documented risk (flagged separately; not errors)

- **D-45, `[cachyos]` first: Arch's own signing keyring comes from CachyOS.**
  - `[cachyos]` carries `archlinux-keyring 1:20260909-1` (packager CachyOS, built 10 Sep 2026), shadowing `core/archlinux-keyring 20260909-1` (Christian Hesse, 09 Sep). The trust anchor for every Arch package therefore updates only when CachyOS rebuilds it.
  - CachyOS also gives several rebuilds an epoch (`mesa 3:26.2.6` against Arch's `1:26.2.7`, `linux-firmware 1:`). `pacman.conf(5)`: "repositories listed first will take precedence over those listed later in the file when packages in two repositories have identical names, regardless of version number." Repo order already gives CachyOS's copy priority, and the epochs mean that removing `[cachyos]` later needs `pacman -Suu` plus `pacman -Qqn | pacman -S -` (CachyOS docs, "Uninstalling CachyOS Repositories").
  - The CachyOS docs also warn: "Installing the CachyOS Pacman will install a forked pacman … If you want to avoid this, don't add the 'cachyos' repository" (https://wiki.cachyos.org/features/optimized_repos/).
  - D-45 says CachyOS's builds replace Arch's "where it has them", so this is intended. The keyring part is the piece worth knowing. pacman 7.1 fetches unknown keys over WKD (https://wiki.archlinux.org/title/Pacman/Package_signing#Upgrade_system_regularly: "For an unknown key, pacman will attempt to import the key using WKD first"), which softens a lag.
- **D-45 "(generic)" repositories leave CachyOS's CPU-tuned builds unused.**
  - CachyOS docs: "x86-64-v3: 5%-20% performance uplift compared to x86-64", and v4 or Zen 4/5 builds where supported.
  - The Framework 13 AMD (Ryzen 7040 is Zen 4, Ryzen AI 300 is Zen 5) qualifies for `[cachyos-znver4]`. CachyOS's script picks it when `gcc -march=native` reports znver4 or znver5 (`cachyos-repo.sh:111-113, 172-173`).
  - For the RTX 5080 desktop it depends on the CPU. CachyOS: "Intel 12th gen (Alder Lake) and newer CPUs may report x86-64-v4 support, but in practice they cannot run AVX-512 … these CPUs should be treated as x86-64-v3 only."
  - The generic repo is a documented, valid choice ("If your CPU only supports x86-64, then add the [cachyos] repositories"). Changing it is a user decision.
- **D-62, `--noconfirm` on `pacman -Syu`.** `pacman(8)`: "--noconfirm Bypass any and all 'Are you sure?' messages. It's not a good idea to do this unless you want to run pacman from a script." In pacman 7.1, replacements default to yes (`callback.c:456`, `yesno`) and conflicts default to no (`callback.c:468`, `noyes`). So `karchy update` accepts replacements silently and stops on conflicts with pacman's own error. That fails safe; F8 covers the news part.

---

## Checked and found correct

1. `[cachyos]` is inserted above `[core]` (`install/base.sh:104-109`). CachyOS docs: "These repositories should be put above Arch Linux Repositories."
2. The CachyOS key `882DCFE48E2051D48E2562ABF3B607488DB35A47` (`base.sh:6`) ends in the docs' `F3B607488DB35A47`, and the host keyring shows it as "CachyOS <admin@cachyos.org>".
3. The Omarchy key `40DFB630…CAC571` (`base.sh:5`) matches Omarchy's own `bin/omarchy-update-keyring:12-13`.
4. Keys are received and then lsigned, as in https://wiki.archlinux.org/title/Pacman/Package_signing#Adding_unofficial_keys. karchy's key comes from the installer, with no key server.
5. `karchy-keyring.install` runs `pacman-key --populate karchy` from `/usr/share/pacman/keyrings/karchy{.gpg,-trusted,-revoked}`, the layout `pacman-key(8)` `--populate` expects.
6. pacstrap copies the live keyring and mirrorlist into the target by default (`pacstrap.in`: `copykeyring=1`, `copymirrorlist=1`, lines 98-111). The target's `pacman.conf` comes from the pacman package and `base_repos_target` edits it afterwards, which matches pacstrap's documented behaviour.
7. SigLevel: the global `Required DatabaseOptional` (CachyOS's shipped `pacman.conf`) covers `[cachyos]` and `[omarchy]`, and `[karchy]` uses `Required` (`pacman.conf(5)`).
8. Keyrings before the upgrade: `pacman -Sy --needed <keyrings>` immediately followed by `-Syu` (`karchy-update:233-246`). Package_signing#Upgrade_system_regularly: "This command is not considered a partial upgrade since it syncs the package database and upgrades the keyring package first."
9. The root-free check uses `checkupdates` with its own database (`karchy-update:72-74`, `karchy-update-check:227`). System_maintenance says checkupdates "provides a safe way to check for upgrades … without running a system update".
10. The preview `pacman -Sup` can't hang on the zlib-ng replacement prompt: print mode answers replace questions with yes (`callback.c:429-439`).
11. Repository packages update before AUR packages (`karchy-update` steps 3 and 4), the order the AUR article assumes.
12. Mirror ranking flags: `--protocol https`, `arch --completion 1 --max-delay 21600`. `rate-mirrors arch --help` gives max-delay "in seconds" and completion "0-1".
13. Mirror freshness is checked against each mirror's `lastsync`. https://wiki.archlinux.org/title/Mirrors#Force_pacman_to_refresh_the_package_lists: "checking timestamp of mirror's lastsync file to ensure package lists are up to date".
14. The new mirror list is swapped in atomically with a backup, and the GeoDNS mirror stays last (`karchy-mirrors-rank:80-92`). Ranking and `karchy update` share `/run/lock/karchy-update` (`tmpfiles.d/karchy.conf:3`).
15. `paccache.timer` is enabled (`setup.sh:81`). https://wiki.archlinux.org/title/Pacman#Cleaning_the_package_cache: "Enable and start paccache.timer to discard unused packages weekly."
16. The package cache lives on `@cache`, outside snapshots (https://wiki.archlinux.org/title/Snapper#Tips_and_tricks lists `/var/cache/pacman/pkg` as "not worth being snapshotted"). The pacman database stays on `@` ("must stay on the root subvolume").
17. `.pacnew` files are detected with `pacdiff --output` (`pacdiff(8)` `-o, --output print files instead of merging them`); only the merge advice is wrong (F3).
18. snap-pac with a snapper config for `/` only (`base.sh:192-194`). `snap-pac(8)`: "By default only the root snapper configuration is snapshotted."
19. sudo: a drop-in in `/etc/sudoers.d` with mode 0440 and the directory 0750 (`karchy-settings/PKGBUILD:35-36`), `%wheel ALL=(ALL:ALL) ALL`, `timestamp_timeout=10`, and the file checked with `visudo -cf` (`base.sh:141`). See https://wiki.archlinux.org/title/Sudo sections "Using visudo", "Sudoers default file permissions" and "Reduce the number of times you have to type a password". File names contain no `.`.
20. faillock: raising `deny` instead of lowering the lockout (`setup.sh:71`). https://wiki.archlinux.org/title/Security: "if lockouts due to mistyping of passwords become too frequent, relaxing the number of attempts may be preferred to reducing the lockout time."
21. Root is locked with `passwd --lock root` (Security#Restricting root login); see F4 for the rescue side.
22. The user is in `wheel` only (`base.sh:137`). https://wiki.archlinux.org/title/Users_and_groups#Pre-systemd_groups: adding users to device groups "has been deprecated in favour of udev marking the devices with a uaccess tag". ddcutil ships `60-ddcutil-i2c.rules` with `TAG+="uaccess"` and a modules-load file, so external-monitor brightness needs no `i2c` group.
23. sysctl: `tcp_mtu_probing = 1` and BBR with `tcp_bbr` loaded first (https://wiki.archlinux.org/title/Sysctl#Enable_MTU_probing, #Enable_BBR). `systemd-sysctl.service` has `After=systemd-modules-load.service`, and the CachyOS kernel ships `tcp_bbr.ko`.
24. sysctl and other drop-ins live in `/usr/lib/...`, so same-named files in `/etc` win (`sysctl.d(5)`; Sysctl wiki: "parameters in a /usr/lib/sysctl.d/50-default.conf will be overriden by equal parameters in /etc/sysctl.d/50-default.conf").
25. journald: systemd defaults on the separate `@log` subvolume (`journald.conf(5)`: SystemMaxUse defaults to 10%, capped at 4G), kept out of root snapshots.
26. systemd-oomd is enabled with swap present. `systemd-oomd.service(8)`: "It is highly recommended for the system to have swap enabled". The CachyOS kernel has `CONFIG_PSI=y`. The `kill` policy is set only on the user `app.slice`, which is allowed (`systemd.resource-control(5)` ManagedOOMMemoryPressure). VM check: `oomctl` should list `…/user@1000.service/app.slice`.
27. `linux-firmware` (CachyOS `1:20261019-1`) is a meta package depending on 12 parts, including `-amdgpu`, `-amd` (amdnpu), `-mediatek`, `-nvidia`, `-realtek` and `-intel`. That covers the Framework 13 AMD's MediaTek Wi-Fi and Bluetooth (7040: `14c3:0616` MT7922; AI 300: `14c3:0717` MT7925, both in `linux-firmware-mediatek` per `pacman -Ql`; IDs from the Arch Wiki Framework pages) and the desktop's usual Intel or Realtek network. The RTX 5080 on nvidia-open loads its GSP firmware from `nvidia-utils` (`/usr/lib/firmware/nvidia/620.70.06/gsp_ga10x.bin`), not from linux-firmware.
28. Microcode follows the CPU vendor (`base.sh:45-48`), with the mkinitcpio `microcode` hook after `autodetect` (`mkinitcpio.conf.d/karchy.conf:3`). https://wiki.archlinux.org/title/Microcode#mkinitcpio: "If the autodetect hook precedes microcode, then only the microcode for the current CPU will be included." On hardware, confirm with `journalctl -k -g microcode`.
29. Locale, time and hostname follow the Installation guide: `locale.gen` plus `locale-gen`, `locale.conf`, `/etc/localtime` and `hwclock --systohc` (`base.sh:125-134`).
30. The console keymap is chosen from `localectl list-keymaps` (`form.sh:86`). `vconsole.conf` is written before `limine-update` rebuilds the initramfs: `/usr/bin/limine-update` calls `limine-mkinitcpio`, and `base_bootloader` runs after `base_locale`. So the LUKS prompt gets the keymap (Installation guide: "If you have changed the default console keymap, only recreating the initramfs is required").
31. `systemd-timesyncd` is enabled (`base.sh:197`). The Installation guide recommends "an NTP client such as systemd-timesyncd".
32. ufw: the package's `/etc/default/ufw` ships `DEFAULT_INPUT_POLICY="DROP"` (unchanged on this host; `pacman -Qkk` reports only a time mismatch). karchy sets `ENABLED=yes` and enables `ufw.service` (https://wiki.archlinux.org/title/Uncomplicated_Firewall: "Make sure ufw.service has been enabled"). The built-in rules allow avahi and DHCP replies.
33. `iptables-nft` is named explicitly for ufw (`base.txt:26-28`).
34. AppArmor is absent. This is Arch's default (Security lists it as an optional MAC). The CachyOS kernel builds it (`CONFIG_SECURITY_APPARMOR=y`) but leaves it out of `CONFIG_LSM`, so it is off unless `lsm=` is set.
35. The `resolv.conf` stub link is made last, outside arch-chroot (`base.sh:234-237`), which avoids arch-chroot's bind mount.
36. The makepkg drop-in directory `/etc/makepkg.conf.d/*.conf` is supported (`makepkg.conf(5)`); only its comment is wrong (F14).

Count: 16 findings (3 broken-feature, 8 suboptimal, 5 cosmetic), 3 decision notes, 36 items checked and found correct.
