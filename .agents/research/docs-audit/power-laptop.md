# Docs audit: power management and laptop hardware

Date: 2026-11-16. Scope: power management and laptop hardware on the Framework 13 AMD and the RTX 5080 desktop, checked against the Arch Wiki, upstream docs and upstream source. Read-only audit: no repository file other than this report was changed, and no host or VM state was changed.

## Hardware this covers

The Framework Laptop 13 has shipped with two AMD mainboard generations (Arch Wiki "Framework Laptop 13" generation list; per-generation pages):

| Generation | APU | Wi-Fi card | Fingerprint | Notes |
| --- | --- | --- | --- | --- |
| AMD Ryzen 7040 Series (2023) | Phoenix (`1002:15bf`) | AMD RZ616 = MediaTek **MT7922** (`14c3:0616`), driven by `mt7921e` | Goodix `27c6:609c` | "Needs BIOS 3.03 or newer"; BIOS 3.18 stable on LVFS |
| AMD Ryzen AI 300 Series (2025) | Strix/Krackan Point (`1002:150e`) | AMD RZ717 = MediaTek **MT7925** (`14c3:0717`), "Poor support" | Goodix `27c6:609c` | BIOS 3.05 stable on LVFS; wants a current kernel |

The brief's "MT7921/RZ616" is slightly off: RZ616 is the MT7922, which the `mt7921e` driver also drives. "An older one" is most likely the 7040, but both are covered below.

Sources: https://wiki.archlinux.org/index.php?title=Framework_Laptop_13&action=raw (Wi-Fi/Bluetooth table, BIOS updates table), https://wiki.archlinux.org/index.php?title=Framework_Laptop_13_(AMD_Ryzen_7040_Series)&action=raw, https://wiki.archlinux.org/index.php?title=Framework_Laptop_13_(AMD_Ryzen_AI_300_Series)&action=raw.

Kernel facts below come from `/proc/config.gz` on this host, which runs the same `linux-cachyos` 7.3.3 that karchy installs.

---

## Findings

Ordered by severity. Each finding ends with where it can be checked.

### F1. With karchy's Secure Boot on, BIOS updates through fwupd will fail

