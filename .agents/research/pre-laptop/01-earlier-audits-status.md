# Status of the three 2026-11-14 audits, before the laptop install

Date: 2026-11-17. Read-only check of `main` at `c094573` (clean tree, 72 commits since 2026-11-14).

Audits checked, all in `.agents/research/`:
- `audit-distros.md` ("distros" below)
- `audit-settings.md` ("settings" below)
- `audit-usage.md` ("usage" below)

Rules used:
- DONE means I read the code, package list or config that does it. A doc line alone did not count.
- DECIDED means a decision row or a binding doc rejects or defers the item.
- STILL OPEN means nothing in the repo addresses it.
- UNCLEAR means the repo cannot answer it. Each one says what I looked for.

Nothing here was tested on hardware. `.agents/STATUS.md` says the same: "Nothing yet on real hardware".

## 1. Summary

| Audit | DONE | DECIDED or DEFERRED | STILL OPEN | UNCLEAR |
|---|---|---|---|---|
| distros | 28 | 5, plus the audit's own skip list (followed) | 20 | 0 |
| settings | 4 | 4, plus the audit's own skip list (followed) | 17 | 1 |
| usage | 11 | 2 (one is a group of 14 "user installs" rows) | 5 | 2 |

Three open items appear in two audits each (Stay awake, `tzupdate`, the Framework microphone). That leaves 39 different open items: 3 in class A, 7 groups in class B, the rest in class C.

How the work since 2026-11-14 landed:
- The distros audit is mostly done. Its bug list (section 0) is fully fixed, and the `etc/` tuning set shipped.
- The settings audit is mostly not done. Settings got Network, SSH and display color controls, but the Power page and every finding around it (F2 to F7) are untouched.
- The usage audit is mostly done through Quick install (D-70), which now carries almost every app the audit told the user to install by hand.

Two stale lines in the records, found on the way:
- `.agents/STATUS.md:122` still lists the `etc/` tuning list under "Needs the user". `docs/ownership-audit.md:97` says every row is decided, and the files are in `system/`.
- `.agents/STATUS.md:115` says Keep This Mount is not built. `bin/karchy-mount-keep` exists and D-76 moved it to the menu.

## 2. Still open and unclear

### A. Would hurt on day one

**A1. The Framework 13 AMD internal microphone may be silent.**
- Raised in: distros section 1b (row "F13 AMD internal-mic profile") and section 4 Detected item 3. Also usage, Hardware table ("check the Framework's internal microphone on first boot").
- What it is: Omarchy sets the card profile "HiFi (Mic1, Mic2, Speaker)" on this laptop. Without it the internal microphone may not be the active input.
- Checked: no WirePlumber rule, `pactl` call or profile name anywhere in `system/`, `config/`, `default/`, `bin/` or `install/`. `karchy-laptop` now depends on `sof-firmware`, which is a different fix. The hardware list in `.agents/TESTING.md` has no microphone check. The audio panel has no card profile picker.
- Suggestion: add "internal microphone records" to the Framework list in `TESTING.md`. If it fails, ship a WirePlumber rule from `karchy-laptop`, gated on the Framework DMI check in `install/setup.sh:26`.

**A2. The first boot has no Wi-Fi, and nothing says so.**
- Raised in: distros section 1a ("First-login no network prompt") and section 4 Base item 8.
- What it is: the ISO connects with `iwctl` (`packaging/iso/airootfs/usr/local/bin/karchy-iso-start:41-46`). The installer does not copy that network to the installed system. The Framework has no Ethernet port without an expansion card.
- Checked: no `iwd`, `system-connections` or `nmconnection` handling in `install/`. `karchy/hypr/autostart.lua` runs disk, Secure Boot and renderer checks at login, but no network check.
- Suggestion: at install, write the live ISO's network as a NetworkManager keyfile. The cheaper option is a login notification that opens the network panel when no connection is up.

**A3. Kernel messages can overwrite the disk password prompt on every boot.**
- Raised in: distros section 2a (row `kernel.printk`) and section 4 Base item 10.
- What it is: karchy boots a plain text console with no Plymouth (D-12). The kernel command line has no `quiet` or `loglevel`.
- Checked: `install/base.sh:301-303` builds the command line: `rw rootflags=… rd.luks… zswap… resume=…`. Nothing else. `TESTING.md:97` checks that the prompt text is readable, which is about font size.
- Suggestion: add `quiet loglevel=3` to the command line in `install/base.sh`. One line, and it also applies to snapshot entries.

