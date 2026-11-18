# Desktop and base-OS gaps before the laptop install

Date: 2026-11-17. Repo state: `main` at `c094573`. Read-only review. This report is the only file that was created.

## What this report covers

The question: compared with CachyOS KDE (Plasma 6) and Windows 11, which base OS features, desktop features and system settings does karchy still lack, or has but never tested?

This report covers the areas the three earlier audits did not:

- everyday desktop features outside the Settings window
- base-OS behaviour that CachyOS ships by default

The earlier audits are `audit-settings.md`, `audit-distros.md` and `audit-usage.md`. Another reviewer tracks the status of their findings. Where an item belongs to one of them, the table says "earlier audit" and names the section. Those items are not ranked again here.

## How each status was decided

| Status | Meaning |
|---|---|
| HAS IT | The code or package is in the repo, and `STATUS.md` or `TESTING.md` records a check. |
| HAS IT BUT UNTESTED | The code or package is in the repo. No check is recorded, or the only check was in a VM and the feature depends on real hardware. |
| OPTIONAL | An entry in Quick install (`default/karchy/quick-install.json`) or a documented step provides it. |
| LEFT OUT ON PURPOSE | A decision or a binding doc drops it. The source is cited. |
| MISSING | A search of `bin/`, `shell/`, `system/`, `install/`, `packaging/` and the catalog found nothing. |

Evidence strength:

- "grep" means I searched the repo and read the matching lines.
- "inferred" means I read the code and concluded how it behaves. Nobody ran it.
- Package availability was checked with `pacman -Si` on this host (CachyOS, same repositories).

The target laptop is the Framework 13 AMD (`TESTING.md`, "On the real machines"). `STATUS.md` line 12 says nothing has run on real hardware yet.

---

## 1. Summary: MISSING and UNTESTED items, ranked

Class A matters on day one. Class B matters within weeks. Class C is nice to have.

### Class A: day one

| # | Item | Status | Suggestion |
|---|---|---|---|
| A1 | **Basic laptop hardware that the hardware checklist does not name.** Wi-Fi connect from the network panel, Bluetooth pairing, speakers and internal microphone, webcam, brightness keys, keyboard-backlight keys, media keys, touchpad tap and the 3-finger swipe, USB stick automount. `TESTING.md` lists suspend, fingerprint, dock and charge limit, but none of these. The VM cannot test Wi-Fi or Bluetooth at all. | HAS IT BUT UNTESTED | Document: add these lines to `TESTING.md` › Framework 13 AMD and run them in the first hour. |
| A2 | **Idle during video and calls.** The screensaver starts after 150 s, the lock after 300 s, and suspend after 15 min on battery. The idle service honours Wayland idle inhibitors (`services/idle/Service.qml:315`). Nothing in the shell answers the D-Bus `org.freedesktop.ScreenSaver` inhibit that some X11 and Electron apps use (grep). No check of video or call playback is recorded. | HAS IT BUT UNTESTED | Test: a 10-minute video in Brave, one in mpv, and one video call. If an app is not honoured, build a small D-Bus inhibit bridge. |
| A3 | **Screen sharing of a whole screen or a window.** The VM check passed for Region only. `STATUS.md` line 70 says "check Screens/Windows on the hardware". The hardware checklist does not list it. | HAS IT BUT UNTESTED | Test: share a screen and a window in a Brave call. Add the line to `TESTING.md`. |
| A4 | **External monitor behaviour.** Hotplug (`karchy-hyprland-monitor-watch`), lid closed with a monitor attached (`karchy-hyprland-monitor-clamshell`, `karchy-system-lid-inhibit`), mirroring and per-monitor scale. `STATUS.md` line 116 lists display mirroring as not checked. The VM used a headless output, not a real plug. | HAS IT BUT UNTESTED | Test with one HDMI or USB-C monitor: plug, unplug, close the lid, mirror, undock while asleep. |
| A5 | **Snapshot rollback.** Snapshots are taken and boot entries exist. A full restore was never run (`STATUS.md` line 116). No doc tells the user how to make a booted snapshot permanent. The snapper template keeps 5 snapshots (`system/snapper/root`), which is about two updates. | HAS IT BUT UNTESTED | Test one full restore before you rely on it. Document the steps in `docs/installing.md`. Consider a higher limit. |
| A6 | **Fractional scale with X11 apps.** The laptop panel needs a scale near 1.6. `xwayland.force_zero_scaling` is on, and `GDK_SCALE` takes whole numbers only (`karchy-settings-displays:120`). X11 apps such as Steam can then draw small. Checked in the VM at scale 1.6 with native apps only. | HAS IT BUT UNTESTED | Test Steam or one X11 app at the laptop scale. Document the per-app fix if it draws small. |

