# karchy Settings vs Windows 11 and KDE Plasma 6

Research only. No repo files were changed. Repo state read on 2026-11-14 (`/home/nulifyer/Projects/karchy`).

Sources:
- **karchy:** the repo files cited inline.
- **KDE:** the host's own Plasma 6.8.2 (`kcmshell6 --list`, the polkit and UPower config files) plus the web pages listed at the end.
- **Windows:** Microsoft support pages and third-party guides (listed at the end). Microsoft's own pages leave out some details, such as the energy saver percentages, so those come from third-party guides and are marked as such.

---

## 0. Problems found while auditing

These are gaps between the docs and the code, or behaviour that limits a Settings page. They matter more than the comparison.

| # | Finding | Evidence |
|---|---|---|
| F1 | **`framework-system` and `tzupdate` are not installed anywhere.** `docs/components.md` lists them under "Detected at install" (Framework: charge limit; Battery: automatic timezone). Nothing in `install/` or `packaging/` installs them. `karchy-laptop` depends only on `karchy-desktop` and `power-profiles-daemon`. | `grep -rn "tzupdate\|framework-system"` finds them only in components.md; `packaging/pkgbuilds/karchy-laptop/PKGBUILD` |
| F2 | **The battery service has a low-battery warning only.** components.md says "low and critical warnings", but `shell/plugins/services/battery/Service.qml` has one hard-coded warning at 10% (`batteryThreshold: 10`). The action at critical level comes from UPower's packaged default (`CriticalPowerAction=Auto` at `PercentageAction=2`), which karchy does not set or check. | Service.qml line 14; `/etc/UPower/UPower.conf` on the host (Arch's file) |
| F3 | **Several toggles have working code but no way to reach them from the UI.** This covers Stay Awake (idle service + `~/.local/state/karchy/indicators/stay-awake`), Do Not Disturb (`notifications` IPC `toggleDnd`), `screensaver-off` and `suspend-off` (`karchy-toggle`). karchy dropped Omarchy's Toggle menu and its `Dnd`/`StayAwake` bar indicators; the i18n strings ("Stay Awake", "Silence Notifications") are still there. | `shell/plugins/bar/indicators/` (only Minimized, Reminder, ScreenRecording, Updates); docs/menu.md "Dropped: … toggles" |
| F4 | **Screen-off depends on the lock.** The display turns off only from the lock screen (`lock/Service.qml` `idleBlankTimer`, 5 s after the lock while idle). With `idle.lock = 0`, the screen never turns off. Windows and KDE both have a separate "turn off screen after" setting. | `shell/plugins/lock/Service.qml` ~line 764 |
| F5 | **Idle sleep cannot happen on a machine without a battery.** `suspendNow` requires `hasBattery`, so the desktop can never sleep on idle, even with `suspendOnAC: true`. | `services/idle/Service.qml` `suspendNow` |
| F6 | **The idle settings live in `~/.config/karchy/shell.json`, and that file is not merged with the defaults.** A user `shell.json` replaces karchy's defaults entirely, bar layout included (`shell.qml` `applyShellConfig`: "We do not deep-merge"). If a Power page saved idle values there, it would also freeze the bar layout at that moment. That breaks D-56 ("only changed values are saved, so the rest keeps following karchy's defaults"). | `shell/shell.qml` lines 84–100 |
| F7 | **Sections are not yet hidden per machine.** D-56 says laptop-only sections are hidden on desktops, but `Settings.qml`'s `sections` list is fixed. Nothing is laptop-only yet, so a Power page is the first to need this. | `shell/plugins/settings/Settings.qml` |
| F8 | menu.md says Setup › Keyboard holds "keybinding viewer, keyboard layouts and inputs". `karchy-menu.jsonc` has only `setup.input` and `setup.keybindings`, which open `input.lua` and `bindings.lua` in the editor. **Keyboard layouts can only be changed by editing a file.** | `default/karchy/karchy-menu.jsonc` lines 59–60 |

---

## 1. Settings › Power

### 1.1 What Windows 11 and KDE offer, and what karchy has

Key: **U** = user-level write (no password), **R** = root write (polkit/pkexec helper, like `karchy-trusted-networks`).

