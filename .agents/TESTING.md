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
tests/installer-network.sh         # the installer's Wi-Fi list from scan text, the network kept from a wpa_supplicant join, and that the network is asked for before the keyring
tools/quick-install-search-check   # the Quick install window's search ranking, against the real list, and its sentence about the last install; `bun tools/quick-install-search-check` where node won't start
python3 tests/keybindings.py       # karchy-settings-keybindings: keys, layers, rules, the generated Lua; with lua installed, karchy's real Lua layer under a stand-in Hyprland
bun tests/keybindings-model.js "$PWD"   # Settings › Keybindings: key capture, search, filters, grouping
lua tests/window-stacking.lua      # which window is in front and where Alt+Tab goes (D-159): the real stacking.lua, window-switch.lua and workspace-modes.lua under a stand-in Hyprland that keeps the stacking order and the focus history
bun tests/menu-search.js "$PWD"    # the menu: the root rows, every search alias finds its Settings page, what loose typing no longer finds (D-136), en/menu.json agrees
bun tests/notifications-panel.js "$PWD"   # the notifications panel: sections, groups, the names apps are listed under
bun tests/storage-model.js "$PWD"  # Settings › Storage: sizes, the live figures, the overview's tiles, the stack and subvolume rows
bun tests/network-model.js "$PWD"  # the network panel: the internet through the VPN (never "No internet" while it protects), a WireGuard tunnel's health and its words
tests/settings-power.sh            # Settings › Power (D-160): karchy-settings-power, karchy-powerprofiles-set, karchy-power-source and the root helper on a made-up laptop and desktop in a user namespace (stand-in UPower, logind, power-profiles-daemon and backlight; the real systemd-analyze). `--machine <dir> laptop|desktop <command>` keeps such a machine to try a command or the page on
tests/vesktop-theme.sh         # the Vesktop (Discord) theme: every theme renders to CSS, and karchy-theme-set-vesktop in a made-up home (no Vesktop, first start, a theme of the user's own, turned off, running, a linked settings file); with a folder of Discord's stylesheets as second argument, the colour map against them
tests/vpn-setup.sh                 # karchy-network-vpn: setup's configuration and refusals, and remove turning the VPN off first for its own profile (stand-in nmcli and karchy-vpn)
tests/storage-helpers.sh system/storage   # Storage's root side: what the helpers refuse, and how they read bees, SMART and the subvolume list
tests/agent-skills.sh        # karchy-agent-skills in a made-up home (never run the command against a real home to test it), and each skill packaged once
tests/users-settings.sh system/users/users-settings   # Settings › Users' root helper as a user: what it turns away, and, in a user namespace with a made-up /etc, the rules between several people and the greetd file automatic login writes
podman run --rm --user 0 -v "$PWD":/repo:ro localhost/karchy-build:<hash> bash /repo/tests/users-accounts.sh   # the same helper making real accounts, as root in a throwaway container (it refuses to run anywhere else)
tests/keyring-login.sh       # the login keyring's root hook (D-142), in a user namespace with a made-up /etc and a made-up oo7-cli: what it refuses, both directions, every interrupted state, the stale key; and the helper's mark and wish for automatic login. One check waits 10 seconds for the hook's time limit
tests/app-packages-rule.sh   # the apps' own packages (D-150): the same rule in the three places that install apps, what the PKGBUILD makes from the catalog, and Quick install's status against a made-up pacman
tests/app-packages-container.sh   # the root helper with the real pacman in a stock Arch container (podman, about 150 MB): an app's package in and out with what came along, a part asked for by name, the refusal, an entry that became one package. Needs out/repo-dev from packaging/build
tools/keyring-check          # the same lock change against the real oo7 of today's repositories, in a stock Arch container (podman): a keyring made with a key takes a password and the key back, keeps its secrets, and reads as locked with a wrong secret. On every push and in the daily upkeep
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