### Class B: within weeks

| # | Item | Status | Suggestion |
|---|---|---|---|
| B1 | **Disk-health warnings do not reach the desktop.** `smartd.service` and the monthly btrfs scrub are enabled (`install/setup.sh:104`, `install/base.sh:332`). No `smartd.conf`, notifier script or scrub-result check exists (grep). A failing disk is recorded in the journal only. KDE (Plasma Disks) and Windows show a notification. | MISSING (the delivery half) | Build: a smartd `-M exec` script and a scrub-result check that call `karchy-notification-send`. |
| B2 | **Recovery steps are not written down.** The pieces exist: snapshot boot entries, the `linux-cachyos-lts` entry, `sulogin` forced in emergency mode (`system/systemd/sulogin.conf`), the karchy ISO. No doc explains how to unlock the disk from the ISO and `arch-chroot`, or how to back up the LUKS header. Windows keeps a BitLocker recovery key. karchy has one password and no fallback. | MISSING (documentation) | Document: a "When it does not boot" section, plus `cryptsetup luksHeaderBackup` to the NAS. |
| B3 | **Phone integration.** KDE Connect and Phone Link have no equivalent. `kdeconnect` is not in the catalog (it is in Arch `extra`). LocalSend covers file transfer only. `audit-settings.md` classed KDE Connect as out of scope for Settings. No decision drops it. | MISSING | Add to Quick install, with ufw ports 1714–1764 opened only on trusted networks, like LocalSend. Or skip it if you do not use it. |
| B4 | **Tools for USB filesystems.** `dosfstools` is the only formatter installed. `exfatprogs` is absent. `ntfsprogs` is installed only when the installer finds an NTFS data disk (`install/base.sh:276`). GNOME Disks cannot format exFAT or NTFS, and a "dirty" NTFS stick from Windows cannot be repaired. | MISSING | Add `exfatprogs` and `ntfsprogs` to `karchy-desktop`. |
| B5 | **No kernel headers.** `linux-cachyos-headers` is in no package list (grep). Any DKMS package then fails to build its module: `xpadneo-dkms`, OpenRazer's driver, the catalog's Waydroid entry (`waydroid,dkms`). CachyOS installs the headers by default. The CachyOS kernel already includes `v4l2loopback`, so virtual cameras work without DKMS. | MISSING | Add to Quick install: make DKMS entries pull both kernels' headers. Or document it. |
| B6 | **Steam install path.** The catalog entry enables `[multilib]` and adds the 32-bit GPU driver. Only its setup text was viewed (`STATUS.md` line 151). The install was never run. | HAS IT BUT UNTESTED (OPTIONAL) | Test once on the laptop. Check a Proton game and a controller. |
| B7 | **Apps that start with the session.** Steam, Proton Pass, Syncthing and others write `~/.config/autostart` files. uwsm is expected to start them, but no check is recorded. | HAS IT BUT UNTESTED | Test with one app. (A Settings list is in `audit-settings.md`, "Startup apps".) |
| B8 | **System tray and notification history.** The tray widget (`bar/widgets/Tray.qml`, StatusNotifier) and the history (Super+Shift+Alt+Comma) have no recorded check. | HAS IT BUT UNTESTED | Test with a tray app, and open the history after a few notifications. |
| B9 | **USB autosuspend is off on the laptop too.** `90-karchy-usb-autosuspend.rules` keeps every USB device awake. This is the user's decision (2026-11-16, `docs/ownership-audit.md:115`) and its comment says it costs battery. The fingerprint reader, webcam and Bluetooth radio are internal USB devices. | Decided, effect not measured | Measure idle power on battery with and without the rule (`powertop`). If the cost is large, limit the rule to external ports. |
| B10 | **Phone and camera over USB (MTP).** `gvfs-mtp` is installed. No check is recorded. | HAS IT BUT UNTESTED | Test with your phone in Thunar. |
| B11 | **LocalSend real transfer.** The firewall rule was checked in the VM. A transfer between two devices over real Wi-Fi is not recorded. | HAS IT BUT UNTESTED | Test phone to laptop on the home network after trusting it. |
| B12 | **Snapshot browser.** KDE on CachyOS offers Btrfs Assistant. `btrfs-assistant` (Arch `extra`) is not in the catalog. Snapshots are reachable only from the boot menu and the `snapper` command. | MISSING | Add to Quick install. |
| B13 | **Printing with a real printer.** The feature installs and removes cleanly in the VM. No print or scan job is recorded. | HAS IT BUT UNTESTED (OPTIONAL) | Test when you first need a printer. |
| B14 | **GPG passphrase prompt.** gnupg is installed as a pacman dependency. Nothing configures or tests `pinentry` in the Hyprland session. | HAS IT BUT UNTESTED | Test `git commit -S` or `gpg --sign` once, if you sign commits. |