| Setting | Windows 11 | KDE Plasma 6 (PowerDevil) | karchy today | What the page would write |
|---|---|---|---|---|
| Turn screen off after (battery / AC) | Yes. Defaults on modern-standby PCs: 3 min on battery, 5 min plugged in [MS-power] | "Turn off screen" after N min, per profile; separate shorter time while locked [KDE-pd] | Only through the lock: screen off 5 s after the lock (F4). `idle.screensaver` 150 s, `idle.lock` 300 s in shell.json | **U**. New `idle.screenOff` (needs a small idle-service change to decouple it from the lock) |
| Dim screen before off | Control Panel advanced: "Dim display after" | "Dim automatically" per profile [KDE-pd] | No. The terminal screensaver (ttfx) fills this role | Skip. The screensaver covers it |
| Screensaver | No (legacy Control Panel only) | No | `idle.screensaver` (s) + `screensaver-off` toggle | **U** |
| Lock after | Sign-in options ("If you've been away…") | Screen Locking KCM: lock after N min, password grace | `idle.lock` (s) | **U** |
| Sleep after (battery / AC) | Yes. Modern standby: 3 / 5 min; S3: 10 / 15 min [MS-power] | "When inactive: Sleep / Hibernate / Shut down" after N min, per profile [KDE-pd] | `idle.suspend` 900 s, battery only; `idle.suspendOnAC` false (D-59). Desktop: impossible (F5) | **U**. Split into `sleepOnBattery` and `sleepOnAC` seconds; drop the `hasBattery` gate when sleep on AC is set |
| Hibernate after (idle) | Yes. 24H2 adds a hibernate timeout once hibernation is enabled [WC-hib] | Through the sleep mode "Standby, then hibernate" [KDE-pd] | `HibernateDelaySec=2h` in `/usr/lib/systemd/sleep.conf.d/karchy-laptop.conf` (D-32); idle sleep uses suspend-then-hibernate | **R**. `/etc/systemd/sleep.conf.d/90-karchy-settings.conf`. systemd-sleep reads it at each sleep, so no reload is needed |
| Sleep mode (standby / hybrid / then-hibernate) | Hybrid sleep in Control Panel advanced | Dropdown per action [KDE-pd] | Always suspend-then-hibernate when `karchy-hibernation-available`, otherwise suspend | Skip. Keep it automatic |
| Lid close (battery / AC) | "Lid, power & sleep button controls", per battery/AC: Do nothing, Sleep, Hibernate, Shut down, Display off (in Settings since 24H2) [pureinfotech-lid] | Per profile: Sleep / Hibernate / Shut down / Lock / Turn off screen / Do nothing, plus "even when an external monitor is connected" [KDE-pd] | `HandleLidSwitch=suspend-then-hibernate`, `HandleLidSwitchExternalPower=suspend`, docked = ignore (logind default) plus `karchy-system-lid-inhibit` for USB-C/Unknown connectors (D-32) | **R**. `/etc/systemd/logind.conf.d/90-karchy-settings.conf`, then `systemctl reload systemd-logind`. logind reloads its config on SIGHUP (`systemd-logind.service(8)`, systemd 262 on the host, `CanReload=yes`) |
| Power button | Same section: Do nothing, Sleep, Hibernate, Shut down, Display off | Sleep / Hibernate / Shut down / Lock / Show logout screen / Turn off screen [KDE-pd] | `HandlePowerKey=ignore` (logind drop-in) and the key opens the power menu (Hyprland binding) | **U**. A generated Hyprland binding in `~/.local/state/karchy/hypr/power.lua` (D-56 pattern). No root needed, because logind ignores the key |
| Power mode / profile | "Power mode": Best power efficiency / Balanced / Best performance, per AC and battery [MS-power] | "Switch to power profile", per profile [KDE-pd] | power-profiles-daemon (laptop). The bar's power panel picks a profile and `karchy-powerprofiles-set` remembers it per `ac` / `battery` in `~/.local/state/karchy/powerprofiles/`. Defaults: AC → performance, battery → balanced | **U**. Reuse `karchy-powerprofiles-set ac\|battery <profile>` |
| Energy saver / low-battery profile | Energy saver (replaced Battery saver in 24H2): on automatically at a chosen % (Never/10/20/30/40/50/Always; 30% reported as the default), option to lower brightness [geekrewind-es; MS-bsaver says the old default was 20%] | "On Low Battery" profile: its own timeouts, profile and brightness below the low level [KDE-pd] | None | **U**. New `power.saverAt` (%). The battery service switches to power-saver below it and back when plugged in |
| Low battery warning level | Control Panel: low battery level + notification | "Low level" % [KDE-pd] | Hard-coded 10% notification + `battery-low` hook | **U**. `battery.lowAt` |
| Critical level + action | Control Panel: critical level, action (sleep / hibernate / shut down) | "Critical level" % + "At critical level" action [KDE-pd] | UPower defaults only: `PercentageCritical=5`, `PercentageAction=2`, `CriticalPowerAction=Auto` (F2) | **R**: `/etc/UPower/UPower.conf.d/` drop-in. Recommend no control: ship a fixed drop-in (`CriticalPowerAction=Hibernate` where hibernation is available) and document it |
| Charge limit | No built-in Windows control (OEM apps) | "Stop charging at" / "Start charging once below", shown only when supported. Bugs show limits not persisting across reboots [KDE-pd; kde-505048] | `karchy-battery-status` and the power panel already **read** the thresholds ("Holding at 80%"). Nothing writes them; `framework-system` is not installed (F1) | See 1.3. Preferred: **U** via UPower `EnableChargeThreshold` (polkit `org.freedesktop.UPower.enable-charging-limit`, `allow_active=yes`, so no password) |
| Battery percentage in bar | Taskbar setting | Battery widget option | `showPercentage` in the power bar widget | **U**. Bar widget setting (optional) |
| Keyboard backlight on idle | n/a | "Change keyboard brightness" per profile | Turned off at lock blank, restored at wake (`karchy-system-wake`) | Skip |
| Wake timers | Control Panel advanced: allow wake timers | No | No (systemd timers wake only with `WakeSystem=`) | Skip |
| USB selective suspend, PCIe ASPM, CPU min/max, disk off | Control Panel advanced | No | Kernel defaults; the audit rejected global USB autosuspend-off | Skip |
| Battery usage per app / energy recommendations | Yes | `kcm_energyinfo` (history graphs) | btop, panel shows live W | Skip |
| Run script on power events | No | "Run script" per profile | `karchy-hook battery-low` | Skip. Hooks exist for power users |
| Inhibit sleep manually (Stay awake) | No (PowerToys Awake) | Battery applet: "Manually block sleep and screen locking" | Idle service has it, no UI (F3) | **U**. Existing state file |

