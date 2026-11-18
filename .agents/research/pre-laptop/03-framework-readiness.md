# Framework 13 AMD (Ryzen 7040): readiness for the karchy install

Date: 2026-11-17. Read-only review of `main` at `c094573`. This report is the only file I created. I ran nothing with sudo and nothing on the laptop.

It builds on the 2026-11-16 audits in `.agents/research/docs-audit/` (mainly `power-laptop.md` and `boot-disk.md`). Where an audit already settled a point, I cite it and do not repeat it.

## How to read the evidence labels

- **Verified** means I read the source today: karchy's code, the running `linux-cachyos` 7.3.3 config on this host (the kernel karchy installs), upstream source files, the Arch Wiki raw pages, or a Framework community thread.
- **User report** means one or more forum posts. It is real, but it is not a vendor statement.
- **Inference** means my reasoning from verified facts. Nobody observed it on this laptop.
- **Not verified** means I could not confirm it. Section 6 lists these.

Nothing here was observed on the laptop. Every "karchy handles it" below means "the code does the right thing on paper".

---

## 1. Do before the install

Ordered by how much damage each one prevents.

### 1.1 Do not flash BIOS 3.20, and take the BIOS-update test off the laptop's list

- **Verified.** Framework's newest BIOS for this board is 3.20, marked stable (announcement thread 83283, first post 2026-07-06). The Arch Wiki table still says 3.18.
- **User report, many.** Updating to 3.20 has left boards unable to boot. Thread 84031 collects the cases. The newest one I read is dated 2026-10-26: a 7840U died going from 3.18 to 3.20. Posters on 2026-10-27 say Framework has not found the cause.
- **Quoted in thread 84031, post 43, from Ars Technica.** Framework says a "small percentage" of updates fail, the cause is under investigation, and a "Crisis Recovery Mode" will come in later BIOS releases. I could not open the Ars Technica article itself.
- **User report, one.** A 7840U owner measured suspend drain of about 0.75 %/h on 3.17, 1.2 %/h on 3.18 and 1.5 %/h on 3.20, and went back to 3.17 (thread 83283, post 55, 2026-11-05).
- **User report, then verified in code.** LVFS stable offers 3.20 (a user's `fwupdmgr get-history` output in thread 84031, post 68). karchy enables `fwupd-refresh.timer` (`install/setup.sh:104`) and has Update › Update Firmware, which runs `sudo fwupdmgr update` (`bin/karchy-update-firmware:16`). `fwupdmgr` asks before each device.

What to do:

1. Before wiping, read the BIOS version: `cat /sys/class/dmi/id/bios_version`. Write it down.
2. If the version is 3.05 or newer, leave the BIOS alone on install day. The Arch Wiki's only hard requirement is 3.03 for the GPU and 3.05 "for maximum compatibility".
3. If the version is older than 3.05, stop and decide separately. Do not combine a BIOS flash with the reinstall.
4. On the laptop, answer **n** when `fwupdmgr update` offers "System Firmware". Say yes only to other devices.
5. Change the "Both machines" firmware line in `.agents/TESTING.md` for the laptop. Today it says "with Secure Boot on, a BIOS update applies". On this laptop that test means flashing 3.20. Replace it with "Update Firmware lists the devices and offers 3.20. Decline it." Keep the real capsule test for the desktop, or for a later BIOS that has the recovery mode.

Cost: one doc edit. When: before the install.

### 1.2 Delete the enrolled fingerprints while the old system still boots

- **Verified.** The Goodix reader (`27c6:609c`) stores prints on the chip. The Arch Wiki says a print enrolled on Windows makes `fprintd-enroll` hang until it is removed in Windows.
- **Inference.** Prints enrolled by an old Linux install stay on the chip the same way. karchy's setup then prints "That finger is already enrolled" (`bin/karchy-setup-security-fingerprint`, `enroll-duplicate`) and has no way to clear the chip.

What to do: on the old Linux install run `fprintd-delete "$USER"`. On Windows, remove the fingerprint under Sign-in options. When: before wiping.

### 1.3 Decide Secure Boot before booting the installer, because the installer decides from the firmware state

- **Verified in code.** The form asks about Secure Boot only when the firmware is in Setup Mode, and the default answer is yes (`install/form.sh:128-131`, `install/lib.sh:74`). Outside Setup Mode the installer sets `KARCHY_SECUREBOOT=no` without asking.
- **Verified in code.** karchy has no command that turns Secure Boot on after the install. `karchy-secureboot enroll` only enrolls. The key creation, the two `/etc/default/limine` lines and the fallback switch happen only in `base_secureboot` (`install/base.sh:346-359`).
- **Verified.** With Secure Boot on and the config hash enrolled, Limine turns its boot-menu editor off (`boot-disk.md`, R1). A kernel parameter can then only be added from a running system or from a chroot.
- **Verified.** The ISO does not boot while Secure Boot is enforced (Arch Wiki, Framework Laptop 13, "Boot failed"). Setup Mode turns enforcement off, so the ISO boots there.
- **Not verified.** Whether Limine boots, and whether the editor comes back, when Secure Boot is turned off in the firmware after enrolling. `boot-disk.md` R1 asked for that test in the VM `karchy-sb`. I found no record that anyone ran it.

My recommendation: install the laptop **without** Secure Boot first. Leave the firmware out of Setup Mode and only turn enforcement off so the ISO boots. Reasons: this is the first hardware install, section 2 lists two display problems whose fix is a kernel parameter, and the recovery path under Secure Boot is untested. Turn Secure Boot on after the first week with the steps in section 4.6.

If you want Secure Boot from the first boot anyway, run the R1 test in `karchy-sb` first and write down what happens. When: before the install.

### 1.4 Check the kernel versions on install day

- **Verified (CVE-2026-98166, published 2026-10-06).** A TTM bug crashed AMD Phoenix laptops minutes to hours after a hibernation, most often with suspend-then-hibernate. That is exactly karchy's laptop sleep path. It affected 7.1 and later, 7.0.10 and later, and 6.18.57 to 6.18.58. The fix is in 7.3, 7.2.8 and 6.18.59.
- **Verified today.** The repositories hold `linux-cachyos` 7.3.4 and `linux-cachyos-lts` 6.18.60. Both carry the fix.

What to do: after the install run `pacman -Q linux-cachyos linux-cachyos-lts`. Pass is 7.3 or newer and 6.18.59 or newer. When: install day, a 10-second check.

### 1.5 Correct two expectations in `.agents/TESTING.md`

- "Charge limit ... the battery panel shows it" will fail by design. See row 15 in section 2. Change it to "the limit holds, and the panel shows no limit".
- "Lid on AC, unplug, wait 2 h: it hibernates" is right, but the timing is "within about 2 h", not "exactly 2 h after the unplug". See row 3.

When: before the install, so a correct result is not written down as a failure.

### 1.6 Arrange the hardware

All three are verified in the Arch Wiki's Framework Laptop 13 pages.

- Put USB-A cards in the front slots. In the two rear slots they raise power use.
- Do not put an HDMI or DisplayPort card in the front-left slot. That port has no display output, and a display adapter there is linked to failed wake-ups.
- Connect a USB4 or Thunderbolt dock to a rear port. Only the rear ports are USB4.

On BIOS 3.18 a dock with a mouse attached can give a black screen at power-on (user report, thread 79967. BIOS 3.20 lists a fix for one Dell monitor with a mouse). If that happens, plug the dock in at the disk password prompt.

### 1.7 Back up, and prepare the way back

See section 3.1. The short form: back up the home folder to the NAS, export what is tied to the old install, write the karchy ISO to a USB stick, verify its checksum, and boot it once to the form before wiping. Esc at the form changes nothing.

### 1.8 Optional code changes. None is required

I found no missing package and no missing kernel parameter that blocks the install. Three small changes are worth a decision. Each can wait until the first-day tests give a result.

| Change | Where | Why wait |
|---|---|---|
| `amdgpu.dcdebugmask=0x10` for Framework AMD | `install/base.sh:301-303`, gated on the DMI check | Costs battery. Add it only if the freeze appears (row 9) |
| `options snd_hda_intel power_save=0` for Framework | new modprobe file in `karchy-laptop` | Only if the jack buzzes (row 12) |
| Wi-Fi off around sleep, Framework only | new unit in `karchy-laptop` | Only if a resume reboots (row 6) |

---

## 2. Known quirks as of late 2026, and what karchy does

"When" says whether the fix must come before the install. Only rows 1, 7 and 15 need action before it, and section 1 covers them.

| # | Area | What is known | karchy | Smallest fix | When |
|---|---|---|---|---|---|
| 1 | BIOS and fwupd | 3.20 is stable on LVFS and has unresolved bricking reports. Updates need the charger, and LVFS "may not update if the battery is 100% charged" (verified, threads 83283, 84031) | Handles the mechanics. The timer and the menu entry will offer 3.20 | Doc note, and decline System Firmware (1.1) | Before |
| 2 | s2idle suspend | The board has s2idle only. No `mem_sleep_default`, no `nvme.noacpi` on AMD (verified, Arch Wiki. `power-laptop.md` item 5). Old lid and keyboard wake bugs are fixed by current BIOS. The kernel keeps a quirk only for BIOS 03.03 and 03.05 (verified, `pmc-quirks.c`). Reported drain is 0.75 to 1.5 %/h depending on BIOS (user report) | Handles it. Sets nothing, which is correct | None. Measure it (test D5) | Wait |
| 3 | Suspend-then-hibernate | `rtc_cmos.use_acpi_alarm=1` is not needed. Since 6.8 the kernel uses the ACPI alarm on AMD when the BIOS year is 2021 or later (verified, `rtc-cmos.c` on master. nixos-hardware sets the parameter only below 6.8). With `HibernateOnACPower=no`, systemd sets the 2 h alarm at suspend time, and at each alarm it sleeps on while on AC and hibernates once off AC (verified, systemd v262 `sleep.c:443-449, 548-551, 586-589`). If hibernation fails, systemd suspends again (verified, `sleep.c:609-616`) | Handles it: `system/laptop/sleep.conf`, `system/laptop/logind.conf`. Untested | None. The comment in `logind.conf` says the 2 h "only start counting once the charger is pulled". The real bound is "at most about 2 h after the unplug" | Wait |
| 4 | Hibernation resume, swap file on btrfs in LUKS | `resume=UUID=<btrfs>` plus `resume_offset` is the documented form (`power-laptop.md` item 13). The crash after resume is fixed in 7.3 and 6.18.59 (verified, CVE-2026-98166) | Handles it: `install/base.sh:295-303`, `install/disk.sh:89`, swap sized to RAM. Untested | None. Check versions (1.4) | Wait |
| 5 | amd-pstate and power-profiles-daemon | The kernel defaults to active mode with EPP (verified, `CONFIG_X86_AMD_PSTATE_DEFAULT_MODE=3`). Framework and AMD recommend PPD over TLP (verified, Arch Wiki, nixos-hardware) | Handles it: `karchy-laptop` depends on PPD, `install/setup.sh:111-112`, Balanced by default (`bin/karchy-powerprofiles-set`) | None | Wait |
| 6 | MT7922 Wi-Fi | "Chance of rebooting instead of waking up", with a turn-Wi-Fi-off-around-sleep workaround (verified, Arch Wiki 7040 page). Power save off helps stability. iwd is reported to help. Link drops are reported on Linux and on Windows, so part of it is the card (user reports, threads 40316, 84603) | Partly. Power save is off (`system/NetworkManager/conf.d/30-karchy-wifi-powersave.conf`). The regulatory domain is set (`system/wifi/`). No sleep unit | None until a resume reboots. Then ship the unit, blocking only `wlan` and keeping airplane mode (`power-laptop.md` F5) | Wait |
| 7 | MT7922 Bluetooth | Kernel 7.0.7 broke it ("Failed to send wmt func ctrl (-22)"). The same patch reached 6.18.31 and 6.12.88, so the LTS kernel broke at the same time. 7.0.8 fixed it (verified, thread 82594) | Handles this class through snapshots, not through the LTS kernel | Know that the fallback for a bad kernel update is the Snapshots entry | Before, as knowledge |
| 8 | Fingerprint | fprintd works. Update the reader firmware "if your reader isn't recognised" (verified, Arch Wiki). The reader appears in `fwupdmgr get-devices` (verified, Framework linux-docs). Old prints block enrolling (1.2) | Handles it, untested: `bin/karchy-setup-security-fingerprint`, detection in `bin/karchy-hw-fingerprint`, fprintd restart after resume in `system/systemd/system-sleep/fprintd-resume`. Polkit and lock screen only, not sudo | None. The failure message already points at Update Firmware | Wait |
| 9 | Display freeze with PSR | `flip_done timed out` and `DMCUB error` freeze the screen on the 7840U. drm/amd issue 4141 closed on 2026-08-12. Issue 3647 is still open. Reports exist on 7.0.0, 7.0.1 and 7.0.11. nixos-hardware sets `amdgpu.dcdebugmask=0x10` by default for every Framework 13 AMD (verified, `framework/13-inch/common/amd.nix`). I found no report on 7.3 either way | Misses it. No parameter | Start without it. If the journal shows either error, add it with the commands in 4.5 | Wait, with the command ready |
| 10 | Display scale | 1.5 is suggested for 2256x1504 and 2 for the 2.8K panel (verified, Arch Wiki). Hyprland picks 2 above 200 PPI and accepts only scales that divide the mode evenly (verified, Hyprland `src/output/Monitor.cpp`). The 2256x1504 panel is about 201 PPI, so the first boot is most likely at 2 (inference) | Handles it: `scale = "auto"` in `config/hypr/monitors.lua`, and `bin/karchy-hyprland-monitor-scaling` rounds to a valid scale (1.5 becomes 1.566667, 1.6 is valid) | None. Set 1.6 in Settings › Displays if 2 is too large | Wait |
| 11 | VRR and adaptive backlight | The 2.8K panel does 30 to 120 Hz VRR (verified, Arch Wiki). PPD's panel power saving is "disabled by default" (verified, PPD README on main). `amdgpu.abmlevel` defaults to -1 (verified, `modinfo` on this host). The wiki's washed-out-colors warning describes older PPD | Handles it. VRR is off unless set in Settings › Displays. No ABM | None | Wait |
| 12 | Brightness and keyboard backlight | F7 and F8 send the brightness keys. Fn+Space drives the keyboard backlight (verified, Arch Wiki key table). A kernel regression made 100 % brightness dim on 7.1.6 and later and on 6.18.43. `amdgpu.dcdebugmask=0x40000` works around it, and the reporter says the fix is upstream (user report on a Framework 16, thread 84042) | Handles the keys: `default/hypr/bindings/media.lua`, `bin/karchy-hw-display`, `bin/karchy-brightness-keyboard` | None. Test 100 % against 95 % (test D8) | Wait |
| 13 | Ambient light sensor | Works in the kernel. Only GNOME and Plasma use it through iio-sensor-proxy. `illuminanced` is the option elsewhere (verified, Arch Wiki) | Not used, by design (`power-laptop.md` item 26) | None | Wait |
| 14 | Function keys | F9 sends Super+P, F10 the airplane key, F11 Print, F12 the media key. Fn+Esc toggles Fn lock (verified, Arch Wiki) | Mostly. Airplane and Print are bound. Super+P and `XF86AudioMedia` have no binding (verified by search of `default/hypr`, `karchy/hypr`, `config/hypr`) | Cosmetic. Bind F9 to Settings › Displays if wanted | Wait |
| 15 | Charge limit | The kernel driver refuses to load on Framework: "Framework charge control detected, preventing load" unless `probe_with_fwk_charge_control` is set (verified, `cros_charge-control.c` on master and the module on this host). So `charge_control_end_threshold` does not exist. The limit is set in the BIOS or with `framework_tool --charge-limit` (verified, framework-system README) | Partly. `framework-system` is installed (`install/setup.sh:26-28`). The panel reads only the sysfs file (`bin/karchy-battery-status:97-101`), so it shows no limit | Doc note and the TESTING correction (1.5). Do not set the module option | Before, doc only |
| 16 | Speakers | Thin sound without an equalizer. Framework publishes an EasyEffects preset, `fw13-easy-effects.json` (verified, Arch Wiki, Framework linux-docs) | Not shipped, by decision (D-48). EasyEffects is in Quick install | Doc note with the preset link | Wait |
| 17 | Headphone jack | Pop or buzz when the codec power-saves. `snd_hda_intel power_save=0` fixes it (verified, Arch Wiki). The kernel default is 10 s (verified, host config) | Misses it, on purpose until tested (`power-laptop.md` F4) | A modprobe file in `karchy-laptop` for Framework, if the buzz is there | Wait |
| 18 | Microphone | Report `01-earlier-audits-status.md`, item A1, says the internal microphone may need a card profile. The kernel has Framework quirks for the ALC295 codec (verified, `alc269.c` on master) | Not handled. Not in the test list | Add the test (D10). Fix only if it fails | Wait |
| 19 | Webcam and privacy switches | The camera is a UVC device. Some apps stutter in YUYV mode (verified, Arch Wiki). The switches are hardware. `framework_tool --privacy` reads them (verified, framework-system README) | Handles the camera (`bin/karchy-capture-webcam-list`). No switch indicator | None | Wait |
| 20 | Expansion cards | See 1.6 | Nothing to handle in software | Arrange the cards | Before, hardware only |
| 21 | USB power | karchy turns USB autosuspend off for every device (`system/udev/90-karchy-usb-autosuspend.rules`, D-79). nixos-hardware does the opposite for the Ethernet card and turns autosuspend on (verified). The rule keeps the reader, camera, Bluetooth and the USB controllers awake (inference) | A decision, with a battery cost nobody measured | Measure idle draw with and without the rule (test W8). If the gap is large, limit the rule to desktops | Wait |
| 22 | USB4 and Thunderbolt docks | Without bolt, a USB4 device connects and then drops to USB 3 (user report, thread 84910. `power-laptop.md` F3) | Handles it: `karchy-laptop` depends on `bolt`, and the Thunderbolt module is in the initramfs (`system/mkinitcpio.conf.d/karchy-thunderbolt.conf`) | None | Wait |
| 23 | Firmware under Secure Boot | fwupd needs a loader signed with karchy's keys (`power-laptop.md` F1) | Handles it on paper: `bin/karchy-secureboot:59-72`. It cannot be tested here without flashing 3.20 | Leave untested on this laptop (1.1) | Before, doc only |
| 24 | Thermal and fan | The EC runs the fan. No thermald on AMD (verified, Arch Wiki). `framework_tool --thermal` shows temperatures and fan speed (verified, framework-system) | Handles it by installing nothing extra | None | Wait |
| 25 | `framework-laptop-kmod` | An out-of-tree module, in the AUR as `framework-laptop-kmod-dkms-git`. It adds the charge limit in sysfs, a fan hwmon and the privacy switches. It needs 6.10 or newer on this board (verified, its README). nixos-hardware enables it by default | Not installed | Skip for now. It would make the panel show the limit, at the price of a DKMS build on every kernel update | Wait |
| 26 | Console text at the disk prompt | The kernel prefers the 16x32 font on both panels: the 8x16 font loses points above about 20,000 character cells (verified, `lib/fonts/fonts.c`, and `CONFIG_FONT_TER16x32=y` on this host). That gives about 141 columns by 47 rows on 2256x1504 (inference) | Handles it by setting no `FONT=` | None. This answers the open point F16 in `base-system.md` | Wait |
| 27 | Keyring and TPM | The brief says TPM2 is involved for the keyring. The code says otherwise: the key is a plain file in `/etc/credstore`, root only, on the encrypted disk (`system/keyring/keyring-key`, D-57). LUKS has only the passphrase (`install/disk.sh:42`) | No TPM anywhere in the unlock path | None. A BIOS update or TPM reset cannot lock the disk or the keyring | Wait |

One more kernel report, weaker than the rows above. A Framework 16 on `linux-cachyos` 7.2.9 locked up when hardware video decode started after a long idle (thread 85399, one user, a different laptop with a second GPU). The existing `vainfo` test covers it.

---

## 3. Install day: preparation

### 3.1 Before wiping

Record, from the old system:

```sh
cat /sys/class/dmi/id/bios_version /sys/class/dmi/id/product_name
lspci -nn | grep -i network        # expect 14c3:0616 (MT7922)
cat /sys/class/drm/card*-eDP-1/modes | head -1   # 2256x1504 or 2880x1920
free -g | head -2                  # the swap file will be this size
lsblk -o NAME,SIZE,MODEL           # the disk the installer will erase
```

Back up and export:

- The home folder, to the NAS. Check that one large file and one small file restore.
- SSH keys, GPG keys, and any age or sops keys. Confirm the copies open.
- Git: push every branch, and check `git stash list` in the repositories you care about.
- Browser profiles that do not sync. Saved Wi-Fi passwords (`nmcli -s connection show <name>`), VPN profiles.
- If the old system is karchy: `karchy keyring-key export <file>`, then pass it as `KARCHY_KEYRING_KEY_FILE` so the restored keyring opens (D-57). On any other system the keyring does not carry over. Export the passwords from the apps instead.
- Two-factor codes and the password manager login. You need them on the new system before the backup is restored.
- The fingerprints (1.2).
- A list of what was installed: `pacman -Qqe > packages.txt`.

Nothing else on this laptop is tied to the old install. The old Secure Boot keys and any TPM enrollment go away with the disk, and karchy does not use the TPM.

Prepare the way back:

1. Download the rc.5 ISO and its `.sha256` from the release page. Run `sha256sum -c`.
2. Write it: `dd if=karchy-….iso of=/dev/sdX bs=4M oflag=sync`.
3. Boot it once to the form (F12 opens the boot menu). Confirm that Wi-Fi connects with `iwctl`. Press Esc. Nothing is written before "Erase and install".
4. Keep the stick. It is also the rescue stick.
5. Keep the desktop or a phone at hand for looking things up.
6. Keep the charger attached for the whole install. bees starts on AC, which is what you want on day one.

### 3.2 Firmware settings

F2 opens setup. Some BIOS versions do not see F2 from the built-in keyboard. An external USB keyboard works (verified, Arch Wiki).

- **Without Secure Boot (my recommendation, 1.3).** In the Secure Boot settings, turn enforcement off. Do not erase the keys. The installer then does not offer Secure Boot.
- **With Secure Boot.** Erase all Secure Boot settings so the firmware enters Setup Mode. The form then offers Secure Boot with yes as the default. The step runs last in the install. It creates keys with sbctl, signs Limine, enrolls the config hash, signs fwupd's loader, and enrolls the keys together with Microsoft's and the firmware's own (`install/base.sh:346-359`, `bin/karchy-secureboot:53-82`). After the reboot, turn enforcement on if it is off.
- Set the battery charge limit here if you want one.

The exact menu labels are from memory, not from a source I read today.

One install-day note from report 01, item A2: the installer does not carry the ISO's Wi-Fi connection into the installed system. Connect again from the network panel at the first login.

### 3.3 Verify at the first boot

Run these before anything else. Each line states the pass.

```sh
systemctl --failed                                   # no units listed
journalctl -b -p err --no-pager | less               # read it once, note anything from amdgpu, mt7921e, nvme, btrfs
pacman -Q karchy-laptop framework-system bolt power-profiles-daemon   # all four present
pacman -Q linux-cachyos linux-cachyos-lts            # 7.3 or newer, 6.18.59 or newer
pacman -Qi linux-cachyos | grep Architecture         # x86_64_v4: the build from the znver4 repository
grep '^\[cachyos' /etc/pacman.conf                   # the three cachyos-*-znver4 repositories come first
cat /proc/cmdline                                    # has rd.luks.uuid=, zswap.enabled=1, resume=UUID=, resume_offset=
swapon --show                                        # /swap/swapfile, size equal to RAM
sudo btrfs inspect-internal map-swapfile -r /swap/swapfile   # equals resume_offset in /proc/cmdline
findmnt -no UUID /                                   # equals resume=UUID= in /proc/cmdline
cat /sys/power/mem_sleep /sys/power/state            # [s2idle], and the second line contains "disk"
karchy-hibernation-available && echo hibernate-ok    # prints hibernate-ok
cat /sys/module/rtc_cmos/parameters/use_acpi_alarm   # Y
cat /sys/devices/system/cpu/amd_pstate/status        # active
powerprofilesctl                                     # three profiles, balanced selected
systemd-analyze cat-config systemd/sleep.conf | grep -E '^(HibernateDelaySec|HibernateOnACPower)'   # 2h, no
systemd-analyze cat-config systemd/logind.conf | grep '^HandleLid'   # both suspend-then-hibernate
systemctl is-active karchy-bees                      # active on AC
sudo framework_tool --versions                       # BIOS and EC versions, matching what you wrote down
```

Then take a named snapshot of the fresh install: `sudo snapper -c root create -d "fresh install, before tests"`.

---

## 4. Recovery

### 4.1 The boot menu

Limine lists the entries in the order `install/base.sh:307` sets: `linux-cachyos`, then `linux-cachyos-lts`, then Snapshots.

1. **A problem after an update.** Boot the newest entry under Snapshots that predates the update. Each snapshot boots with the kernel it was taken with. The desktop comes up on a writable overlay. If it works, run `limine-snapper-restore` to make it permanent. `boot-disk.md` F1 notes that a full restore had never been run. Run one early, on purpose (test D3).
2. **A problem with the new kernel only.** Boot the `lts` entry. The Bluetooth breakage of May 2026 hit both kernels at once (row 7), so try a snapshot if `lts` shows the same fault.
3. **A parameter is needed to boot.** Without Secure Boot, press `e` on the entry and edit the command line for one boot. With Secure Boot the editor is off, so go to 4.3.

### 4.2 Resume from hibernation fails

- **It boots fresh instead of resuming.** The session is lost and nothing else is damaged. Check `journalctl -b -k | grep -i -E 'hibernat|resume|PM:'` for the reason. Compare `resume_offset` with `map-swapfile` as in 3.3.
- **It hangs during resume.** Hold the power button to turn it off, then boot again. The kernel clears the hibernation mark from the swap file when it starts reading the image, so the second boot should start fresh (inference from kernel behaviour I did not re-read today). If it still hangs, boot the `lts` entry: a different kernel version rejects the image.
- **Resume works but the machine freezes minutes later.** That was the symptom of CVE-2026-98166. Check the kernel versions (1.4).

To turn hibernation off while you investigate, create `/etc/systemd/sleep.conf.d/zz-no-hibernate.conf`:

```ini
[Sleep]
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
```

The lid then suspends only (logind falls back, `power-laptop.md` item 11), and the Hibernate menu entry disappears because `karchy-hibernation-available` asks logind. Delete the file to undo it. Plain suspend drains the battery if the laptop stays closed for days.

### 4.3 Chroot from the ISO, for karchy's layout

This follows `install/disk.sh`: partition 1 is the 4 GiB ESP, partition 2 is LUKS2 with the partition name `karchy`, and the btrfs inside holds the eight subvolumes.

If Secure Boot is on, turn enforcement off in the firmware first. The ISO is not signed. Do not erase the keys.

```sh
# 1. Find the disk. On this laptop it is normally nvme0n1. Partition 1 is named EFI, partition 2 karchy.
lsblk -o NAME,SIZE,FSTYPE,PARTLABEL
disk=/dev/nvme0n1

# 2. Unlock with the name the installed system uses. Type the disk password.
name="luks-$(cryptsetup luksUUID "${disk}p2")"
cryptsetup open "${disk}p2" "$name"
root=/dev/mapper/$name

# 3. Mount the subvolumes the way the installer does.
opts=noatime,compress=zstd:1
mount -o "$opts,subvol=/@" "$root" /mnt
mount -o "$opts,subvol=/@home"  "$root" /mnt/home
mount -o "$opts,subvol=/@root"  "$root" /mnt/root
mount -o "$opts,subvol=/@srv"   "$root" /mnt/srv
mount -o "$opts,subvol=/@cache" "$root" /mnt/var/cache
mount -o "$opts,subvol=/@log"   "$root" /mnt/var/log
mount -o "$opts,subvol=/@tmp"   "$root" /mnt/var/tmp
mount -o noatime,subvol=/@swap  "$root" /mnt/swap
mount -o fmask=0077,dmask=0077 "${disk}p1" /mnt/boot

# 4. Enter the system.
arch-chroot /mnt
```

Do not use `/dev/disk/by-label/karchy`. The LUKS header and the btrfs filesystem both carry the label `karchy` (`install/disk.sh:42,55`). The install stick may also have a partition named EFI, so name the partitions by disk as above.

Inside the chroot, the usual repairs:

```sh
limine-update                 # rebuilds the initramfs, the boot entries and, under Secure Boot, the hash and signatures
limine-install --fallback     # puts Limine back on the ESP and in the firmware boot list, after a firmware reset
snapper -c root list          # the snapshots, with dates and descriptions
pacman -Syu                   # only with the network up: finishes an interrupted update
journalctl -D /var/log/journal -b -1 -p err   # the errors of the last boot of the installed system
```

Leave cleanly:

```sh
exit
umount -R /mnt
cryptsetup close "$name"
```

To read files without entering the system, steps 1 to 3 are enough. A snapshot is at `/mnt/.snapshots/<number>/snapshot`.

### 4.4 The firmware lost the boot entry

A firmware reset or an EFI-shell BIOS update clears the boot list. karchy keeps `EFI/BOOT/BOOTX64.EFI` current (`install/base.sh:312-313`), so the laptop still boots through the fallback path. Run `sudo limine-install` once from the running system to restore the named entry.

### 4.5 Add a kernel parameter on the installed system

```sh
echo 'KERNEL_CMDLINE[default]+=" amdgpu.dcdebugmask=0x10"' | sudo tee -a /etc/default/limine
sudo limine-update
grep -c dcdebugmask /boot/limine.conf     # more than 0, then reboot
```

The `+=` form is the one limine-entry-tool documents for `/etc/default/limine`. I did not run these lines. Check the `grep` result before rebooting. To undo, delete the line and run `sudo limine-update` again.

### 4.6 Turn Secure Boot on after the install

These are the steps of `base_secureboot`, done by hand. Nobody has run them in this order on an installed system, so try them in the VM `karchy-sb` first.

1. In the firmware, erase all Secure Boot settings (Setup Mode). Boot karchy.
2. Run:

```sh
sudo pacman -S --needed sbctl
sudo sbctl create-keys
sudo sed -i '/^ENABLE_LIMINE_FALLBACK=/d' /etc/default/limine
printf 'ENABLE_VERIFICATION=yes\nENABLE_ENROLL_LIMINE_CONFIG=yes\n' | sudo tee -a /etc/default/limine
sudo limine-update
sudo sbctl verify                          # limine_x64.efi and BOOTX64.EFI are signed
sudo sed -i 's/^KARCHY_SECUREBOOT=.*/KARCHY_SECUREBOOT=yes/' /etc/karchy/install.conf
karchy-secureboot enroll
```

3. Reboot, turn enforcement on in the firmware, and check `sbctl status`.

A `karchy-secureboot setup` command that does this would be the proper fix. It can wait.

---

## 5. Test list

E marks a test that is already in `.agents/TESTING.md` under "On the real machines". I added the command and the pass. N marks a new test. Write down what happened for each one.

### 5.1 First day

| # | | Test | Action | Pass |
|---|---|---|---|---|
| D1 | E | Kernel build | `pacman -Qi linux-cachyos \| grep Architecture` and `grep '^\[cachyos' /etc/pacman.conf` | `x86_64_v4`, and the `znver4` repositories are listed first. `pacman -Sl` cannot show this: it marks the package installed in every repository that has it (checked on this host) |
| D2 | E | Disk prompt is readable | Look at the password prompt at boot | Text is large enough to read without leaning in |
| D3 | E | Snapshot boot, and a restore | Install any small package. Reboot, choose Snapshots, the entry before it. Then run `limine-snapper-restore` and reboot normally | The desktop comes up from the snapshot. After the restore the package is gone and the system boots |
| D4 | N | First-boot checks | The block in 3.3 | Every line matches |
| D5 | N | s2idle reaches hardware sleep | Unplug. `systemctl suspend`, wait 10 minutes, wake. Then `cat /sys/power/suspend_stats/last_hw_sleep` | Close to 600000000 (microseconds). A value near 0 means the SoC never slept. If the file is missing or the value is low, run `sudo pacman -S amd-debug-tools` and `sudo amd-s2idle test`, which names the cause |
| D6 | E | Hibernate and resume | Open a terminal and a browser. `cat /proc/sys/kernel/random/boot_id`. `systemctl hibernate`. Power on, type the disk password | The lock screen, then the same windows, and the same `boot_id` |
| D7 | E | Suspend-then-hibernate, short | Create `/etc/systemd/sleep.conf.d/zz-test.conf` with `[Sleep]` and `HibernateDelaySec=3min`. Unplug. Close the lid. Wait 6 minutes. Open it | The power light pulses, then goes dark after about 3 minutes. Opening the lid shows the disk prompt, then the session. `journalctl -b \| grep -E 'suspend entry\|hibernation entry'` shows both. Delete the file afterwards |
| D8 | N | Brightness | Press F7 and F8 through the range. Compare 95 % with 100 % | Every step changes the panel, and 100 % is the brightest |
| D9 | N | Display scale | `hyprctl monitors \| grep -E 'scale\|^Monitor'`. Set 1.6 in Settings › Displays if 2 is too large | The scale is 2 or the one you set, text is sharp, and no scale error notice appears |
| D10 | N | Speakers and microphone | `speaker-test -c 2 -t wav -l 1`. Then `arecord -d 5 /tmp/mic.wav && aplay /tmp/mic.wav` | Left and right are heard. Your voice plays back |
| D11 | E | Headphone jack | Plug headphones in. Play nothing for 30 seconds, then play and stop a sound | No buzz at idle and no pop when sound starts or stops. If there is one, `echo 0 \| sudo tee /sys/module/snd_hda_intel/parameters/power_save` should stop it until reboot |
| D12 | N | Webcam and privacy switches | `karchy-capture-webcam-list`. Open the camera in a browser test page. Flip both switches. `sudo framework_tool --privacy` | The camera is listed and shows a picture. The switches cut the picture and the microphone, and the tool reports them |
| D13 | N | Function keys | Press F1 to F12 once each, and Fn+Space | Volume, media, brightness, airplane mode (panel shows it) and screenshot work. The keyboard backlight cycles. F9 and F12 do nothing, which is expected |
| D14 | E | Fingerprint | `fwupdmgr get-devices \| grep -A6 -i fingerprint`. Then Setup › Security › Set Up Fingerprint | The reader is listed with a version. Enrolling ends with "Enrolled". The lock screen and a polkit prompt accept the finger. `sudo` asks for the password |
| D15 | N | Wi-Fi band and Bluetooth | `iw reg get \| head -3`. `iw dev \| awk '/Interface/{print $2}' \| xargs -I{} iw dev {} link`. Pair a phone or headphones | Your country, a 5 or 6 GHz frequency, and the Bluetooth device connects |
| D16 | E | Charge limit | `sudo framework_tool --charge-limit 80`, then `sudo framework_tool --charge-limit`. `ls /sys/class/power_supply/BAT1/charge_control_end_threshold` | The tool reports 80. The sysfs file does not exist, and the panel shows no limit. Both are expected (row 15) |
| D17 | N | Firmware list, no flash | Update › Update Firmware | Devices are listed. If System Firmware 3.20 is offered, answer n |
| D18 | N | Power profiles | Switch each profile in the power panel. After each, `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference` | Three different values. `powerprofilesctl list-actions` shows `amdgpu_panel_power` disabled |
| D19 | N | bees follows the charger | `systemctl is-active karchy-bees`, unplug, wait 10 seconds, repeat, plug in, repeat | active, then inactive, then active |
| D20 | E | Video decode | `vainfo`. Play a 4K YouTube video in Brave and open `brave://gpu` | VA-API profiles are listed. Video Decode says hardware accelerated. No `vcn` errors in `journalctl -k` |

### 5.2 First week

| # | | Test | Action | Pass |
|---|---|---|---|---|
| W1 | E | Lid on battery, the real 2 hours | Close the lid on battery in the evening. Open it the next morning | The disk prompt appears. `upower -i $(upower -e \| grep BAT) \| grep percentage` shows a loss of about 3 % or less |
| W2 | E | Lid on AC, then unplug | Close the lid on AC. Unplug after 10 minutes. Wait a little over 2 hours | The disk prompt appears on opening. Left on AC overnight instead, it resumes without the disk prompt |
| W3 | E | Idle suspend | On battery, leave it alone for 20 minutes | It suspends by itself, and later hibernates |
| W4 | E | Resume with Wi-Fi, 20 times | `sudo sh -c 'for i in $(seq 20); do rtcwake -m no -s 40; systemctl suspend; sleep 70; nmcli -t -f STATE general; done'` (about 25 minutes) | 20 lines saying `connected`. `uptime` shows no reboot. `journalctl -b -k \| grep -c "PM: suspend exit"` is 20 or more |
| W5 | N | Suspend drain | Note the percentage. Suspend for 1 hour on battery with the test file from D7 removed. Note it again | About 1.5 % or less. Write the number down with the BIOS version |
| W6 | N | Hibernate with memory full | Start a `karchy vm` and open many browser tabs until `free -h` shows little available. Close the lid on battery with the 3-minute test file | It hibernates and resumes. If it only suspends, `journalctl -b \| grep -i "couldn't hibernate"` says why. That result means the swap file needs headroom (`boot-disk.md` R2) |
| W7 | N | No display freeze | Each day: `journalctl -k -b \| grep -E 'DMCUB\|flip_done\|ttm_resource\|list_del'` | No output all week. If `DMCUB` or `flip_done` appears, apply 4.5 |
| W8 | N | Cost of USB autosuspend off | On battery, idle, screen on at fixed brightness, read the draw in the power panel after 5 minutes. Then mask the rule with `sudo ln -s /dev/null /etc/udev/rules.d/90-karchy-usb-autosuspend.rules`, reboot, repeat, and delete the link | Write both numbers down. A gap above about 0.5 W is worth changing the rule for laptops |
| W9 | E | USB4 dock | Dock on a rear port. `boltctl list`. `cat /sys/bus/thunderbolt/devices/domain0/security`. Use the dock's Ethernet, USB and display. Suspend and resume while docked | The dock is authorized. Everything behind it works before and after the resume |
| W10 | E | Suspend with a VM running | Start a `karchy vm`, then `systemctl suspend` | It suspends within a few seconds and resumes with the VM alive |
| W11 | E | bees soak, laptop part | Use it normally on AC. Hibernate once while `karchy-bees` is active. Compare `map-swapfile -r` before and after | The same offset, a clean `btrfs scrub`, no btrfs warnings in `journalctl -k` |
| W12 | N | Heat and fan | `timeout 120 openssl speed -multi "$(nproc)" sha256 >/dev/null`, with `sudo framework_tool --thermal` in a second terminal | The fan speeds up, temperatures stay below about 100 °C, and the fan slows within a minute or two after the load |
| W13 | N | External display on a card | HDMI or DisplayPort card in a rear or the front-right slot. Connect, suspend, resume, disconnect | The display returns after resume. Unplugging does not hang the session |
| W14 | E | Secure Boot recovery | Only if Secure Boot is on: turn enforcement off in the firmware and boot | Write down whether karchy boots and whether `e` edits an entry |
| W15 | N | A bad-update drill | After a real `karchy update`, boot the pre-update snapshot once and reboot normally | The pre-update snapshot boots. This is the path row 7 depends on |

---

## 6. What I could not verify

- Anything on the laptop itself. No test above has been run.
- Framework's knowledge base. Its pages need JavaScript and returned only titles. I used the Arch Wiki, Framework's `linux-docs` repository and the community threads instead. The expansion-card statements come from the Arch Wiki, which cites that knowledge base page.
- The LVFS device page (HTTP 403). The claim that LVFS stable offers 3.20 rests on a user's `fwupdmgr` output.
- The Ars Technica article with Framework's statement on BIOS 3.20. I read the statement as quoted in thread 84031.
- Whether any BIOS newer than 3.20 exists. A forum search by title on 2026-11-17 showed none.
- Which kernel release fixed the PSR freeze (drm/amd 4141) and the brightness regression (drm/amd 5562). The issue pages block automated readers. I found no report for 7.3 in either direction.
- The exact labels in the firmware's Secure Boot menu.
- Which audio subsystem ID this board reports, and whether the internal microphone needs a profile.
- Which driver exposes the ambient light sensor on this board.
- The CachyOS wiki. I did not find a Framework page there and did not search further. CachyOS-specific facts above come from the kernel config and packages on this host.
- The `+=` line in 4.5 and the steps in 4.6. They follow the tool's documentation and karchy's installer, and nobody has run them.

## 7. Sources

- karchy: `install/*.sh`, `system/laptop/`, `packaging/pkgbuilds/karchy-laptop/PKGBUILD`, `bin/karchy-secureboot`, `bin/karchy-setup-security-fingerprint`, `bin/karchy-battery-status`, `bin/karchy-hibernation-available`, `bin/karchy-hyprland-monitor-scaling`, `default/hypr/bindings/media.lua`, `karchy/hypr/bindings.lua`, `.agents/TESTING.md`, `.agents/DECISIONS.md`, the audits in `.agents/research/docs-audit/`, and `.agents/research/pre-laptop/01-earlier-audits-status.md`.
- This host: `/proc/config.gz` and `modinfo` for `linux-cachyos` 7.3.3, `pacman -Si`, `/usr/share/doc/limine-entry-tool/README.md`, `/usr/share/doc/limine-snapper-sync/README.md`.
- Arch Wiki, raw pages: "Framework Laptop 13" (revision of 2026-11-05) and "Framework Laptop 13 (AMD Ryzen 7040 Series)" (revision of 2026-05-08).
- Linux master (7.4-rc3): `drivers/rtc/rtc-cmos.c`, `drivers/power/supply/cros_charge-control.c`, `drivers/platform/x86/amd/pmc/pmc-quirks.c`, `drivers/platform/chrome/cros_ec_lpc.c`, `sound/hda/codecs/realtek/alc269.c`, `lib/fonts/fonts.c`.
- systemd v262 `src/sleep/sleep.c`. Hyprland main `src/output/Monitor.cpp`. power-profiles-daemon main `README.md`.
- CVE-2026-98166, from `cveawg.mitre.org`.
- Framework: `FrameworkComputer/linux-docs` (the 7040 Fedora guide, `fwupd.md`, `FPR-320-firmware`, `disable-accidental-wakeup`), `FrameworkComputer/framework-system` (`README.md`, `EXAMPLES.md`), `DHowett/framework-laptop-kmod` `README.md`.
- NixOS/nixos-hardware: `framework/13-inch/7040-amd/default.nix`, `framework/13-inch/common/amd.nix`, `framework/13-inch/common/default.nix`, `framework/kmod.nix`, `common/gpu/amd/dc-debug-mask.nix`.
- community.frame.work threads, by number: 83283 (BIOS 3.20), 84031 (3.20 bricking), 79967 (BIOS 3.18), 78216 (BIOS 3.17), 82594 (Bluetooth on 7.0.7), 82167 and 80423 (display freezes), 84507 (freeze after hibernate), 84042 (brightness), 84910 (USB4 and bolt), 40316 and 84603 (MT7922), 85399 (video decode), 84317 (AC detection). Read as `https://community.frame.work/raw/<number>`.
- drm/amd issues 3647, 4141, 5387 and 5405: titles, states and dates from the GitLab API.