### Class C: nice to have

| # | Item | Status | Suggestion |
|---|---|---|---|
| C1 | Firmware updates are not announced. `karchy-update-check` does not ask fwupd. `fwupd-refresh.timer` is enabled, but the user must open Update › Update Firmware. | MISSING | Build: add `fwupdmgr get-updates` to the update check and a row to the Updates window. |
| C2 | File search and an inline calculator in the launcher. KRunner and Windows Search do both. The menu searches apps and menu rows only. | MISSING | Skip. Catfish and Clapgrep are in Quick install. omacalc is one search away. |
| C3 | Visual window switcher and overview. Alt+Tab cycles windows with no thumbnails. There is no Task View or KDE Overview. | MISSING | Skip, or decide later (needs a new binding, D-17). |
| C4 | Snap a floating window to a screen half (Windows Snap, KWin quick tile). Super+Left and Super+Right move focus. | MISSING | Skip. Tiling mode covers it. |
| C5 | Wi-Fi hotspot. No code (grep). | MISSING | Document the `nmcli device wifi hotspot` line. (`audit-settings.md` classed it out of scope.) |
| C6 | OpenVPN and other NetworkManager VPN plugins. The VPN page imports WireGuard files only. `networkmanager-openvpn` is not in the catalog. | MISSING | Add `networkmanager-openvpn` to Quick install if an employer or provider needs it. |
| C7 | Bluetooth file transfer. `bluez-obex` is not installed and no UI exists. | MISSING | Skip. LocalSend covers it. |
| C8 | Camera app. The webcam works in the browser. No camera app is in the base install or the catalog (`snapshot` and `cameractrls` are in Arch `extra`). | MISSING | Add `snapshot` to Quick install. |
| C9 | Log viewer. No GUI for the journal. `lnav` (terminal) is in the catalog. `gnome-logs` is not. | MISSING | Add `gnome-logs` to Quick install. |
| C10 | Character map. The emoji picker is dropped on purpose. `gnome-characters` is not in the catalog. | MISSING (catalog) | Add `gnome-characters` to Quick install. |
| C11 | Camera-in-use and screen-share indicators. The microphone widget shows use. Nothing shows camera or screen capture by another app. | MISSING | Skip for now. |
| C12 | Regional formats. The installer writes `LANG=en_US.UTF-8` and nothing else (`install/base.sh:217-220`). Date order, week start, units and paper size cannot be chosen. | MISSING | Document `localectl set-locale LC_TIME=…`. Add a form question later. |
| C13 | Online accounts and calendar sync. The clock panel has a month grid with no events. GNOME Calendar, Evolution and Thunderbird are in the catalog. `gnome-online-accounts` is not. | MISSING / OPTIONAL | Skip. Use Thunderbird or the web apps. |
| C14 | Screen reader, on-screen keyboard, high contrast, sticky keys. Nothing in the repo or catalog (`orca` is in `extra`). | MISSING | Skip. The laptop has no touchscreen. |
| C15 | Welcome or first-run guide. CachyOS Hello has no equivalent. Super+K shows the keybindings. | MISSING | Skip, or send one first-login notification that names Super+Space and Super+K. |
| C16 | Session restore after a reboot. Hyprland has none. | MISSING | Skip. |
| C17 | Guest account and parental controls. | MISSING | Skip. Single-user machine. |
| C18 | Ambient-light brightness. The Framework 13 has a light sensor. `iio-sensor-proxy` is not installed. | MISSING | Skip. |
| C19 | HDR and 10-bit. Settings › Displays has the controls. Never run on a real display. The laptop panel is not HDR. | HAS IT BUT UNTESTED | Test on the desktop (phase 5). |
| C20 | Thumbnails and the trash in Thunar. `tumbler`, `ffmpegthumbnailer` and `gvfs` are installed. No check is recorded. | HAS IT BUT UNTESTED | Two-minute check on the laptop. |
| C21 | CachyOS mirrors are not ranked. `karchy-mirrors-rank` ranks Arch mirrors only. The CachyOS list stays as packaged. | MISSING | Skip unless downloads from `[cachyos]` are slow. |
| C22 | Catalog entry "Omarchy Windows VM" installs only `freerdp`. The name promises a Windows VM. | Catalog defect | Rename it to FreeRDP, or remove it. |
| C23 | Crash reporter. No equivalent of DrKonqi or Windows Error Reporting. Core dumps are kept, capped at 1 GiB. | MISSING | Skip. `coredumpctl` is enough. |