### 1.2 Recommended page layout

The page shows on every machine. Battery and lid rows are hidden when `UPower.displayDevice.isLaptopBattery` is false (or `karchy-hw-laptop`); this also closes F7. On a laptop, timeout rows show two columns, **On battery | Plugged in**. On a desktop they show one column.

**Header text:** "Only what you change is saved. Lid and sleep changes ask for your password."

**Section A: Screen and sleep** (U, `~/.config/karchy/power.json`)

| Control | Options | Default laptop (battery / AC) | Default desktop |
|---|---|---|---|
| Screensaver after | Off, 1, 2.5, 5, 10 min | 2.5 / 2.5 min | 2.5 min |
| Turn off screen after | 1, 2, 5, 10, 15, 30 min, Never | 5 / 10 min | 10 min |
| Lock when the screen turns off | toggle (or "Lock after" dropdown) | on | on |
| Sleep after | 5, 10, 15, 30, 60 min, Never | 15 min / Never (D-59) | Never |
| Stay awake | toggle (same state as a bar indicator) | off | off |

Note on the desktop default of Never: NVIDIA suspend is still a risk on the RTX 5080 machine, and D-59 avoids sleeping on AC. Users can opt in.

The 5/10 min laptop screen-off default is an assumption. Changing only lock→screen-off coupling would keep today's 5 min + 5 s behaviour on both power sources, so 5 / 5 min is the no-change choice; 5 / 10 min is the proposal.