### B. Will be missed within weeks

**B1. There is no Settings › Power page.**
- Raised in: settings sections 1.1, 1.2 and section 4 priority 1, with findings F4 and F7.
- What it is: lid action, sleep and screen-off times, hibernate delay, power button action and power profile per source have no controls. The defaults work, but changing one means editing `shell.json` or writing a systemd drop-in.
- Checked: `shell/plugins/settings/Settings.qml:36-44` lists Displays, Input, Network, SSH, Appearance, Default apps and About. No `karchy-settings-power` in `bin/`. `docs/components.md:105` says "more sections (Power, Printers) follow in phase 2". F4 holds: the screen turns off only from the lock (`shell/plugins/lock/Service.qml:262-269`). F7 holds: the section list is fixed, with nothing hidden per machine.
- Suggestion: build the page as the audit laid it out, with `~/.config/karchy/power.json` and a pkexec helper for the logind and sleep drop-ins.

**B2. Stay awake and Do Not Disturb have working code and no way to reach them.**
- Raised in: settings F3 and section 4 priority 2. Also distros section 1c ("Stay-awake indicator, DND indicator").
- What it is: a presentation, a long download or a screen share needs one of these. Today the only route is a shell IPC call or a state file.
- Checked: `shell/plugins/bar/indicators/` holds Minimized, Reminder, ScreenRecording and Updates only. `toggleDnd` exists at `shell/plugins/notifications/Service.qml:1404`, and line 61 says "nothing on screen says the desktop is quiet". The Stay awake state is at `shell/plugins/services/idle/Service.qml:17-45`. No menu row, binding or Settings switch calls either. `docs/menu.md:37` dropped the Toggle menu on purpose, so this needs the user's approval (D-17, D-18).
- Suggestion: add the two switches to the power and notification panels and bring back the two bar indicators. Otherwise remove the unreachable state.

**B3. One Settings change freezes the whole shell config.**
- Raised in: settings F6.
- What it is: a user `shell.json` replaces karchy's defaults entirely. Settings › Appearance now writes that file, so the first change to the bar style or the lock screen clock saves a full copy. Later updates to the default bar layout or idle values then stop reaching that machine. This breaks D-56 ("only changed values are saved").
- Checked: `shell/shell.qml:83-100` ("We do not deep-merge"). `mutateShellConfig` copies the full config and `persistShellConfig` writes it (`shell/shell.qml:120-128`, `177-181`). `AppearanceSection.qml:130` and `:147` both go through that path.
- Suggestion: save only the changed keys and merge them over the defaults at load. Do it before the laptop install, or the laptop keeps the bar layout of install day.

**B4. Battery warnings stop at one notice at 10%.**
- Raised in: settings F2 and section 4 priority 9.
- What it is: one hard-coded warning, no automatic power saver at a set level, and the action at critical level is UPower's packaged default, which karchy neither sets nor checks. `docs/components.md:142` still claims "low and critical warnings".
- Checked: `shell/plugins/services/battery/Service.qml:14` (`batteryThreshold: 10`). No UPower drop-in in `system/` or `packaging/`.
- Suggestion: ship a UPower drop-in with `CriticalPowerAction=Hibernate` from `karchy-laptop`, and add a second warning. Correct the components line either way.

**B5. USB sticks and other modules fail after a kernel update until restart.**
- Raised in: distros section 1a (`linux-modules-cleanup`) and section 4 Base item 2.
- What it is: pacman deletes the running kernel's modules on upgrade. Choosing "Later" at the restart question leaves a session that cannot load `exfat`, `uas` or a USB network driver. CachyOS kernels update often.
- Checked: no `kernel-modules-hook` or `linux-modules-cleanup` in any package list or the installer. `karchy update` does offer a restart when the kernel changed (`bin/karchy-update:202`, `:443-448`), which covers only the "Restart now" answer.
- Suggestion: add `kernel-modules-hook` to `karchy-desktop` and enable `linux-modules-cleanup.service` in `install/setup.sh`.

**B6. Bluetooth pairing has no agent for passkey devices.**
- Raised in: distros section 1a (`bt-agent`) and section 4 Base item 11.
- What it is: headsets and mice pair without a code. Keyboards and some phones ask for a passkey or a confirmation, and nothing answers.
- Checked: `bin/karchy-bluetooth-device:35` runs `timeout 20s bluetoothctl pair … >/dev/null 2>&1 || true`. No `bluez-tools` or `bt-agent` anywhere. The audit asked for a test first. The hardware list in `TESTING.md` has no Bluetooth item.
- Suggestion: pair a keyboard and a phone on the laptop. If it fails, ship `bt-agent` as a user unit.