- **Severity:** broken-feature
- **What karchy does:** `install/base.sh:212-225` (`base_secureboot`) enrolls sbctl keys plus Microsoft's and signs Limine. Nothing signs fwupd's EFI binary or sets `DisableShimForSecureBoot`. `bin/karchy-update-firmware:13-14` copies the **unsigned** `/usr/lib/fwupd/efi/fwupdx64.efi` to `/boot/EFI/arch/fwupdx64.efi`, then runs `fwupdmgr update` (line 18). karchy has no shim.
- **What the docs say:**
  - Arch Wiki fwupd, "Secure Boot": "Currently, ''fwupd'' relies on [[Secure Boot#shim|shim]] to chainload the ''fwupd'' EFI binary on systems with [[Secure Boot]] enabled". Under "Using your own keys": `# sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi`, "Then after each update of fwupd, the UEFI executable will be automatically signed, thanks to the sbctl pacman hook", and "Finally, you have to set `DisableShimForSecureBoot` in `/etc/fwupd/fwupd.conf`". (https://wiki.archlinux.org/index.php?title=Fwupd&action=raw)
  - fwupd.conf(5) on this host: "DisableShimForSecureBoot=false — The shim loader is required to chainload the fwupd EFI binary unless the fwupd.efi file has been self-signed manually."
  - Arch Wiki fwupd, "Prepare ESP": "''fwupd'' will copy all the necessary files over to the ''esp''". The copy in karchy-update-firmware is therefore not needed.
  - The Framework 7040 and AI 300 BIOS updates are delivered this way: the Framework Laptop 13 wiki's BIOS table lists LVFS stable 3.18 (7040) and 3.05 (AI 300).
- **Fix:**
  1. In `base_secureboot`, after `sbctl create-keys`, run `sbctl sign -s -o /usr/lib/fwupd/efi/fwupdx64.efi.signed /usr/lib/fwupd/efi/fwupdx64.efi`. The `-s` adds the file to sbctl's database, so the `zz-sbctl.hook` re-signs it after each fwupd update.
  2. Write `[uefi_capsule]` / `DisableShimForSecureBoot=true` into `/etc/fwupd/fwupd.conf`. pacman keeps the edit, because the file is a backup file of fwupd (`pacman -Qii fwupd`).
  3. Make `karchy-secureboot enroll` repeat step 1, since it can run after a key reset.
  4. Drop the `install` of the unsigned binary in `karchy-update-firmware:13-15`.
- **Where to check:** real hardware. OVMF has no ESRT capsule device, so a VM can only confirm that the signed file and the config line exist.

### F2. Idle suspend silently does nothing when systemd refuses suspend-then-hibernate

- **Severity:** broken-feature (conditional: heavy swap use, or no RTC alarm support)
- **What karchy does:** `shell/plugins/services/idle/Service.qml:103-105` runs `if karchy-hibernation-available; then systemctl suspend-then-hibernate; else systemctl suspend; fi`. There is no fallback when `systemctl` fails. `bin/karchy-hibernation-available:21-38` compares *total* swap with `/sys/power/image_size` and checks for `resume=`. It does not apply systemd's own test.
- **What the docs and source say:**
  - systemd v262 `src/shared/hibernate-util.c:462-497`, `hibernation_is_safe()`: `r = active <= (size - used) * HIBERNATION_SWAP_THRESHOLD;` with `#define HIBERNATION_SWAP_THRESHOLD 0.98`. In other words, Active(anon) must fit in the **free** swap.
  - `src/login/logind-dbus.c:2273-2304`: when that check fails, the D-Bus call returns "Not enough suitable swap space for hibernation available on compatible block devices and file systems". `SLEEP_ALARM_NOT_SUPPORTED` returns "Sleep verb '%s' is not configured or configuration is not supported by kernel".
  - (https://raw.githubusercontent.com/systemd/systemd/v262/src/shared/hibernate-util.c, https://raw.githubusercontent.com/systemd/systemd/v262/src/login/logind-dbus.c)
  - The swap file doubles as zswap's writeback target (D-10). After a memory-heavy session, `used` grows and the check fails, so the laptop stays awake on battery.
  - The lid path is not affected: logind falls back to plain suspend for button and lid actions (`src/login/logind-action.c:286-293`: "Requested %s operation is not supported, using regular suspend instead.").
- **Fix:** call `systemctl sleep` instead. Arch Wiki Suspend and hibernate: "The `systemctl sleep` command will automatically select the most appropriate sleep operation. By default, `suspend-then-hibernate` is used, and falls back to `suspend`". logind.conf(5): `SleepOperation=` defaults to "suspend-then-hibernate suspend hibernate". The smallest change that keeps today's structure is `systemctl suspend-then-hibernate || systemctl suspend`.
- **Where to check:** VM. Fill the swap (or boot without `resume=` while keeping the script's check true), let idle fire on a VM with a fake battery or `idle.suspendOnAC`, and read the journal.

### F3. Thunderbolt and USB4 docks lose their PCIe-attached devices without bolt

- **Severity:** broken-feature (docks whose Ethernet or USB controller sits behind a PCIe tunnel)
- **What karchy does:** no package installs `bolt` (`packaging/pkgbuilds/karchy-laptop/PKGBUILD:12`, `karchy-desktop/PKGBUILD:12-49`), and there is no udev authorize rule. `system/mkinitcpio.conf.d/karchy-thunderbolt.conf` loads the module only.
- **What the docs say:**
  - Kernel `Documentation/admin-guide/thunderbolt.rst:16-22`: "the software connection manager in Linux also advertises security level ``user`` which means PCIe tunneling is disabled by default … the software connection manager only supports ``user`` security level and is expected to be accompanied with an IOMMU based DMA protection." (https://raw.githubusercontent.com/torvalds/linux/master/Documentation/admin-guide/thunderbolt.rst). AMD's USB4 hosts use the software connection manager.
  - boltd(8) on this host: "The primary task of boltd is to authorize thunderbolt peripherals if the security level is either user or secure", and "As long as iommu support is active … new devices will be automatically enrolled with the iommu policy and … automatically authorized by boltd without any user interaction."
  - Framework community, "TS4 dock ethernet missing in Fedora — fixed by installing bolt" (https://community.frame.work/t/ts4-dock-ethernet-missing-in-fedora-fixed-by-installing-bolt/84454). A 7040 bolt log there shows the `user` level with the `iommu` policy (https://community.frame.work/t/amd-7040-standalone-usb4-issue/67578).
  - Arch Wiki Framework Laptop 13, "Docking stations": "On AMD systems, only the top left and top right ports (the rear ports) have Thunderbolt 3 support, in addition to being USB 4."
- **Fix:** add `bolt` to `karchy-desktop` depends. It is small, and boltd(8) says it is "autostarted via systemd/udev if a thunderbolt device is connected". At minimum, add it to `karchy-laptop`. Also tell the owner to dock on a rear port.
- **Where to check:** real hardware. Run `cat /sys/bus/thunderbolt/devices/domain0/security` and `boltctl domains`, then test the dock's Ethernet.

### F4. The headphone jack buzzes or pops when the HDA codec power-saves

- **Severity:** suboptimal
- **What karchy does:** sets no `snd_hda_intel` option. The kernel default is `CONFIG_SND_HDA_POWER_SAVE_DEFAULT=10` (host config).
- **What the docs say:** Arch Wiki Framework Laptop 13, "Headset jack": "On Intel and AMD motherboards, when powersave activates and deactivates on the sound card, there is a small noisy popping sound or a buzzing sound … You can deactivate powersave for the sound card entirely by passing `power_save=0` as a module option to `snd_hda_intel`." The Framework community thread for the AMD 13 was marked solved with `snd_hda_intel.power_save=0` (https://community.frame.work/t/resolved-framework-13-amd-headphone-jack-buzz-when-not-playing-audio/39116).
- **Fix:** test first. If the buzz is there, ship `/usr/lib/modprobe.d/karchy-framework-audio.conf` with `options snd_hda_intel power_save=0` from `karchy-laptop`, installed only on Framework (the DMI check in `install/setup.sh:26`), or document it. The cost is a small amount of idle power.
- **Where to check:** real hardware (headphones in the jack, silence).

### F5. The MT7922 can reboot the laptop instead of resuming

- **Severity:** suboptimal (conditional; reported by some users, not all)
- **What karchy does:** has no rfkill-around-sleep unit. Wi-Fi power save is off (`system/NetworkManager/conf.d/30-karchy-wifi-powersave.conf`), which the wiki recommends separately.
- **What the docs say:** Arch Wiki Framework 13 (AMD Ryzen 7040), "Wakeup issues": "Some users experience issues on wakeup from suspend / hibernate, as the framework has a chance of rebooting instead of waking up. The wifi module Mediatek MT7921 seems to cause this. As a workaround, turn off wifi before suspend and enable it after wakeup." The page gives an `rfkill-before-sleep.service` (`Before=sleep.target`, `ExecStart=/usr/sbin/rfkill block all`, `ExecStop=/usr/sbin/rfkill unblock all`). It also says "the computer can sometimes fail to wake up if a display adapter is plugged into the port on the left side, closest to the user."
- **Fix:** no default change. If it happens, ship that unit for Framework only. It must restore the user's own rfkill state and not undo airplane mode (`karchy-airplane`), so it should block only `wlan` and remember the previous state. Don't put a display card in the front-left slot.
- **Where to check:** real hardware (a few dozen suspend and resume cycles).

### F6. On AC the default profile is "performance"

- **Severity:** suboptimal
- **What karchy does:** `bin/karchy-powerprofiles-set:50-56` defaults to `performance` on AC whenever it is available, and the battery service applies it at every plug-in (`shell/plugins/services/battery/Service.qml:54-63,135-141`).
- **What the docs say:** PPD README: "In 'performance' mode performance will be maximized at the expense of power." (https://sources.debian.org/data/main/p/power-profiles-daemon/0.30-2/README.md, identical to upstream 0.30). On AMD, PPD drives amd-pstate EPP and platform_profile from the profile (README "Operations on AMD-based machines"), so a laptop on a desk runs hotter and louder at idle.
- **Fix:** default to `balanced` on both sources and keep the per-source memory, so a user who picks performance on AC keeps it. This is the owner's call. The Omarchy origin is `bin/omarchy-powerprofiles-set` (`vendor/upstream.tsv:133`).
- **Where to check:** real hardware (fan noise and `powerprofilesctl` on AC).

### F7. A plain suspend on AC can drain the battery after the charger is pulled (D-32)

- **Severity:** suboptimal. This is a decision risk, also listed in the decisions section.
- **What karchy does:** `system/laptop/logind.conf:6` sets `HandleLidSwitchExternalPower=suspend`. A lid closed on AC that is unplugged later (picked up and put in a bag) stays in s2idle until the battery is empty.
- **What the docs say:** systemd-sleep.conf(5) on this host: "HibernateOnACPower= Whether to allow hibernation when the system has AC power. … If this option is disabled, the countdown of HibernateDelaySec= starts only after AC power is disconnected, keeping the system in the suspend state otherwise. … Added in version 257."
- **Fix:** keep D-32's intent (no hibernation while plugged in) but make it safe:
  - `HandleLidSwitchExternalPower=suspend-then-hibernate` in `system/laptop/logind.conf`
  - `HibernateOnACPower=no` in `system/laptop/sleep.conf`
- **Where to check:** real hardware (close on AC, unplug, wait more than 2 h).

### F8. Nothing refreshes LVFS metadata, so BIOS updates go unnoticed

- **Severity:** suboptimal
- **What karchy does:** the services enabled at `install/setup.sh:80-87` don't include `fwupd-refresh.timer`. Metadata is fetched only when the owner runs Update Firmware (`bin/karchy-update-firmware:17`).
- **What the docs say:** Arch Wiki fwupd, "Usage": "To download the latest metadata … `$ fwupdmgr refresh` — Tip: This can be done automatically by enabling `fwupd-refresh.timer`." The Framework 13 wiki recommends staying on the current BIOS ("It is highly recommended to upgrade to BIOS 3.05 for maximum compatibility", 7040 page).
- **Fix:** enable `fwupd-refresh.timer` in `setup_services`. A later step could let `karchy-update-check` mention pending firmware (`fwupdmgr get-updates --json`, which needs no root).
- **Where to check:** VM (the timer runs; `fwupdmgr get-remotes` shows a fresh age).

### F9. NVIDIA laptops don't get the suspend-then-hibernate unit

- **Severity:** suboptimal. It doesn't affect the owner's machines: the laptop is AMD-only and the desktop never uses suspend-then-hibernate.
- **What karchy does:** `install/setup.sh:93-95` enables `nvidia-suspend`, `nvidia-resume` and `nvidia-hibernate`, but not `nvidia-suspend-then-hibernate`, although `karchy-laptop` uses suspend-then-hibernate.
- **What the docs say:** nvidia-utils 620.70.06 ships `/usr/lib/systemd/system/nvidia-suspend-then-hibernate.service` ("NVIDIA actions for suspend-then-hibernate", `Before=systemd-suspend-then-hibernate.service`, `WantedBy=systemd-suspend-then-hibernate.service`). Read from the host's unit file, owned by `nvidia-utils 620.70.06-2`.
- **Fix:** add it to the `systemctl enable` line when the unit file exists.
- **Where to check:** real hardware (an NVIDIA laptop). Not needed for the owner's two machines.

### F10. A running karchy VM may block suspend (unverified on current kernels)

- **Severity:** suboptimal (unverified)
- **What karchy does:** karchy VMs run as user units under `user.slice` (D-63).
- **What the docs say:** Arch Wiki Suspend and hibernate, "System freezes for 60 seconds and then wakes back up": "Since systemd v256, systemd freezes `user.slice` before sleeping. This process can fail due to kernel bugs, particularly when KVM is in use." The page cites systemd issues #33083 and #33626.
- **Fix:** none until reproduced. Add "suspend with a VM running" to the phase 4 checklist. If it fails, the documented workaround is `Environment=SYSTEMD_SLEEP_FREEZE_USER_SESSIONS=false` on the sleep services, which the wiki warns "can itself prevent the system from going to sleep".
- **Where to check:** VM-in-VM is unreliable, so test on real hardware with a `karchy vm` running.

### F11. Fingerprint setup gives no hint when the reader's firmware is too old

- **Severity:** suboptimal
- **What karchy does:** `bin/karchy-setup-security-fingerprint:144-147` detects the Goodix reader by vendor ID, then fails at enrollment with "Enrollment failed. Please try again." (line 224).
- **What the docs say:** Arch Wiki Framework 13 (AMD 7040 and AI 300), "Fingerprint reader": "You will need to upgrade the fingerprint reader firmware following the article on the Framework knowledgebase if your reader isn't recognised." Arch Wiki fprint, "No devices available": "Ignoring device due to initialization error: unsupported firmware version — Ensure your device's firmware is up to date with [[Fwupd]]."
- **Fix:** when `fprintd-enroll` fails or reports no device, print "Update the reader's firmware with Update Firmware, then try again" before exiting.
- **Where to check:** real hardware.

### F12. The Framework charge limit can't be seen or set from karchy

- **Severity:** cosmetic (the limit still works, set in the BIOS or with `framework_tool`)
- **What karchy does:**
  - `bin/karchy-battery-status:95-102` reads `charge_control_end_threshold` from sysfs, and `:138-147` uses it to show "holding".
  - The power panel shows "Charge limit" only with that value (`shell/plugins/panels/power/Panel.qml:405-406`).
  - `install/setup.sh:24-28` installs `framework-system`, and `docs/components.md:140` says it covers the "charge limit".
- **What the docs say:**
  - Kernel `drivers/power/supply/cros_charge-control.c` (in v6.12, v6.18 and master): `if (ret > 0 && !probe_with_fwk_charge_control) { dev_info(dev, "Framework charge control detected, preventing load\n"); return -ENODEV; }` (https://raw.githubusercontent.com/torvalds/linux/master/drivers/power/supply/cros_charge-control.c). On a Framework there is no sysfs threshold by default, so UPower has none either.
  - The limit lives in the EC: framework-system's EXAMPLES.md has "`--charge-limit [<CHARGE_LIMIT>]` Get or set max charge limit" (https://raw.githubusercontent.com/FrameworkComputer/framework-system/main/EXAMPLES.md), and its README says "Many actions require root".
- **Fix:** document that the limit is set in the BIOS (or `sudo framework_tool --charge-limit 80`). Expect the panel to show "time to full" instead of "holding" at the limit. Don't set `probe_with_fwk_charge_control` blindly: the kernel refuses to load by default precisely because Framework's EC has its own limit. A later Settings › Power page could call `framework_tool` through a root helper.
- **Where to check:** real hardware.

### F13. Removing fingerprint leaves a stale `/etc/pam.d/polkit-1`

- **Severity:** cosmetic
- **What karchy does:** setup creates `/etc/pam.d/polkit-1` when it is missing (`bin/karchy-setup-security-fingerprint:42-55`; polkit ships only `/usr/lib/pam.d/polkit-1`, per `pacman -Ql polkit`). Removal only deletes the fingerprint lines (`bin/karchy-remove-security-fingerprint:32-36`), so the copy stays.
- **What the docs say:** pam.d(5): "Files in /etc/pam.d override files with the same name in this directory [/usr/lib/pam.d]." Future polkit PAM changes would be masked.
- **Fix:** on removal, delete `/etc/pam.d/polkit-1` when what remains equals `/usr/lib/pam.d/polkit-1` (`cmp`).
- **Where to check:** VM. The code path doesn't need a reader if the detection guard is bypassed.

### F14. components.md says the fingerprint reader is set up at install

- **Severity:** cosmetic (docs)
- **What karchy does:** `docs/components.md:141` lists "Fingerprint reader: fprintd + PAM (D-14)" under "Detected at install". The installer installs nothing for it; the menu offers "Set Up Fingerprint" when `karchy-hw-fingerprint` succeeds (`default/karchy/karchy-menu.jsonc:71`).
- **Fix:** move the line to say "offered in the menu when a reader is detected".
- **Where to check:** no check needed.

---

## Decisions where the docs show a risk (reported separately)

- **D-14, fingerprint as `sufficient` for sudo and polkit.** Arch Wiki fprint, "Login configuration": "This setting (fingerprint-only authentication) is a security breach if used for su, polkit, or sudo as it allows background processes to obtain permissions without prompting the user for a fingerprint (via fingerprint hijacking). See CVE-2024-37408." karchy inserts `auth sufficient pam_fprintd.so` at the top of `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1` (`bin/karchy-setup-security-fingerprint:22-41`).
  - **Risk:** any process running as the user can start `sudo` in a hidden pty and get root from the next sensor touch, which might be meant for something else.
  - **Mitigation that keeps the flow:** keep fingerprint for polkit and the lock screen, where karchy's overlay shows the request. For sudo, either use the password, or at least `pam_fprintd.so max-tries=1 timeout=10` as the wiki's sudo example does.
  - The lid gate itself is fine: pam_exec runs it with the caller's real UID and the PAM environment only.
- **D-32, plain suspend on AC.** See F7. systemd 257+'s `HibernateOnACPower=no` gives the same "never hibernate while plugged in" behavior without the drained-battery case.

---

## Checked and found correct

1. CPU frequency driver: `linux-cachyos` is built with `CONFIG_X86_AMD_PSTATE=y`, `CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3` (active/EPP). This matches the Arch Wiki CPU frequency scaling page ("built with CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3 which means the default for them is the active mode"), so no `amd_pstate=` parameter is needed.
2. power-profiles-daemon is the only power manager. No TLP, tuned, auto-cpufreq or system76-power is installed, and none is in Quick install (`default/karchy/quick-install.json`). Framework and AMD recommend PPD over TLP (Arch Wiki Framework 13: "(AMD) TLP is not advised … PPD is recommended"). PPD's unit `Conflicts=tuned.service tlp.service auto-cpufreq.service system76-power.service`.
3. The PPD that karchy gets is CachyOS's 0.30-3 (`[cachyos]` before Arch, D-45). Its `scx-scheds` integration is optional and inert. `powerprofilesctl` needs `python-gobject`, which `karchy` depends on.
4. Panel power savings (ABM): PPD 0.30 leaves `amdgpu_panel_power` off ("This is disabled by default", README), and amdgpu `abmlevel` defaults to -1/auto (`amdgpu_drv.c` DOC: abmlevel). The wiki's "washed-out colors" warning describes PPD 0.20 behavior that no longer applies.
5. Suspend method: the AMD Framework is s2idle only, and karchy sets no `mem_sleep_default`. It also avoids `nvme.noacpi=1` ("on AMD it will cause the issue") and `acpi_osi="!Windows 2020"` (Intel only), both from the Arch Wiki Framework 13 "Suspend" section.
6. No stale AMD workaround parameters (`amdgpu.sg_display=0` is "resolved with the latest BIOS update"; `amdgpu.dcdebugmask=0x10`/`0x610` are only-if-needed fixes). Keep them in the troubleshooting notes.
7. `amd-ucode` is added on AMD CPUs (`install/base.sh:45-47`), and `linux-firmware` (including `-mediatek` and `-amdgpu`) is pacstrapped (`install/packages/base.txt`), as the Framework pages require.
8. The Wi-Fi regulatory domain is set from the timezone (`system/wifi/*`). Without it, the wiki says: "You will be limited to 802.11n (Wi-Fi 4) and 2.4GHz bands if you do not configure the regulatory domain."
9. Wi-Fi power save is off, which the wiki recommends: "For MT7921/MT7922, Wi-Fi stability can be improved by disabling power saving mode."
10. The lid configuration keys and values are valid per logind.conf(5): `HandleLidSwitch=suspend-then-hibernate`, `HandleLidSwitchExternalPower=suspend`, with `HandleLidSwitchDocked` left at "ignore". So is the drop-in path `/usr/lib/systemd/logind.conf.d/`.
11. The lid falls back to suspend when hibernation isn't possible (systemd v262 `logind-action.c:286-293`).
12. `HibernateDelaySec=2h` in `/usr/lib/systemd/sleep.conf.d/` is valid. With a battery, systemd uses ACPI `_BTP` and the delay, "whichever comes first" (systemd-sleep.conf(5)).
13. The hibernation location is correct: `resume=UUID=<btrfs fs on the LUKS mapper>` plus `resume_offset` from `btrfs inspect-internal map-swapfile -r` (Arch Wiki Suspend and hibernate, "Acquire swap file offset", and the LUKS note "resume= parameter must point to the unlocked/mapped device"). The `systemd` initramfs hook needs no `resume` hook ("a resume mechanism is already provided").
14. Hibernation works with Secure Boot: `CONFIG_LOCK_DOWN_KERNEL_FORCE_NONE=y`, so lockdown doesn't apply (Arch Wiki: "Enabling kernel lockdown prevents hibernation").
15. Lock before sleep uses a delay inhibitor with `InhibitDelayMaxSec=15` (logind.conf(5): "Specifies the maximum time a system shutdown or sleep request is delayed due to an inhibitor lock of type delay").
16. The clamshell `handle-lid-switch` block inhibitor is honored whatever `LidSwitchIgnoreInhibited` says (logind.conf(5): "Low level inhibitor locks … are always honored").
17. `karchy-system-lid-inhibit`'s list of connectors logind doesn't count (USB, Unknown, DVI-A, Composite) matches logind's own list, including the missing comma between "DVI-A-" and "Composite-" (systemd v262 `logind-core.c:665-670`).
18. Idle suspend respects other apps' sleep inhibitors: systemctl(1) says the default `--check-inhibitors=auto` "means logind will perform the check and respect active inhibitor locks".
19. A critical battery while awake is handled by UPower's `CriticalPowerAction=Auto`: "If HybridSleep isn't available, Hibernate will be used. If Hibernate isn't available, PowerOff will be used" (`/etc/UPower/UPower.conf`).
20. Display backlight: `brightnessctl` uses the logind API, so no video group is needed (brightnessctl README, "Permissions"). `karchy-hw-display` prefers `amdgpu_bl*`.
21. Keyboard backlight: the Framework AMD keyboard LED is `chromeos::kbd_backlight` (cros_kbd_led_backlight bound through cros_ec since 6.10, per the kernel patch https://patchwork.kernel.org/project/chrome-platform/patch/20240505-cros_ec-kbd-led-framework-v1-1-bfcca69013d2@weissschuh.net/). It matches `/sys/class/leds/*kbd_backlight*` in `bin/karchy-brightness-keyboard:16`. `CONFIG_CROS_KBD_LED_BACKLIGHT=m`; the cros_ec_lpc DMI table matches "All remaining Framework Laptop models (13 AMD Ryzen …)".
22. Fingerprint detection: Goodix `27c6` is in `karchy-hw-fingerprint`'s vendor list, and the Framework reader is `27c6:609c` (both AMD wiki pages). The `libfprint-git` from `[omarchy]` provides `libfprint` and `libfprint-2.so` (omarchy.db).
23. sudo PAM order: `pam_fprintd` `sufficient` goes before `include system-auth`, as the wiki's sudo example shows. Ctrl+C at the fingerprint prompt falls through to the password: pam_fprintd catches SIGINT and returns `PAM_AUTHINFO_UNAVAIL` (fprintd 1.94.5 `pam/pam_fprintd.c`). Defaults are 3 tries and 30 s (`DEFAULT_MAX_TRIES 3`, `DEFAULT_TIMEOUT 30`).
24. The polkit PAM override in `/etc/pam.d/polkit-1` is the right mechanism (pam.d(5)), and the shell's polkit agent reads that file to switch to fingerprint mode (`shell/plugins/polkit/PolkitAgent.qml:162`).
25. fprintd after sleep: the `system-sleep` hook restarts fprintd post-resume, with `TimeoutStopSec=3s`. This covers the wiki's "Sleeping while fprintd is still running breaks fprintd". s2idle is what libfprint upstream recommends ("Upstream recommends using S2Idle sleep instead of S3").
26. iio-sensor-proxy isn't installed, which is correct: only GNOME and KDE consume it (7040 page: "Install iio-sensor-proxy to enable automatic brightness in Gnome and KDE. Other desktop environments are unsupported at this time"). `illuminanced` (Arch extra) is the option if auto-brightness is wanted later.
27. thermald isn't installed, which is correct for AMD (Framework 13 wiki: "This applies to the Intel version only. AMD users should use power-profiles-daemon.").
28. `framework-system` (Arch extra 0.6.6) is installed on Framework by the DMI vendor check (`install/setup.sh:26-28`), as the wiki's "Interact with system" section suggests. The kernel provides `cros_ec_lpcs` and `cros_ec_chardev` as modules.
29. fwupd is installed with the LVFS stable remote. Since 2.1.9-1 the passim server is off by default (Arch Wiki fwupd "Local cache server").
30. A BIOS update from the EFI shell clears the NVRAM boot entries, but `limine-install --fallback` keeps `EFI/BOOT/BOOTX64.EFI` (`install/base.sh:188`), which the wiki says avoids needing a recovery disk.
31. The Thunderbolt module is in the initramfs for USB4 dock keyboards at the LUKS prompt. It is valid because the software connection manager still makes USB and DP tunnels at the `user` level. TB3 docks, whose USB sits behind PCIe, still won't type there (thunderbolt.rst).
32. bees runs on AC only through `ConditionACPower=true` and a udev rule on the `Mains` supply. The Framework exposes an ACPI AC adapter (type Mains), so the rule fires (needs a hardware check).
33. Idle suspend on battery only (D-59) keeps Wayland idle inhibitors (`IdleMonitor respectInhibitors: true`) and re-checks the power source when the timer fires (`Service.qml:329-336`).

---

## Real-hardware test list (phase 4)

- **s2idle residency:** `amd-s2idle test` from `amd-debug-tools` (Arch extra). The wiki points AMD users at amd-debug-tools for S0ix checks.
- **Suspend-then-hibernate:** close the lid on battery, set `HibernateDelaySec` low for the test, and confirm the RTC wake and hibernation, then a resume through the LUKS prompt.
- **Thunderbolt:** `cat /sys/bus/thunderbolt/devices/domain0/{security,iommu_dma_protection}` with a dock on a rear port, before and after adding bolt (F3).
- **Wi-Fi:** 20 or more suspend cycles on Wi-Fi, watching for a reboot instead of a resume (F5).
- **Headphone jack:** listen for a buzz or pop at idle (F4).
- **Fingerprint:** sudo, polkit and the lock screen after a suspend. The AI 300 has a rare "reader missing after resume" problem (Framework tracking issue linked from https://github.com/FrameworkComputer/linux-docs/blob/main/Fingerprint-Wake-Workaround/README.md: "In our testing, this has not been needed. Had it occur once in 30 suspend to resumes").
- **Firmware:** run Update Firmware with Secure Boot on (F1) and check the fingerprint reader's firmware.
- **Expansion cards:** USB-A cards go in the front slots. Framework KB: "When an USB-A expansion card is attached to the far left/right port (1 & 3 …), retimers will consume more power … This can lead to a shorter Modern Standby period." (https://knowledgebase.frame.work/expansion-card-functionality-on-framework-laptop-13-amd-ryzen-7040-series-SkrVx7gAh)

## Not covered here

- NVIDIA driver specifics on the RTX 5080 desktop (VRAM preservation and its module options). These belong to the GPU audit. The desktop gets no PPD, no idle suspend and no suspend-then-hibernate, by design.
- The speaker EQ (EasyEffects preset), which the wiki recommends for the 13. D-48 dropped it deliberately; EasyEffects is in Quick install.