### Covered by the earlier audits (not ranked here)

These items affect daily laptop use. The other reviewer tracks them.

- Night light, Do Not Disturb and Stay Awake controls, keyboard layout switching, cursor size, the Power page, charge limit, low and critical battery levels, auto timezone, clock format: `audit-settings.md` sections 0 to 3.
- Bluetooth pairing agent for passkeys, mpv not visible to media keys (`mpv-mpris`), Wi-Fi not carried from the installer to the first boot, `kernel-modules-hook`, THP and journal settings, audio power saving, slow-disk writeback limits, the Framework internal-microphone profile: `audit-distros.md` sections 1 and 2.
- Brave password migration, `gh`, the Steam library path, VM disks: `audit-usage.md`.

---

## 2. Full table by area

### 2.1 Clipboard, capture and small tools

| Item | Status | Evidence |
|---|---|---|
| Clipboard history | HAS IT BUT UNTESTED | `shell/plugins/clipboard`, Super+Ctrl+V (`default/hypr/bindings/clipboard.lua`). Text and images. Skips entries a password manager marks secret (`capture.sh:15`). No check of the panel is recorded. |
| Emoji picker | LEFT OUT ON PURPOSE | `docs/components.md` "Dropped", `PLAN.md` "Out". The compose key and Noto Color Emoji remain. |
| Character map | MISSING | Not in the base install or the catalog. See C10. |
| Screenshots | HAS IT | Omasnap on Print and Super+Shift+S. `STATUS.md` line 141 (Print observed). Annotation from the notification. |
| Text capture (OCR), QR, colour picker | LEFT OUT ON PURPOSE | `docs/menu.md` "Dropped: the rest of the Capture submenu (text, QR, color)". `hyprpicker` is installed but only freezes the screen for region capture (`karchy-capture-region:307`). Eyedropper is in the catalog (OPTIONAL). |
| Screen recording | HAS IT BUT UNTESTED | Record Screen menu and Alt+Print. The VM check used wf-recorder, because `gpu-screen-recorder` needs a real GPU (`STATUS.md` line 86, line 116). |
| Night light | LEFT OUT ON PURPOSE | `docs/components.md` "Dropped". Earlier audit: `audit-settings.md` §3 recommends bringing it back. |
| Do Not Disturb | MISSING (UI) | The notification service has `toggleDnd` and `isDnd`. No menu row, bar indicator or Settings switch (grep). Earlier audit: `audit-settings.md` F3. |
| Notification history | HAS IT BUT UNTESTED | `notifications/Store.js` (100 entries), Super+Shift+Alt+Comma. No recorded check. |

### 2.2 Windows, desktops and monitors

| Item | Status | Evidence |
|---|---|---|
| Tiling and floating | HAS IT | Dwindle, per-workspace floating mode with titlebars (D-60). Checked in the VM (`STATUS.md` line 64). |
| Windows-style keys | HAS IT | Super+Up, Super+Down, Super+M, Super+Shift+M, Alt+F4. Checked in the VM (`STATUS.md` line 69). |
| Snap to a screen half | MISSING | Super+Left and Super+Right move focus (`karchy/hypr/bindings.lua:10-11`). See C4. |
| Window switcher | HAS IT (no thumbnails) | Alt+Tab cycles and raises (`bindings.lua:41-44`). No visual switcher. See C3. |
| Overview of all windows | MISSING | No binding or plugin (grep for `expo`, `overview`). |
| Virtual desktops | HAS IT | Workspaces, 10 per monitor, Super+1..0, Super+Tab. Milestone 1 checks. |
| Monitor hotplug | HAS IT BUT UNTESTED | `karchy-hyprland-monitor-watch` (session autostart). Only a headless output was used in the VM. See A4. |
| Mirroring | HAS IT BUT UNTESTED | Settings › Displays › "Color and mirroring…". `STATUS.md` line 116: not checked. |
| Per-monitor scale | HAS IT | Settings › Displays, checked in VM `karchy-disp` (`STATUS.md` line 23, 136). X11 apps at fractional scale: see A6. |
| Lid closed with an external monitor | HAS IT BUT UNTESTED | `karchy-system-lid-close`, `karchy-hyprland-monitor-clamshell`, `karchy-system-lid-inhibit`. `TESTING.md` says the VM cannot test docking. |
| HDR, 10-bit, variable refresh | HAS IT BUT UNTESTED | `DisplaysSection.qml` (colour mode, `vrr`). `TESTING.md` lists VRR and 10-bit for the desktop only. |
| Touchpad gestures | HAS IT BUT UNTESTED | One gesture: 3-finger horizontal swipe (`bindings.lua:95`). KDE and Windows also offer overview and desktop-grid gestures. Never run on a touchpad. |
| On-screen keyboard | MISSING | Grep found nothing. `wvkbd` is not in the sync databases. See C14. |

