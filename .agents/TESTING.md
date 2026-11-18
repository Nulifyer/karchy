# Testing and evidence

## Evidence standard

- A milestone closes only on a fresh install in the target environment, with the evidence saved under `docs/evidence/<milestone>/`: the install log, screenshots, and a filled checklist with the date and karchy commit.
- Static checks (shellcheck, `bash -n`, `hyprctl configerrors`) show that files parse. They don't show that a feature works.
- Results from the VM don't cover NVIDIA, fingerprint, suspend or docking. Phases 4 and 5 test those on hardware.
- A checklist item passes only when it was observed in that run. Items that are untested or skipped stay unticked, with a reason.

## Milestone 1 checklist (VM boots to a working desktop)

Environment: QEMU/KVM on this host, UEFI (OVMF), virtio-gpu with 3D (virgl), and a virtual disk of at least 40 GiB.

- [ ] From the stock Arch ISO, the karchy installer form runs an unattended install with no other manual steps.
- [ ] After reboot: the LUKS text prompt, then greetd auto-login, then Hyprland with the Omarchy shell bar.
- [ ] Super+Return opens foot, Super+E opens Thunar, Super+Space opens the menu, and Alt+F4 closes a window.
- [ ] Super+L locks and unlocking works; Super+Escape opens the power menu.
- [ ] Print and Super+Shift+S take screenshots.
- [ ] A notification and a polkit password prompt both appear.
- [ ] A theme switch changes the shell, Hyprland and foot.
- [ ] After a change in the checkout and a rebuild, `karchy update` installs only the changed karchy packages and the session picks up the change.
- [ ] Only the chosen packages are installed: `pacman -Qqe` is `install/packages/base.txt` plus microcode and `karchy-desktop` (and the detected metas).

## Fast checks

```text
shellcheck tools/vm          # extend to install/ and karchy's own bin/ as they land
tools/quick-install-search-check   # the Quick install window's search ranking, against the real list
```

## Full checks

```text
tools/vm fetch                       # download + verify (sha256 and Arch keyring signature) the Arch ISO
tools/vm new [--secureboot] [--tpm]  # 40 GiB qcow2 + blank UEFI vars (Setup Mode), defined in libvirt as karchy-<vm>
tools/vm run --iso [--headless]      # boot the ISO and open the console in virt-manager; repo shared read-only as 9p tag "karchy"
tools/vm screenshot <file.png>       # evidence screenshots via virsh
tools/vm type <text> / key <combo>   # drive the VM for unattended checks
tools/vm click <x> <y>               # click at a screenshot pixel
tools/vm exec [--user] <command>     # run in the guest (as root, or in the desktop session) via the guest agent
tools/vm stop [--force]              # clean shutdown; --force pulls the plug (recent guest writes can be lost)
tools/vm snap/restore <name>         # retry installs from a known state
tools/vm repo                        # serve out/repo-<channel> (from packaging/build) to guests at http://10.0.2.2:8090
```

Inside the live ISO: `mount -t 9p -o trans=virtio,version=9p2000.L,ro karchy /root/karchy` (not under `/mnt`, which the installer mounts over), then `/root/karchy/install/karchy-install --config /root/karchy/tests/vm-install.conf`. Build the packages first with `packaging/build`.

Dev mode in a test VM (D-55), to try shell and command changes without rebuilding packages: add `karchy /mnt/karchy 9p trans=virtio,version=9p2000.L,ro,nofail 0 0` to the guest's fstab and `KARCHY_PATH=/mnt/karchy` to `/etc/karchy.conf`, reboot, then `karchy-restart-shell` after each change. System files still come from the packages.

## Environment

- Host: CachyOS with KDE Plasma, RTX 5080, 31 GiB RAM. Test VMs are libvirt domains on `qemu:///system` (the user is in the `libvirt` group), visible in virt-manager. `tools/vm` needs libvirt, virt-manager, qemu-desktop, edk2-ovmf, acl (setfacl), imagemagick, gpg and archlinux-keyring, and swtpm for `--tpm`.
- VM files: `${KARCHY_VM_DIR:-~/.local/state/karchy-vm}`. Override the VM size with `KARCHY_VM_CPUS`, `KARCHY_VM_MEMORY` and `KARCHY_VM_DISPLAY`.
- Install media: the current stock Arch Linux ISO, from `geo.mirror.pkgbuild.com/iso/latest`.

## Known gaps

- The VM cannot test NVIDIA, fingerprint, laptop power or suspend, real docking, or Wi-Fi.

## Project notes

- Phase 2 extends this checklist to everything in `docs/components.md`, `docs/keybindings.md` and `docs/menu.md`, and adds:
  - Secure Boot in the VM using `OVMF_CODE.secboot.4m.fd`: enroll, boot signed, and boot a snapshot entry.
  - Hardware detection: a VM with no battery and no NVIDIA gets none of the Detected-tier packages.
  - The Settings window: a hand edit overrides a GUI value.
  - A mirror-ranking failure, simulated, keeps the old list.
  - The LocalSend port is open on a trusted network and closed on an untrusted one.

## On the real machines (from the docs audit, D-79)

Things a VM can't show. Write down what happened for each.

Both machines:
- Boot a snapshot from the Limine menu: the desktop comes up (writable overlay), then reboot normally.
- `vainfo` and brave://gpu show hardware video decode.
- A data disk: mounted at boot; the 3.6 TB disk comes up without "timed out waiting for device" (`journalctl -b`).
- Secure Boot recovery, before relying on it: what turning Secure Boot off in the firmware does to booting, written down.