**B7. Suspend can fail with a network share open in the file manager.**
- Raised in: distros section 1a ("Unmount gvfs FUSE before sleep") and section 4 Base item 7.
- What it is: karchy ships gvfs and gvfs-smb. A hung `gvfsd-fuse` can make suspend fail without a message, and a laptop suspends many times a day. Kept shares use a kernel CIFS automount and are not affected.
- Checked: `system/systemd/system-sleep/` holds only `fprintd-resume`.
- Suggestion: port Omarchy's `default/systemd/system-sleep/unmount-fuse` into `karchy-settings`.

**Dropped on purpose, but likely to be missed on a laptop: night light.** `.agents/PLAN.md:44` and `docs/components.md:60` drop it, so its class is DECIDED. The settings audit (section 3, priority 5) asked to bring it back with `hyprsunset` and noted that no reason was recorded. No decision row answers that request.

### C. Nice to have

| Item | Raised in | What I checked | Suggestion |
|---|---|---|---|
| Automatic timezone (`tzupdate`) | settings F1, distros section 4 Detected 4 | Not installed. `docs/components.md:142` now says it is not built and needs a decision (AUR only, asks a web service for the location) | The user decides. The Wi-Fi country follows the timezone, so a manual Set Timezone is needed when travelling |
| Keyboard layouts in Settings | settings F8, priority 6 | `InputSection.qml` has compose key, repeat and pointer rows only. The layout follows the installer's keymap (`install/base.sh:221-231`) | Add only if a second layout is needed |
| Date and time block in Settings | settings priority 7 | Menu has Set Timezone and Sync Clock. No Settings block | Fold into a later page |
| Bar block in Appearance | settings priority 10 | Only the bar style is there (`AppearanceSection.qml:117-136`). Position, background, battery percent and clock format need `karchy-bar` | Needs B3 fixed first |
| Startup apps list | settings priority 11 | No UI. No file mentions `~/.config/autostart` | Low priority |
| Update history | settings priority 11 | `shell/plugins/updates/` has no history view | Low priority |
| Cursor size | settings priority 11 | Fixed at 24 in `default/hypr/envs.lua:8-9` | Add to Appearance |
| Account page, audio card profiles | settings section 2.1 and 2.2 | Neither exists | Audio profiles would also give a manual fix for A1 |
| Idle sleep on a machine without a battery | settings F5 | `suspendNow` still requires `hasBattery` (`services/idle/Service.qml:33`) | Desktop only. Fix with the Power page |
| `ttf-liberation` in the base install | usage, Desktop basics | Not a dependency. Quick install has it as `liberation-ms-core-fonts` | One click for the user, or add to `karchy-desktop` |
| `exfatprogs` | distros section 1c | Not a dependency and not in the catalog. Only `dosfstools` and, for NTFS disks, `ntfsprogs` | Add to `karchy-desktop`. GNOME Disks cannot format exFAT without it |
| `mpv-mpris` | distros section 1c | Not a dependency and not in the catalog | Add next to `mpv`, or the media keys cannot see mpv |
| Writeback caps for slow disks | distros section 2a | `system/udev/` has the scheduler and USB autosuspend rules only | Port `61-writeback-limits.rules` |
| THP shrinker and defrag setting | distros section 2a | `system/tmpfiles.d/karchy.conf` has lock files only | Two tmpfiles lines |
| `nmi_watchdog=0` and the watchdog blacklist | distros section 2a | Not in `system/sysctl.d/` or any modprobe file | Small battery saving |
| `kernel.sysrq=1` | distros section 2a | Not set | The user's call |
| SSH keepalive | distros section 1a | No `ServerAliveInterval` config shipped | Low priority |
| `hid_apple fnmode=2` | distros section 1a | Not set | Only matters for some external keyboards |
| systemd-oomd grace period | usage, Security | karchy sets 20 s at 50% (`system/systemd/oomd.conf.d/10-karchy.conf`). No 120 s user-slice override | Raise it if large builds get killed |
| Gaming extras | distros section 4 Optional 1 | Steam itself is done. No `ntsync` module load, performance wrapper, `xpadneo` entry or shader-cache file | Low priority on this laptop |
| Webcam overlay size has no control | distros section 3 | `--webcam-size` exists in `bin/karchy-capture-screenrecording:71`. The menu row does not pass it and no key is bound | Low priority |