### 2.3 Accessibility

| Item | Status | Evidence |
|---|---|---|
| Text size | HAS IT | Settings › Appearance (`karchy-display-text-size`). Checked (`STATUS.md` line 26). |
| Zoom or magnifier | LEFT OUT ON PURPOSE | `docs/keybindings.md` "Deliberately unbound: … zoom". |
| Cursor size | MISSING (control) | Fixed at 24 (`default/hypr/envs.lua:8-9`). Earlier audit: `audit-settings.md` §2. |
| Reduce animations | LEFT OUT ON PURPOSE | D-48 drops the animations toggle. |
| High contrast, sticky keys, screen reader | MISSING | Grep found nothing. Not in the catalog. See C14. |

### 2.4 Search, apps and system tools

| Item | Status | Evidence |
|---|---|---|
| App launcher | HAS IT | Super+Space, the menu engine. Milestone 1 check. |
| File search in the launcher | MISSING | `shell/plugins/menu` searches apps and menu rows. Catfish and Clapgrep are OPTIONAL. See C2. |
| Calculator | HAS IT (as an app) | omacalc is a shipped app. No inline maths in the launcher. |
| Task manager | HAS IT | Mission Center on Ctrl+Shift+Esc, checked (`STATUS.md` line 73). btop in a terminal. |
| System tray | HAS IT BUT UNTESTED | `bar/widgets/Tray.qml` uses Quickshell's `SystemTray`. No recorded check. See B8. |
| Default apps and file associations | HAS IT | Settings › Default apps, nine roles, checked (`STATUS.md` line 25). D-37. |
| Autostart apps | HAS IT BUT UNTESTED | Relies on uwsm and systemd's XDG autostart. No check and no UI. See B7. |
| Session restore | MISSING | Hyprland has none. `audit-settings.md` classed it as skip. |
| System information | HAS IT | Settings › About and fastfetch. CPU-X and GPU-Viewer are OPTIONAL. |
| Log viewer | MISSING | See C9. |
| Package installer GUI | HAS IT | Quick install window (D-70), checked from three sources (`STATUS.md` line 162). |

### 2.5 Audio, media and Bluetooth

| Item | Status | Evidence |
|---|---|---|
| Volume, mute and microphone keys | HAS IT BUT UNTESTED | `default/hypr/bindings/media.lua`. The VM has no such keys. See A1. |
| Media keys and bar media control | HAS IT BUT UNTESTED | `media.lua` (`media.playPause`), `services/media`. mpv stays invisible without `mpv-mpris` (earlier audit: `audit-distros.md` §1c). |
| Volume per app | HAS IT | Audio panel lists playback streams (`panels/audio/Panel.qml:60-64`). `pavucontrol` is OPTIONAL. |
| Output and input device choice | HAS IT | Audio panel, Shift+Mute switches the output (`media.lua`). |
| Bluetooth pairing | HAS IT BUT UNTESTED | Bluetooth panel and `karchy-bluetooth-device`. The VM has no adapter. Passkey devices may fail (earlier audit: `audit-distros.md` §1a, `bt-agent`). |
| Bluetooth file transfer | MISSING | No `bluez-obex`, no UI (grep). See C7. |
| Codecs | HAS IT | `ffmpeg`, mpv with hardware decoding (`system/mpv/mpv.conf`), Brave with VA-API flags. Hardware decode is on the hardware checklist (`vainfo`). |
| Webcam | HAS IT BUT UNTESTED | Kernel driver plus `v4l-utils`. Used by the recording overlay. No camera app. See A1 and C8. |
| Laptop speaker tuning | LEFT OUT ON PURPOSE | D-48 drops the speaker EQ. EasyEffects is OPTIONAL. |

### 2.6 Sharing, phone and remote access