- The VMs have QEMU's iTCO watchdog (libvirt adds it to q35 machines, action reset). A watchdog left running survives a forced reset: systemd arms it for 10 minutes on the way into a reboot, so a reboot that hangs and is then forced can reset the VM again up to 10 minutes later, in the middle of the next boot. Look for `event 'watchdog'` in `virsh event --domain karchy-<vm> --all --loop` before blaming the guest.

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
- The Limine menu's letters (D-154) read as JetBrains Mono, with even stems and no missing parts, and the tree's lines join; with Secure Boot set up the menu still shows karchy's font, not Limine's wide one (the font's hash is enrolled with the config).
- `vainfo` and brave://gpu show hardware video decode.
- A data disk: mounted at boot; the 3.6 TB disk comes up without "timed out waiting for device" (`journalctl -b`).
- Secure Boot recovery, before relying on it: what turning Secure Boot off in the firmware does to booting, written down.

Desktop (RTX 5080, Ryzen 7 3700X):
- `pacman -Q linux-cachyos` comes from `cachyos-v3`.
- Firmware: the Updates window's "Check for firmware updates…" lists devices; with Secure Boot on, a BIOS update applies (the signed `fwupdx64.efi.signed` is used).
- Both monitors at their full refresh rate; HDMI color and refresh look right; VRR and 10-bit where the monitors take them.
- Suspend and resume work; Hibernate is not offered. To check NVIDIA issue #1343 once a driver says it's fixed: save everything, then follow the test in .agents/research/docs-audit/nvidia-hibernation.md (resume keeps the session, `boot_id` unchanged, no `nv_pmops_freeze -5`).
- Idle VRAM use (`nvidia-smi`) with the desktop running; only act if it's gigabytes.
- If the CPU's integrated GPU is enabled, Hyprland draws on the NVIDIA card.
- bees soak test (D-83, D-86), after a snapshot and a NAS backup: install with the default (bees on), use the machine normally for a week on linux-cachyos 7.x; `journalctl -k` shows no btrfs warnings or hung tasks, `btrfs scrub` is clean, and `karchy-bees.service` keeps running. Also: hibernate and resume while bees is deduplicating, and `btrfs inspect-internal map-swapfile -r /swap/swapfile` gives the same offset before and after.

Framework 13 AMD (commands and pass criteria for most lines: `.agents/research/pre-laptop/03-framework-readiness.md` §5):
- `pacman -Q linux-cachyos` comes from `cachyos-znver4` (Ryzen 7040).
- First boot: run the command block in `03-framework-readiness.md` §3.3 (failed units, kernel versions, command line, swap and resume offset, sleep states, power profiles); every line matches its comment. Then take a named snapshot.
- Firmware: the Updates window's "Check for firmware updates…" lists devices; decline System Firmware 3.20 (bricked boards reported, see `03-framework-readiness.md`).
- Back up the LUKS header to the NAS (`docs/recovery.md`).
- Wi-Fi on the install media (D-153): on the Framework's MT7922 iwd's join fails after `associated`; the installer should show "Trying another way to join..." and get to the form. Not yet run on the laptop from a built ISO.
- Wi-Fi: the network joined on the install media connects at the first boot without asking (the installer carries it over; a real connect was never tested in a VM). Then connect to another network from the network panel, reboot, and confirm it reconnects. `iw reg get` shows your country and the link is on 5 or 6 GHz.
- Bluetooth: pair headphones and a mouse; check the headset microphone.
- Speakers and internal microphone: `speaker-test -c 2 -t wav -l 1` plays left and right; `arecord -d 5 /tmp/mic.wav && aplay /tmp/mic.wav` plays your voice back.
- Webcam, speakers and microphone in one Brave video call; the two privacy switches cut the picture and the microphone (`sudo framework_tool --privacy`).
- Share a screen and a window in that call.
- Function row: brightness through its range (100 % is brighter than 95 %), keyboard backlight (Fn+Space), volume, media and the airplane key. F9 and F12 do nothing, which is expected.
- Touchpad: tap, two-finger scroll, the 3-finger swipe, palm rejection while typing.
- Display scale: `hyprctl monitors` shows 2 or the scale set in Settings › Displays, text is sharp; Steam or another X11 app has a usable size at that scale.
- Play a 10-minute video in Brave and in mpv on battery: the screensaver, lock and suspend do not start.
- Play music (a player, or a Brave tab with only sound) on battery past the idle suspend time: the screen locks and goes dark but the laptop stays awake; pause it and it suspends (D-110).
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
- Settings › Power by power source (D-160; so far only run against stand-ins): the page shows "On battery" beside "Plugged in" with "(now)" on the right one, and it moves when the charger goes in or out.
  - Power mode: set Power saver on battery and Performance plugged in; pull the charger: within a second or two `powerprofilesctl get` says `power-saver` and `cat /sys/devices/system/cpu/cpu0/cpufreq/energy_performance_preference` changes; plug in: `performance`. Setting the mode of the source not in use leaves `powerprofilesctl get` alone. A mode picked in the bar's power panel shows in Settings and the other way round.
  - Screen brightness: set 40% on battery and 100% plugged in; pull the charger and plug it in: the screen follows each time (`karchy brightness display`), the brightness keys still work, and nothing changes it again until the next plug or unplug, also not suspend or a restart. With "Leave as it is" the screen stays as it was.
  - Power saver at low battery: with "Switch to Power saver" chosen and the warning at a level just under the present charge (Warn at 30%), run on battery until the warning shows: `powerprofilesctl get` says `power-saver`, the page says another mode is running, the battery's own mode is still shown as chosen; plugging in brings the plugged-in mode back, and unplugging above the level the battery's own. Log in on battery under the level: Power saver from the start.
  - Hibernation while plugged in: with "Then hibernate after" 5 minutes (`karchy-settings-power set hibernateAfter 5`) and Plugged in "Not while plugged in", close the lid on the charger for 10 minutes: it wakes from suspend, not from hibernation (`journalctl -b -u systemd-suspend-then-hibernate`); with the same time chosen for plugged in, it hibernates. Set the delay back afterwards.
  - Unplug and plug in quickly several times: the mode and brightness end at the source in use (`karchy-shell battery status`, `journalctl --user -b | grep -i power`).
- Stay Awake on: the screen stays on past the idle times; off: it locks again. Do Not Disturb on: a chat notification stays off screen.
- Sleep with a share open: open a NAS share in Thunar, play a file from it in mpv, close the lid on Wi-Fi: it sleeps, and the share opens again after wake. After wake, `ip -4 addr` shows an address.
- Disk warnings: `sudo smartd -q onecheck` with `-M test` appended to the DEVICESCAN line in `/etc/smartd.conf` shows a "Disk warning test" notification per disk.
- Share a whole screen and a single window from a call in Brave; the picker lists both.
- Steam at the panel's scale is neither tiny nor blurry; one Proton game runs, and the screen doesn't lock while it is fullscreen.
- KDE Connect pairs with a phone on the trusted home network and not on an untrusted one.
- Boot a snapshot: the notice names it; "Restore this snapshot" restores it.
- Fingerprint: Settings › Security shows Fingerprint with "Set up…"; after enrolling there the row reads "Set up", the lock screen and polkit prompts take it, sudo asks for the password; Remove puts the password back.
- Settings › Keybindings on the laptop's own keyboard: change a binding, capture a media key (it is saved by keycode) and a Super combination; the key caps match what is printed on the keys.
- A USB4 dock: Ethernet and USB behind it work (bolt).
- Suspend with a VM running.
- Charge limit set in the BIOS or with `sudo framework_tool --charge-limit 80`: `sudo framework_tool --charge-limit` reports 80 and charging stops there. The battery panel shows no limit and `/sys/class/power_supply/BAT1/charge_control_end_threshold` does not exist; both are expected (the kernel's charge-control driver does not load on Framework, `03-framework-readiness.md` row 15).
- The disk-password splash appears at the panel's own resolution, sharp, with the box in the middle; a wrong password says so; the desktop follows without text in between. With `plymouth.enable=0` the text prompt is readable, and no kernel or boot message prints over it (quiet boot).
- Settings › Storage (D-104): the NVMe drive shows health, wear and temperature; "Measure now" finishes and the figures look sane against `sudo compsize -x / /home`; note how long it takes (`seconds` in `/var/lib/karchy/storage/measurement.json`); the figures at the top of each volume move within seconds while a large file is copied, and `systemctl list-timers` shows no storage timer (D-123); an expansion-card or USB drive mounts, unmounts and ejects from the page.