Open, but not relevant to the laptop:

| Item | Raised in | What I checked |
|---|---|---|
| Data disk mounts at `/mnt/BIG`, not `/mnt/big` | usage, Hardware | `bin/karchy-disk-fstab:31` keeps the label's case. Desktop only. Relabel the disk before that install |
| DDC monitor brightness check | usage, Hardware | `ddcutil` loads `i2c-dev` itself (docs audit, `base-system.md` item 22). The desktop list in `TESTING.md` has no brightness check |
| VM extras: no animations, `vulkan-virtio` | distros section 4 Detected 6 | `karchy-vm` depends only on the two guest agents |
| NVIDIA runtime power rule | distros section 2a | Not shipped. Matters only on hybrid laptops |

### Unclear

| Item | Raised in | What I looked for |
|---|---|---|
| XDG autostart runs under uwsm | settings section 2.1 ("verify") | A recorded check in `STATUS.md`, `TESTING.md` or the docs audit. None found. uwsm normally relies on systemd's autostart generator, but nothing here confirms it on karchy |
| A one-line install list for the dev tools | usage, Dev table | The audit wanted it in the dotfiles repo, which is outside karchy. D-84 lists what karchy took from that repo, and the list is not among it |
| Migration steps for the user | usage, Apps, Backup and Security | Brave Sync, VS Code Settings Sync, copying VM disks and container data off the system disk. These are actions on the old machine, so the repo cannot show them. `karchy keyring-key export` (D-79) helps only with the keyring |

## 3. Done and decided

### audit-distros.md

| Item | Class | Evidence |
|---|---|---|
| `iw` for the band row and status | DONE | `packaging/pkgbuilds/karchy/PKGBUILD` depends |
| Wi-Fi regulatory domain, `wireless-regdb` | DONE | `system/wifi/85-karchy-wifi-regdomain.rules`, `karchy-wifi-regdomain.service`. `karchy-settings` depends on `iw` and `wireless-regdb` |
| Webcam overlay reachable from the UI | DONE | Record Screen menu, `default/karchy/karchy-menu.jsonc:39-44`. Built as menu rows, not the chooser the audit drew |
| Recording indicator click | DONE | `shell/plugins/bar/indicators/ScreenRecording.qml:43` starts or stops a recording |
| Webcam presence check | DONE | `karchy-capture-webcam-list` in the menu row's `when`. `v4l-utils` in `karchy` depends |
| `framework-system` on Framework laptops | DONE | `install/setup.sh:26-28` |
| Wi-Fi power save off | DONE | `system/NetworkManager/conf.d/30-karchy-wifi-powersave.conf` |
| ARP announce and ignore | DONE | `system/sysctl.d/60-karchy-network.conf` |
| BBR, fq, MTU probing | DONE | Same file, plus `system/modules-load.d/karchy-bbr.conf` |
| resolved mDNS and LLMNR off | DONE | `system/systemd/resolved.conf.d/10-karchy-multicast.conf` |
| Stop timeout 10 s | DONE | `system/systemd/system.conf.d/10-karchy-timeout.conf` and the `user.conf.d` twin |
| Mount-event limit, open-file limit | DONE | `system/systemd/system.conf.d/20-karchy-limits.conf` |
| I/O scheduler per disk type, BFQ on hard disks | DONE | `system/udev/60-karchy-ioschedulers.rules` |
| faillock 10 | DONE | `install/setup.sh:81-83` |
| dirmngr key servers | DONE | `system/gnupg/dirmngr.conf` |
| Thunderbolt in the initramfs | DONE | `system/mkinitcpio.conf.d/karchy-thunderbolt.conf` |
| keep-shell at logout | DONE | `system/systemd/user/wayland-wm@hyprland.desktop.service.d/10-karchy-keep-shell.conf` |
| Restart notice after updates | DONE | `bin/karchy-update:202`, `:269`, `:443-448`. Only inside `karchy update`, with no reminder after "Later" |
| Vulkan driver by GPU vendor | DONE | `install/setup.sh:35-40` (`vulkan-radeon`, `vulkan-intel`, `intel-media-driver`) |
| NVIDIA early KMS | DONE | `system/nvidia/mkinitcpio.conf`, installed by `karchy-nvidia` |
| `bolt` | DONE | `karchy-laptop` depends, on every laptop |
| Gaming in one click | DONE | Quick install: `steam` with `multilib` and `gpu32`, `proton-cachyos-slr`, GameMode, MangoHud (`default/karchy/quick-install.json`, `bin/karchy-quick-install:178-194`). D-70 revised D-19 this way |
| Band pin shown per saved network | DONE | `shell/plugins/settings/SavedNetworkRow.qml:263-270` |
| Share button in Settings › Network | DONE | `SavedNetworkRow.qml:34`, for the network in use |
| Screen-share picker with previews | DONE | `hyprland-preview-share-picker` in `karchy-desktop`. The audit said skip |
| `rtkit` | DONE | `karchy-desktop` depends, D-79. The audit said skip |
| USB autosuspend off | DONE | `system/udev/90-karchy-usb-autosuspend.rules`, D-79. The audit said skip |
| Printing as an optional feature | DONE | `karchy-printing` package, D-38, D-67 |
| Audio power save off on AC | DEFERRED | Hardware check first: `TESTING.md:92`. Docs audit `power-laptop.md` F4, under D-79 |
| journald size cap | DECIDED | systemd defaults kept on `@log`: docs audit `base-system.md` item 25, under D-79 |
| NVIDIA suspend services | DECIDED | Only for the 580 driver: D-79, `install/setup.sh:117-118` |
| Home backup to the NAS | DEFERRED | D-35, phase 7 |
| Capture text, QR and color picker | DECIDED | `docs/menu.md:37`, D-18 |
| The audit's skip list (zram, ananicy, sched-ext, kernel manager, vendor quirks, connectivity URL and the rest) | DECIDED | Followed. D-10, D-15, D-48. DNS switching came back in another form under D-68 |