Desktop (RTX 5080, Ryzen 7 3700X):
- `pacman -Q linux-cachyos` comes from `cachyos-v3`.
- Firmware: Update Firmware lists devices; with Secure Boot on, a BIOS update applies (the signed `fwupdx64.efi.signed` is used).
- Both monitors at their full refresh rate; HDMI color and refresh look right; VRR and 10-bit where the monitors take them.
- Suspend and resume work; Hibernate is not offered. To check NVIDIA issue #1343 once a driver says it's fixed: save everything, then follow the test in .agents/research/docs-audit/nvidia-hibernation.md (resume keeps the session, `boot_id` unchanged, no `nv_pmops_freeze -5`).
- Idle VRAM use (`nvidia-smi`) with the desktop running; only act if it's gigabytes.
- If the CPU's integrated GPU is enabled, Hyprland draws on the NVIDIA card.
- bees soak test (D-83, D-86), after a snapshot and a NAS backup: install with the default (bees on), use the machine normally for a week on linux-cachyos 7.x; `journalctl -k` shows no btrfs warnings or hung tasks, `btrfs scrub` is clean, and `karchy-bees.service` keeps running. Also: hibernate and resume while bees is deduplicating, and `btrfs inspect-internal map-swapfile -r /swap/swapfile` gives the same offset before and after.

Framework 13 AMD (commands and pass criteria for most lines: `.agents/research/pre-laptop/03-framework-readiness.md` §5):
- `pacman -Q linux-cachyos` comes from `cachyos-znver4` (Ryzen 7040).
- First boot: run the command block in `03-framework-readiness.md` §3.3 (failed units, kernel versions, command line, swap and resume offset, sleep states, power profiles); every line matches its comment. Then take a named snapshot.
- Firmware: Update Firmware lists devices; decline System Firmware 3.20 (bricked boards reported, see `03-framework-readiness.md`).
- Back up the LUKS header to the NAS (`docs/recovery.md`).
- Wi-Fi: the network joined on the install media connects at the first boot without asking (the installer carries it over; a real connect was never tested in a VM). Then connect to another network from the network panel, reboot, and confirm it reconnects. `iw reg get` shows your country and the link is on 5 or 6 GHz.
- Bluetooth: pair headphones and a mouse; check the headset microphone.
- Speakers and internal microphone: `speaker-test -c 2 -t wav -l 1` plays left and right; `arecord -d 5 /tmp/mic.wav && aplay /tmp/mic.wav` plays your voice back.
- Webcam, speakers and microphone in one Brave video call; the two privacy switches cut the picture and the microphone (`sudo framework_tool --privacy`).
- Share a screen and a window in that call.
- Function row: brightness through its range (100 % is brighter than 95 %), keyboard backlight (Fn+Space), volume, media and the airplane key. F9 and F12 do nothing, which is expected.
- Touchpad: tap, two-finger scroll, the 3-finger swipe, palm rejection while typing.
- Display scale: `hyprctl monitors` shows 2 or the scale set in Settings › Displays, text is sharp; Steam or another X11 app has a usable size at that scale.
- Play a 10-minute video in Brave and in mpv on battery: the screensaver, lock and suspend do not start.
- s2idle reaches hardware sleep: on battery, `systemctl suspend`, wait 10 minutes, wake; `cat /sys/power/suspend_stats/last_hw_sleep` is close to 600000000.
- Power profiles: each profile in the power panel changes `energy_performance_preference`; `powerprofilesctl list-actions` shows `amdgpu_panel_power` disabled.
- bees follows the charger: `systemctl is-active karchy-bees` is active on AC, inactive 10 seconds after unplugging, active again when plugged in.
- Plug in a USB stick: a notification appears and Thunar shows it; eject it. Plug in a phone: Thunar shows its storage (MTP).
- External monitor: plug, unplug, mirror, close the lid, undock while asleep.
- Start one app that adds itself to autostart; log out and in: it starts and shows in the tray.
- After the snapshot boot above, make the snapshot permanent with `sudo limine-snapper-restore` (`docs/recovery.md`) and reboot: a package installed after the snapshot is gone and the system boots.
- Realtime audio: `grep 'Max realtime timeout' /proc/$(pgrep -x quickshell)/limits` shows no hard limit of 0.
- Idle power on battery with and without `90-karchy-usb-autosuspend.rules`; write both numbers down.
- Secure Boot, if the install was done without it (`03-framework-readiness.md` §1.3 recommends that for the first week): clear the keys in the firmware, run `karchy secureboot setup`, restart; `sbctl status` shows Secure Boot enabled.
- Lid on battery: suspend, then hibernate after 2 h; lid on AC, unplug, wait 2 h: it hibernates.
- Idle suspend on battery; resume with the Wi-Fi card (MT7922) working, no reboot instead of resume.
- Headphone jack: no buzz or pop at idle (if there is, `snd_hda_intel power_save=0` for Framework).
- Night light: the switch in the display panel visibly warms the screen; the schedule turns it on and off; it comes back after suspend.
- Settings › Power: close the lid on battery and plugged in with each choice; the hibernate delay with a short value; the screen-off, lock and sleep times on each power source.
- Stay Awake on: the screen stays on past the idle times; off: it locks again. Do Not Disturb on: a chat notification stays off screen.
- Fingerprint: lock screen and polkit prompts take it, sudo asks for the password.
- A USB4 dock: Ethernet and USB behind it work (bolt).
- Suspend with a VM running.
- Charge limit set in the BIOS or with `sudo framework_tool --charge-limit 80`: `sudo framework_tool --charge-limit` reports 80 and charging stops there. The battery panel shows no limit and `/sys/class/power_supply/BAT1/charge_control_end_threshold` does not exist; both are expected (the kernel's charge-control driver does not load on Framework, `03-framework-readiness.md` row 15).
- Console text at the disk password prompt is readable, and no kernel or boot message prints over it (quiet boot).