| Item | Status | Evidence |
|---|---|---|
| Send files to nearby devices | HAS IT | LocalSend, port open on trusted networks only (D-33, D-68). Firewall rule checked in the VM (`STATUS.md` line 33). A real transfer is not recorded (B11). |
| Phone integration | MISSING | `kdeconnect` is not in the catalog. See B3. |
| Screen sharing in browsers and calls | HAS IT BUT UNTESTED | `xdg-desktop-portal-hyprland` and `hyprland-preview-share-picker`. Region only in the VM (`STATUS.md` line 70). See A3. |
| Remote desktop, as a client | OPTIONAL | Remmina, RustDesk, Parsec, Moonlight in the catalog. |
| Remote desktop, as a host | LEFT OUT ON PURPOSE | `docs/components.md` "Dropped: … remote session". Sunshine is OPTIONAL. SSH server: Settings › SSH (D-78). `wayvnc` is not in the catalog. |
| VPN | HAS IT | Settings › Network › VPN imports WireGuard files (`karchy-network-vpn`). The `nulifyer-vpn` package. Proton VPN, Mullvad and Tailscale are OPTIONAL. OpenVPN plugin: see C6. |
| Hotspot | MISSING | See C5. |
| Airplane mode | HAS IT | `karchy-airplane`, checked in the VM (`STATUS.md` line 92). The real key is untested. |
| Online accounts and calendar | MISSING / OPTIONAL | See C13. |

### 2.7 Files, devices and printing

| Item | Status | Evidence |
|---|---|---|
| USB drives | HAS IT BUT UNTESTED | `udiskie --automount --notify` in `karchy/hypr/autostart.lua:33`. No recorded check with a USB device. See A1. |
| exFAT and NTFS tools | MISSING | See B4. Mounting works through the kernel drivers. |
| Phones over USB (MTP) | HAS IT BUT UNTESTED | `gvfs-mtp`. See B10. |
| Internal data disks and NAS shares | HAS IT | `karchy-disk-fstab`, `karchy-mount-keep`, both checked in the VM (`STATUS.md` lines 34-35). |
| Archives | HAS IT | `thunar-archive-plugin`, xarchiver, `7zip` (D-40). xarchiver was opened in the theming check. Extract Here itself is not recorded. |
| Thumbnails and previews | HAS IT BUT UNTESTED | `tumbler`, `ffmpegthumbnailer`. See C20. |
| Trash | HAS IT BUT UNTESTED | Thunar through `gvfs`. No automatic emptying. |
| Printing and scanning | OPTIONAL | `karchy-printing` (D-38). Install checked in the VM. See B13. |

### 2.8 Language, input and fonts

| Item | Status | Evidence |
|---|---|---|
| Keyboard layout switching | MISSING (UI) | Settings › Input has no layout list (grep of `InputSection.qml`). Earlier audit: `audit-settings.md` F8. |
| Input methods (IME) | LEFT OUT ON PURPOSE | D-48 drops CJK input setup. `docs/keybindings.md` leaves input-method switching unbound. The catalog's Fcitx5 entry installs the bare `fcitx5` package with no setup. |
| Display language | LEFT OUT ON PURPOSE | D-49, English only. |
| Regional formats | MISSING | See C12. D-48 drops the locale generator. |
| Fonts: emoji, CJK | HAS IT | `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji`, JetBrains Mono Nerd (`karchy-desktop` depends). |
| Office-compatible fonts | OPTIONAL | "Liberation / MS core fonts" in the catalog. |
| Time sync | HAS IT | `systemd-timesyncd` enabled (`install/base.sh:331`). Update › Sync Clock. |
| Automatic timezone | MISSING | `docs/components.md` says it needs a decision. Earlier audit: `audit-settings.md` F1. |

### 2.9 Accounts, passwords and security

| Item | Status | Evidence |
|---|---|---|
| Password storage | HAS IT | oo7, unlocked at login (D-57). Checked in the VM (`STATUS.md` line 54). |
| SSH agent | HAS IT | Settings › SSH, agent switch checked (`STATUS.md` lines 159, 162). |
| GPG agent | HAS IT BUT UNTESTED | See B14. |
| User accounts | HAS IT (one user) | The installer creates one user. greetd logs that user in. Other users can sign in at the text greeter after Log Out (`system/greetd/config.toml`). No UI to add users. |
| Guest and parental controls | MISSING | See C17. |
| Lock screen | HAS IT | Super+L, checked (`STATUS.md` line 141). Fingerprint unlock is on the hardware checklist. |
| Fingerprint and FIDO2 | HAS IT BUT UNTESTED | Setup › Security. `TESTING.md` lists the fingerprint. FIDO2 with a real key is not checked (`STATUS.md` line 116). |
| Disk encryption management | HAS IT | Update › Passwords › Change Drive Password, checked (`STATUS.md` line 163). No TPM unlock (D-13: password at boot). No header backup: see B2. |
| Firewall | HAS IT | ufw, deny incoming (D-15). Settings › Network shows it read-only. Gufw is OPTIONAL. |
| Antivirus | OPTIONAL | ClamUI in the catalog. |
| Secure Boot | HAS IT | Installer step, checked in VM `karchy-sb` (`STATUS.md` line 43). Booting a snapshot under Secure Boot is not checked. |
| Location service | MISSING | No `geoclue` use (grep). Nothing in karchy needs it. |
| Microphone-in-use indicator | HAS IT | `bar/widgets/Microphone.qml:39`. |
| Camera and screen-share indicators | MISSING | See C11. |