### audit-settings.md

| Item | Class | Evidence |
|---|---|---|
| `framework-system` installed (F1, first half) | DONE | `install/setup.sh:26-28` |
| menu.md keyboard entry matches the menu (F8, doc half) | DONE | `docs/menu.md` Setup › Config Files, D-73 |
| Variable refresh, 10-bit, HDR, mirroring | DONE | `shell/plugins/settings/DisplaysSection.qml:293-354`, commit `8b8dfb6`, D-79 |
| `bolt` for dock authorization | DONE | `karchy-laptop` depends |
| Charge limit control | DEFERRED | Set in the BIOS or with `framework_tool`: `TESTING.md:96`, docs audit `power-laptop.md` F12 under D-79. That report also rejects the module option the audit proposed |
| Night light | DECIDED | `.agents/PLAN.md:44`. See the note at the end of class B |
| Animations switch | DECIDED | D-48 |
| Emoji picker | DECIDED | `docs/components.md:60` |
| The audit's skip list (wake timers, per-app notification rules, language and region and the rest) | DECIDED | Followed. D-49 for language |

### audit-usage.md

| Item | Class | Evidence |
|---|---|---|
| Plain text opens in VS Code | DONE | `system/xdg/mimeapps.list:14` |
| Disk-usage viewer | DONE | Disktree, D-74 |
| `openssh`, `rsync`, `unzip` in the base | DONE | `karchy-desktop` depends |
| Theme sync for Obsidian and Pi | DONE | D-48 as revised on 2026-11-14, `STATUS.md` line 42 |
| Virtual machines feature | DONE | D-63: `karchy vm` on QEMU without libvirt. `virt-manager` is in Quick install for the existing libvirt VMs |
| Containers feature | DONE | `karchy-containers` package, D-63, D-67 |
| GPU in containers | DONE | `bin/karchy-feature-containers:22` adds `nvidia-container-toolkit` |
| Steam with multilib and the 32-bit driver | DONE | Quick install, as above |
| Proton, Wine helpers, gamescope, MangoHud | DONE | Quick install entries `proton-cachyos`, `wine-helpers`, `gamescope`, `mangohud-goverlay` |
| `i2c-dev` loaded for DDC | DONE | Shipped by `ddcutil` itself (docs audit `base-system.md` item 22) |
| `sof-firmware` | DONE | `karchy-laptop` depends, D-79 |
| Apps the user installs (Zed, Meld, Beyond Compare, RustDesk, Ghidra, AI tools, `gh`, pavucontrol, kitty and the rest) | DECIDED | D-19. Each is now a Quick install entry (D-70), for example `zed`, `github-cli`, `beyond-compare`, `audio-mixer` |
| NVIDIA suspend services differ from the host | DECIDED | D-79 |