**Section B: Power mode** (U; shown only when power-profiles-daemon is running, so laptop-only for now)
- On battery: Power saver / Balanced / Performance (default Balanced).
- Plugged in: same choices (default Performance). These write the same state files the bar panel writes, so the panel and the page agree.

**Section C: Battery** (laptop only, U)

| Control | Options | Default |
|---|---|---|
| Limit charging to protect the battery | toggle + dropdown 60/70/80/90% (Framework: stop threshold only) | off. GNOME and KDE also ship it off; the user should choose |
| Switch to power saver at | Never, 10, 20, 30% | 20% |
| Warn when battery is at | 5, 10, 15, 20% | 10% (today's value) |
| Read-only line | "At 2% the laptop hibernates" | from UPower config |

**Section D: Lid and power button**
- **Power button (U, both machines):** Show power menu (default) / Sleep / Hibernate (if available) / Shut down / Do nothing.
- **Closing the lid, on battery (R, laptop):** Sleep, then hibernate (default) / Sleep / Hibernate / Lock / Do nothing.
- **Closing the lid, plugged in (R, laptop):** Sleep (default) / the same list.
- **With an external display:** fixed text, "Keeps running on the external display". Leave it as clamshell. A control here would fight `karchy-system-lid-inhibit`.
- **Hibernate after sleeping for (R, laptop, only when `karchy-hibernation-available`):** 30 min, 1 h, 2 h (default), 4 h, Never (plain suspend).

**Implementation shape (D-56):**
- **`karchy-settings-power`** owns `~/.config/karchy/power.json` (idle, profile, battery keys).
  - The idle service reads `power.json` over the defaults. A user `shell.json` `idle` block still wins, so hand edits keep working.
  - This avoids F6, because nothing writes `shell.json`.
- **`karchy-settings-power-system`** is a root helper under `/usr/bin` (D-50), run through pkexec. It validates its arguments and writes only:
  - `/etc/systemd/logind.conf.d/90-karchy-settings.conf` (`HandleLidSwitch`, `HandleLidSwitchExternalPower`), then reloads logind;
  - `/etc/systemd/sleep.conf.d/90-karchy-settings.conf` (`HibernateDelaySec`).
  - The `/etc` files sort after karchy-laptop's `/usr/lib` drop-ins, so they win. Deleting them returns to karchy's defaults.
- **Status:** read the live values from logind over D-Bus (`busctl get-property … HandleLidSwitch`), not from the files, so manual drop-ins show up correctly.

### 1.3 Charge limit on the Framework 13 AMD: what it needs

- The upstream driver is `cros_charge-control` (kernel 6.12+). On Framework laptops it needs `cros_charge-control.probe_with_fwk_charge_control=1`.
- On Framework it supports **only the stop threshold** (EC command v2). `framework_tool` or `ectool` must not be used at the same time. TLP also reports that recent Framework EC firmware broke the module [tlp-vendors]. Forum reports are mixed: it works on some kernels and firmware, the sysfs files are missing on others [fw-forum].
- `framework_tool --charge-limit` works but has to be reapplied at boot. A GitHub issue reports it not taking effect [fw-gh-291]. The Framework BIOS also has its own charge-limit setting.
- **UPower route.** GNOME 48 "Preserve Battery Health" calls UPower's `EnableChargeThreshold` [upower-mr208; fw-gnome48]. The host's polkit policy allows it for the active user without a password. UPower re-applies the limit itself.
  - Open question: the first UPower version supported only devices with both start and end thresholds. Check `upower -d` for `charge-threshold-supported` on the Framework before relying on it.
- **Recommendation (phase 4, on the Framework):**
  1. Add the module option in karchy's Framework-detected tier (a `modprobe.d` file).
  2. Test UPower `EnableChargeThreshold`.
  3. If UPower refuses a stop-only device, use a small root helper plus a boot oneshot that writes `charge_control_end_threshold`.
  4. Either way, **fix F1**: either install `framework-system` or remove the claim from components.md. With the kernel path working, `framework-system` isn't needed for the charge limit.

---

## 2. The rest of the settings surface

Classes: **(a)** already covered, **(b)** worth adding to Settings (minimal form given), **(c)** out of scope.

### 2.1 Windows 11 Settings [MS-explore]

| Windows area | Class | karchy today, or the proposal |
|---|---|---|
| **System › Display** (resolution, refresh, scale, orientation, multiple displays, brightness, HDR, night light) | (a), plus (b) | (a): Settings › Displays (resolution, refresh, scale, position, rotation, on/off per monitor), brightness in the monitor panel. (b): **Night light** (see 3); **VRR and HDR/10-bit** toggles per monitor for the RTX 5080 desktop (Hyprland `vrr`, `bitdepth`, `cm`); **Mirror displays** (the `karchy-hyprland-monitor-internal-mirror` command exists) |
| System › Sound (output/input device, volume, mono audio, device properties) | (a) | Audio panel: output picker, inputs, per-app mixer; microphone bar module. Mono audio: (c), rare |
| System › Notifications (on/off, per-app, DND, schedules) | (b) | Notification service with DND exists, no UI (F3). Add a **Do Not Disturb** toggle to Settings and bring back the `Dnd` bar indicator. Per-app muting and schedules: (c) |
| System › Focus | (c) | Pomodoro-style timer; reminders already exist |
| **System › Power & battery** | (b) | Section 1 |
| System › Storage (usage, Storage Sense, cleanup) | (a)/(c) | GNOME Disks, paccache, /tmp aging, smartd and scrub. A "free space" page is (c) |
| System › Nearby sharing | (a) | LocalSend + trusted networks (Settings › Network) |
| System › Multitasking / Snap | (a) | Hyprland tiling, floating-mode titlebars, workspace layout in the menu. More is (c) |
| System › Clipboard (history) | (a) | Clipboard history service, Super+Ctrl+V |
| System › Projecting to this PC, Remote Desktop | (c) | Remote session dropped on purpose; sshd in menu › Security |
| System › Optional features | (a) | Settings › Optional features |
| System › About | (a) | Settings › About (+ channel) |
| BT & devices › Bluetooth | (a) | Bluetooth panel |
| BT & devices › Printers & scanners | (a) | Optional feature (D-38) |
| BT & devices › Mouse, Touchpad | (a) | Settings › Input |
| BT & devices › Keyboard / typing (layouts) | (b) | Layouts only by editing `input.lua` (F8). Add **Keyboard layouts** (add/remove/order + switch key) to Settings › Input. The XKB logic already sits in `keyboard.xkb(compose)` |
| BT & devices › Pen & Windows Ink | (c) | No pen hardware on the target machines |
| BT & devices › AutoPlay | (a) | udiskie automount + notification. A toggle is (c) |
| BT & devices › USB (error notifications, battery saver) | (c) | — |
| Network & internet (Wi-Fi, Ethernet, VPN, hotspot, proxy, airplane mode) | (a) | Network panel (Wi-Fi, band, QR, captive portal), VPN plugin, trusted networks. Hotspot, proxy, airplane mode: (c) (`nmcli`/`rfkill`) |
| Personalization › Background, Colors, Themes | (a) | Settings › Appearance + menu |
| Personalization › Lock screen | (c) | Lock screen follows the theme |
| Personalization › Taskbar | (b), low | The bar is configured through `karchy-bar` / `shell.json`. A minimal **Bar** block in Appearance (top/bottom, opaque/glass, show battery %, clock format) is worth having. Making it work needs F6 fixed (merge user keys over defaults) |
| Personalization › Start | (c) | Menu tree is fixed by D-18 |
| Personalization › Fonts | (a) | Appearance › monospace font + text size |
| Apps › Installed apps | (a) | Menu › Packages (install/remove) |
| Apps › Default apps | (a) | Settings › Default apps |
| Apps › Startup apps | (b), low | No UI. uwsm should run XDG autostart (`~/.config/autostart`); verify. Minimal: a list of `~/.config/autostart` entries with on/off switches (`Hidden=true`) |
| Apps › Video playback, Archived apps, Apps for websites | (c) | mpv config; web apps in the menu |
| Accounts › Your info, Sign-in options (password, fingerprint, security key) | (a) | Menu › Update › Password (user, LUKS), Setup › Security (fingerprint, FIDO2). Could move to a Settings › Account page later: (b), low |
| Accounts › Email/online accounts, family, other users, Windows backup | (c), backup later | Single user. Home backup to the NAS is phase 7 (D-35); its settings would go in Settings |
| Time & language › Date & time (timezone, auto-time, auto-timezone) | (b) | Menu › Update › Timezone and Time exist. Auto-timezone (`tzupdate`) was promised but isn't installed (F1). Minimal **Date & time** block: timezone picker, "Set timezone automatically" (laptop), 24 h clock / seconds (the clock widget already has formats) |
| Time & language › Language & region, Typing, Speech | (c) | English only (D-49). Regional formats could matter (date order, week start); (c) for now |
| Gaming (Game Mode, Game Bar, captures) | (c) | Steam installed by the user; screen recording exists |
| Accessibility (text size, visual effects, mouse pointer, contrast, magnifier, narrator, captions, color filters, sticky keys) | (a) partly, (b) small | (a): text size. (b), low: **cursor size** (Hyprland `cursor` size + `XCURSOR_SIZE`) and maybe **reduce animations** (`toggle-animations` was dropped in D-48; a switch would bring back its value without the command). Magnifier and screen reader: (c) |
| Privacy & security › App permissions (camera, mic, location, screenshots) | (c) | No per-app permission model outside Flatpak and portals. The mic bar module shows use |
| Privacy & security › Windows Security (firewall, device security) | (a) | ufw deny incoming + LocalSend rule from trusted networks; Secure Boot step |
| Privacy & security › Find my device, diagnostics | (c) | — |
| Windows Update (check, pause, history, active hours, restart scheduling, optional updates, delivery optimization) | (a), plus (b) small | (a): updates indicator, `karchy update`, Settings › About (channel + update button), snapper pre/post snapshots, fwupd in the menu. Pause, active hours and restart scheduling are (c): updates never install by themselves. (b), low: **update history** (show the last few `karchy update` runs or snapper pre/post pairs, with "boot an earlier snapshot" help text) |

### 2.2 KDE Plasma 6 System Settings modules (from `kcmshell6 --list`, Plasma 6.8.2 on this host)

| KDE module | Class | karchy |
|---|---|---|
| Night Light (`kcm_nightlight`, `kcm_nighttime`) | (b) | Dropped; see section 3 |
| Display Configuration (`kcm_kscreen`) | (a) + (b) | Settings › Displays; add VRR, HDR, mirror (as in 2.1) |
| Audio (`kcm_pulseaudio`) | (a) | Audio panel. Profiles (HDMI/analog) could be useful later |
| Notifications (`kcm_notifications`) | (b) | DND toggle only (F3) |
| Shortcuts (`kcm_keys`) | (a) | Super+K viewer; custom bindings go in the user's `bindings.lua` (D-17 needs approval for new binds, so no editor) |
| Autostart (`kcm_autostart`) | (b), low | As "Startup apps" above |
| Session (`kcm_smserver`: restore, logout confirm) | (c) | — |
| Users (`kcm_users`) | (a)/(c) | Password in the menu; single user |
| Date & Time (`kcm_clock`) | (b) | As 2.1 Date & time |
| Region & Language (`kcm_regionandlang`) | (c) | D-49 |
| Accessibility (`kcm_access`) | (b), low | Cursor size; sticky keys (c) |
| Firewall (`kcm_firewall`) | (a) | Trusted networks. A full ufw rule editor is (c) |
| Thunderbolt (`kcm_bolt`) | (c), check | Thunderbolt module is in the initramfs. Whether `bolt` is needed for authorization on the Framework 13 AMD (USB4) depends on the firmware security level. Check on the hardware in phase 4; add only if docks need authorizing |
| KDE Connect | (c) | LocalSend covers file sharing |
| Online Accounts (`kcm_kaccounts`) | (c) | — |
| Removable Storage (`kcm_device_automounter`, `kcm_solid_actions`) | (a) | udiskie automount, internal disk offer (D-24) |
| Printers | (a) | Optional feature |
| Login Screen (`kcm_plasmalogin`/SDDM) | (c) | greetd auto-login after LUKS (D-13) |
| Power Management (`kcm_powerdevilprofilesconfig`) | (b) | Section 1 |
| Energy info (`kcm_energyinfo`) | (c) | — |
| Screen Locking (`kcm_screenlocker`) | (b) | Lock-after time in the Power page |
| Keyboard (`kcm_keyboard`), Mouse, Touchpad | (a) + (b) | Input page; add layouts (F8) |
| Bluetooth, Networks, Wi-Fi hotspot, Proxy | (a)/(c) | Panels; hotspot and proxy (c) |
| Default Applications, File associations | (a) | Default apps |
| Colors, themes, icons, cursors, fonts, wallpaper, splash, Plymouth | (a)/(c) | Theme engine covers colors and wallpaper; no Plymouth (D-12); cursor size (b), low |
| Window behaviour, rules, effects, virtual desktops, screen edges, task switcher | (c) | Hyprland Lua config; user files |
| KWallet | (a) | oo7 auto-unlocked (D-57), nothing to configure |
| File search (Baloo), Plasma search, web shortcuts, activities, recent files | (c) | Not shipped |
| Game controllers, tablets, touchscreen, virtual keyboard | (c) | — |
| Info modules (About, CPU, memory, PCI, USB, Vulkan, VA-API…) | (a)/(c) | About + fastfetch; btop |
| Feedback / telemetry, KDE Daemon services | (c) | — |
| Spell checking, sound theme | (c) | — |

---

## 3. Dropped features to bring back

| Dropped item | Where it was dropped | What the comparison says | Recommendation |
|---|---|---|---|
| **Night light** | Inception "Out" list (`.agents/PLAN.md` line 44; components.md "Dropped"). **Not** part of D-48. The ownership audit only removes leftover service IDs. No reason is recorded | Both Windows (System › Display › Night light, with a schedule) and KDE (`kcm_nightlight` + `kcm_nighttime`) include it. It is a basic display feature people expect | **Bring back, minimal.** `hyprsunset` (Arch) and a Night light block in Settings › Displays: Off / Always on / Scheduled (from–to), plus a warmth slider. Write the generated profile config under `~/.local/state/karchy/` (check whether hyprsunset accepts a config path; else start it from a user unit with arguments). Re-apply on wake, because profile changes don't fire across suspend [hypr-forum]. Omarchy's version was about 210 lines (74-line toggle, 118-line service, bar indicator) and can be adapted |
| **Toggle menu: Stay Awake, Silence Notifications, Screensaver off** + `Dnd` / `StayAwake` indicators | menu.md "Dropped: … toggles"; indicators not kept | Windows has DND in Quick Settings; KDE has DND in notifications and "block sleep" in the battery applet. The code exists in karchy, only the UI is gone (F3) | **Bring back** the `Dnd` and `StayAwake` indicators, and put the switches in Settings (Power: Stay awake; a Notifications row: Do not disturb). Cheap: code and i18n strings are already present |
| `toggle-animations` (D-48) | D-48 | Windows (Accessibility › Visual effects › Animation effects) and KDE (`kcm_animations`) | Optional: an "Animations" switch in Appearance writing a generated Hyprland include. Not urgent |
| `tzupdate` automatic timezone | Never actually installed (F1) | Windows and KDE both set the timezone automatically | Install it in the battery tier as documented, or drop the claim; expose it under Date & time |
| Emoji picker | components.md Dropped | Windows has Win+. and KDE has an emoji selector; not a Settings item | Out of scope for Settings; mention only |
| Weather, world clock, Tailscale, dock, remote session | Dropped | Not part of either OS's core Settings | Keep dropped |

---

## 4. Priorities

**Must-have**
1. **Settings › Power.** Sections A–D as in 1.2.
   - Prerequisites:
     - a separate `power.json` read over the defaults (F6);
     - screen-off separate from the lock (F4);
     - idle sleep allowed on AC and desktops when the user chooses it (F5);
     - per-machine section hiding (F7);
     - a pkexec helper for the logind and sleep drop-ins (with logind reload).
2. **Stay awake and Do not disturb back in the UI** (F3): Settings switches + bar indicators. Small change, existing code.
3. **Fix the doc and package gaps:** `framework-system`/`tzupdate` (F1), the critical-battery claim (F2), the menu.md keyboard entry (F8).
4. **Charge limit on the Framework:** module option + UPower `EnableChargeThreshold` (or a fallback helper), verified on the hardware in phase 4.

**Nice to have**
5. **Night light** (hyprsunset) in Settings › Displays.
6. **Keyboard layouts** in Settings › Input.
7. **Date & time** block (timezone, automatic timezone on laptops, 24 h / seconds).
8. Displays: **VRR, HDR/10-bit, mirror** (mainly the RTX 5080 desktop).
9. Battery: **power saver at X%**, configurable low warning.
10. A small **Bar** block in Appearance (position, background, battery %, clock), once shell.json merging is fixed.
11. **Startup apps** list (`~/.config/autostart` on/off); **update history**; cursor size; animations switch.

**Skip**
- Wake timers, USB selective suspend, PCIe/CPU power tuning, dim-before-off, battery usage per app, energy recommendations, run-script actions.
- Focus sessions, per-app notification rules, Storage Sense, remote desktop and projecting, pen, gaming, online accounts, KDE Connect, login screen.
- Language and region (D-49), app permissions, users, session restore, window-manager behaviour pages, Windows Update pause, active hours and restart scheduling (karchy never updates without the user).

---

## Sources

Local (host, 2026-11-14):
- Plasma 6.8.2 `kcmshell6 --list`.
- `/usr/share/polkit-1/actions/org.freedesktop.upower.policy` (`enable-charging-limit` `allow_active=yes`).
- `/etc/UPower/UPower.conf` (upower 1.91.5).
- `man systemd-logind.service` (SIGHUP reloads config) and `systemctl show systemd-logind -p CanReload` (systemd 262.2).

Web:
- [MS-power] Power settings in Windows 11: https://support.microsoft.com/topic/0d6a2b6b-2e87-4611-9980-ac9ea2175734
- [MS-explore] Exploring Windows Settings: https://support.microsoft.com/en-us/Windows/Experience/exploring-windows-settings
- [pureinfotech-lid] Change lid close action on Windows 11: https://pureinfotech.com/change-close-lid-action-windows-11/
- [WC-hib] Hibernation settings in Windows 11: https://windowscentral.com/how-use-hibernation-extend-battery-life-windows-11
- [geekrewind-es] Energy saver threshold: https://geekrewind.com/how-to-automatically-turn-energy-saver-on-or-off-in-windows-11/
- [MS-bsaver] Battery saver (hardware guidelines): https://learn.microsoft.com/en-us/windows-hardware/design/component-guidelines/battery-saver
- Windows Update pause and active hours: https://geekrewind.com/how-to-pause-automatic-updates-for-a-convenient-time-in-windows-11/ and https://www.computerworld.com/article/3564826/stop-windows-update-from-rebooting-your-pc.html
- [KDE-pd] KDE Power Management handbook: https://docs.kde.org/stable_kf6/en/powerdevil/kcontrol/powerdevil/index.html
- PowerDevil in Plasma 6.0 and beyond: https://blogs.kde.org/2024/04/23/powerdevil-in-plasma-6.0-and-beyond
- [kde-505048] Charge limit not preserved across reboots: https://bugs.kde.org/show_bug.cgi?id=505048
- [tlp-vendors] TLP battery care vendor specifics: https://linrunner.de/tlp/settings/bc-vendors.html
- [fw-forum] Charge levels from KDE on Framework: https://community.frame.work/t/charge-levels-configurable-from-kde-userspace/69432?page=2
- [fw-gh-291] framework-system charge-limit issue: https://github.com/FrameworkComputer/framework-system/issues/291
- [fw-gnome48] GNOME 48 Preserve Battery Health (Framework forum): https://community.frame.work/t/gnome-48-preserve-battery-health/67918
- [upower-mr208] UPower charge threshold MR: https://gitlab.freedesktop.org/upower/upower/-/merge_requests/208
- logind.conf(5): https://man.archlinux.org/man/logind.conf.5.en.txt
- hyprsunset wiki: https://wiki.hypr.land/Hypr-Ecosystem/hyprsunset/
- [hypr-forum] hyprsunset and suspend: https://forum.hypr.land/t/solved-hyprsunset-doesnt-work-when-suspended/899