### 2.10 Power and laptop

| Item | Status | Evidence |
|---|---|---|
| Idle, lock and sleep times | HAS IT (no Settings page) | `idle.*` in `shell.json`. Checked in the VM (`STATUS.md` line 53). Earlier audit: `audit-settings.md` §1. Playback: see A2. |
| Power profiles | HAS IT BUT UNTESTED | power-profiles-daemon, the power panel, per-source memory (`karchy-powerprofiles-set`). No battery in the VM. |
| Battery state and health | HAS IT BUT UNTESTED | The power panel shows time left, cycles, size and charge limit (`panels/power/Panel.qml:403-411`). |
| Charge limit | HAS IT BUT UNTESTED | `framework-system` is installed on Framework machines (`install/setup.sh:26-28`). Nothing sets the limit from the UI. On the hardware checklist. Earlier audit: `audit-settings.md` §1.3. |
| Lid and power button | HAS IT BUT UNTESTED | `system/laptop/logind.conf`, power key opens the power menu. The lid tests are on the hardware checklist. |
| Suspend, then hibernate | HAS IT BUT UNTESTED | D-32. On the hardware checklist. |
| USB power saving | LEFT OUT ON PURPOSE | See B9. |
| Automatic brightness | MISSING | See C18. |

### 2.11 Updates, recovery and maintenance

| Item | Status | Evidence |
|---|---|---|
| System updates and notifications | HAS IT | Updates window, bar indicator, `karchy update`. Checked in the VM from GitHub (`STATUS.md` lines 99-101). |
| Restart-needed notice | HAS IT | `karchy-update` marks kernel, driver, firmware and systemd updates (`karchy-update:202`). |
| Firmware updates | HAS IT BUT UNTESTED | Update › Update Firmware (`karchy-update-firmware`). On the hardware checklist. Not announced: see C1. |
| Rollback and restore points | HAS IT BUT UNTESTED | snapper, snap-pac, limine-snapper-sync. See A5. No manual "create a restore point" entry (the snapshot menu is not in `docs/menu.md`). |
| Home folder history | LEFT OUT ON PURPOSE | D-09: snapper covers `@` only. |
| Backups | OPTIONAL | The built-in home backup is phase 7 (D-35), not built. Pika Backup, Deja Dup, Vorta, restic and others are in the catalog. |
| Disk management | HAS IT | GNOME Disks, Disktree. Theming check only. |
| Disk health (SMART) | HAS IT BUT UNTESTED | `smartd` runs. Warnings do not reach the desktop: see B1. |
| Out-of-memory handling | HAS IT BUT UNTESTED | `systemd-oomd` with karchy's limits (`system/systemd/oomd.conf.d/10-karchy.conf`). No recorded check. |
| Crash handling | MISSING | See C23. |
| Recovery boot options | HAS IT (undocumented) | Snapshot entries, the LTS kernel, forced `sulogin`. See B2. Reset Computer is dropped (`docs/menu.md`). |

### 2.12 Gaming, containers, VMs and Windows apps

| Item | Status | Evidence |
|---|---|---|
| Steam | OPTIONAL, untested | Catalog entry with `multilib` and `gpu32`. See B6. D-19 keeps it out of the base. |
| GameMode, MangoHud, Gamescope, Proton-CachyOS, NTSync | OPTIONAL | Catalog, Gaming category. |
| Controllers | OPTIONAL | "Controller udev rules" (`steam-devices`). `xpadneo-dkms` for Xbox pads over Bluetooth is not in the catalog and needs headers (B5). |
| Variable refresh | HAS IT BUT UNTESTED | Settings › Displays. |
| Containers | OPTIONAL | `karchy-containers` (D-63), checked in the VM. |
| Virtual machines | OPTIONAL | `karchy vm` (D-63), checked in the VM. A Windows guest is not tested (`STATUS.md` line 74). |
| Windows apps | OPTIONAL | Bottles, Lutris, Wine helpers, WinBoat in the catalog. None tested. See C22 for one misnamed entry. |

---

## 3. CachyOS defaults a user would notice

| CachyOS default | karchy status | Evidence |
|---|---|---|
| Tuned repositories (v3, v4, znver4) | HAS IT | `install/base.sh:14-47`. The hardware checklist confirms `cachyos-znver4` on the laptop. |
| `linux-cachyos` and an LTS fallback | HAS IT | `install/packages/base.txt`. |
| Kernel headers | MISSING | See B5. |
| Kernel manager | LEFT OUT ON PURPOSE | `docs/menu.md` "Dropped: … kernel picker". |
| chwd hardware detection | HAS IT (own code) | `install/setup.sh`: NVIDIA generation, Vulkan per GPU vendor, microcode, Framework, VM. It runs at install only. `STATUS.md` line 87: no command to switch drivers after a GPU change. |
| `cachyos-settings` tunings | Partly | Present: I/O schedulers (`60-karchy-ioschedulers.rules`), BBR and fq, stop timeouts, open-file limits. Not found by grep: THP settings, journal size cap, audio power saving on AC, writeback limits, `sysrq`, `nmi_watchdog`. Earlier audit: `audit-distros.md` §2a. |
| zram | LEFT OUT ON PURPOSE | D-10: zswap plus a swap file, which also allows hibernation. |
| ananicy-cpp | MISSING | Not installed and not in the catalog. `audit-distros.md` recommends skipping it. No decision records that. |
| sched-ext schedulers | OPTIONAL | "Sched-ext schedulers" in the catalog, with `scx_loader.service`. The kernel supports them. |
| Package installer GUI | HAS IT | Quick install (D-70). |
| CachyOS Hello | MISSING | See C15. Its maintenance buttons are partly covered by timers (`paccache`, `karchy-mirrors.timer`). |
| rate-mirrors | HAS IT | Weekly, with checks (D-29), verified in the VM (`STATUS.md` line 30). Arch mirrors only: see C21. |
| Update notifier | HAS IT | The updates indicator (D-61). |
| snapper tooling | HAS IT BUT UNTESTED | See A5. karchy keeps 5 snapshots and has no timeline. |
| Btrfs Assistant | MISSING | See B12. |
| Bootloader with snapshot entries | HAS IT | Limine and limine-snapper-sync (D-12). |
| Plymouth boot splash | LEFT OUT ON PURPOSE | D-12. |
| Login screen | LEFT OUT ON PURPOSE | D-13: greetd auto-login after the disk password. |
| pacman settings | HAS IT | Color, ILoveCandy, VerbosePkgLists, 10 parallel downloads (`install/base.sh:178-187`). |
| AUR helper | HAS IT | paru (D-20). |
| ufw enabled | HAS IT | D-15. |
| Bluetooth enabled at boot | HAS IT | `bluetooth.service` enabled (`install/setup.sh:103`). |
| fish with CachyOS's config | HAS IT (own config) | karchy's prompt and eza listings (D-84). No command-not-found helper (`pkgfile`): grep found none. |
| systemd-oomd | HAS IT | Enabled (`install/setup.sh:104`). |
| fstrim, btrfs scrub | HAS IT | `install/base.sh:332`. |
| Reboot-required hook | HAS IT | In `karchy update`, not as a pacman hook. A plain `pacman -Syu` gives no notice. |
| Gaming meta packages | OPTIONAL | Individual catalog entries. No one-click bundle (`audit-distros.md` proposes one). |

---

## 4. Lines to add to the hardware checklist

`TESTING.md` › Framework 13 AMD does not name these. Each takes a few minutes.

1. Wi-Fi: connect from the network panel, reboot, and confirm it reconnects.
2. Bluetooth: pair headphones and a mouse. Check the headset microphone.
3. Speakers, internal microphone and webcam in one Brave video call.
4. Share a screen and a window in that call.
5. Function row: brightness, keyboard backlight, volume, media and the airplane key.
6. Touchpad: tap, two-finger scroll, the 3-finger swipe, palm rejection while typing.
7. Play a 10-minute video in Brave and in mpv on battery. The screensaver, lock and suspend must not start.
8. Plug in a USB stick. A notification appears and Thunar shows it. Eject it.
9. Plug in a phone. Thunar shows its storage (MTP).
10. External monitor: plug, unplug, mirror, close the lid, undock while asleep.
11. Open Steam or another X11 app at the laptop scale and check its size.
12. Start one app that adds itself to autostart. Log out and in. It starts and shows in the tray.
13. Boot a snapshot from Limine, then restore it permanently.
14. Idle power on battery with and without `90-karchy-usb-autosuspend.rules`.
