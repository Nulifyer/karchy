# Menu

The Omarchy menu engine with a karchy tree (D-18). Super+Space opens it, and typing searches apps. Tags: [O] Omarchy entry kept, [New] karchy addition.

**What belongs here** (D-133, D-135; user 2026-11-19): the menu is for what you do now. A row is an action (reload, record, install, shut down), a quick-open link (Keybinds, Update, Settings) or an app launch. What you set and leave (preferences, enrolment, accounts, passwords) is in the Settings window, and every Settings page is found from the menu's search. A new row that is a preference picker goes to Settings instead.

```
Apps        ›  installed apps
Packages    ›  Quick Install · Install Package · Remove Package · Install Web App · Remove Web App
Recording   ›  Stop · No Audio · Desktop Audio · Desktop + Microphone · Desktop + Microphone + Webcam
Keybinds       opens Settings › Keybindings
Update         opens the Updates window
Settings       opens Settings
Reload      ›  Shell · Hyprland · Audio · Wi-Fi · Bluetooth · Trackpad
Power       ›  Lock · Suspend · Hibernate · Log Out · Reboot · Shutdown
```

- **Apps:** search installed desktop apps [O]. App results carry no "Apps" subtitle. The Virtual Machines and Containers windows are apps here while their feature is installed (D-116), not menu rows.
- **Packages**
  - Quick Install: the Quick install window, common apps and karchy's optional features by category, searched like fzf (D-70) [New]
  - Install Package: one fzf list over the repositories and the AUR (D-135) [O] + [New]. Each row says its source (the repository's name, or "AUR · built here from a user-submitted script"). Repository packages are listed before AUR ones whatever is typed, a name in both shows the repository's first, and within a source the shortest names lead, so the package named exactly what was typed is on top. The list opens on the repositories at once and the AUR's names are added as they load. Preview: `pacman -Sii`, or paru's info with the AUR's caution; Alt+B shows an AUR package's build script. Tab selects several; repository packages install with pacman and AUR ones with paru (which shows the build files and asks), in one run. `karchy pkg install`; `karchy pkg aur-install` lists the AUR only.
  - Remove Package [O]
  - Install Web App, Remove Web App (once one exists): icons from the site, then Dashboard Icons (D-82) [O] + [New]
- **Recording:** Stop while one runs; No Audio, Desktop Audio, Desktop + Microphone, Desktop + Microphone + Webcam (only when a webcam is present). Then pick a region, window or monitor [O] + [New]
- **Keybinds:** Settings › Keybindings, the list of every binding and its editor (Super+K; D-134) [New]
- **Update:** the Updates window (`karchy updates`; D-81) [New]
- **Settings:** opens the karchy Settings window (D-27) [New]
- **Reload:** restart or reload one part of the desktop: Shell, Hyprland, Audio, Wi-Fi, Bluetooth (with an adapter), Trackpad (with a touchpad) [O]
- **Power:** Lock, Suspend, Hibernate (only if available), Log Out, Reboot, Shutdown; Super+Escape and the power key open it [O]

One card width at every level; the header shows where you are ("Reload"), or "Search…" at the top; Title Case throughout. The root is eight rows. A list ends in a cut-off row only when it is more than one row over 70% of the screen's height.

## Search

**A result from a submenu reads as its path**: "Power › Reboot", "Reload › Hyprland", "Packages › Quick Install", "Settings › Security". The menu draws the parent, dimmed, before the label, from the tree; labels inside a submenu are short and never repeat the parent (this replaces D-73's rule that every label reads on its own). The words of the path find the row too: "power restart", "reload hyprland", "settings displays".

**Search-only rows** are found, never listed:

- Theme (the theme picker; also themes) and Background (the wallpaper picker; also wallpaper), marked `"searchOnly": true`. Settings › Appearance has both.
- The children of a row that runs an action: Settings' pages and the Updates window's Firmware part.

| Result | Opens | Found by |
| --- | --- | --- |
| Settings › Network | `karchy settings network` | network, wifi, wi-fi, ethernet, vpn, dns |
| Settings › Displays | `karchy settings displays` | displays, monitors, screen, resolution, scale, night light |
| Settings › Input | `karchy settings input` | keyboard, mouse, touchpad, trackpad, input, input config |
| Keybinds (the root row) | `karchy settings keybindings` | keybinds, keybindings, shortcuts, keys, hotkeys |
| Settings › Appearance | `karchy settings appearance` | appearance, style, bar style, lock screen clock, workspace layout, tiling, floating, looknfeel |
| Settings › Fonts | `karchy settings fonts` | font, fonts, text size, monospace font, app font, terminal font |
| Settings › Notifications | `karchy settings notifications` | notifications, do not disturb, dnd, silent |
| Settings › Default Apps | `karchy settings apps` | default apps, default browser, file associations |
| Settings › Power | `karchy settings power` | power, battery, sleep, lid, idle, suspend, hibernate |
| Settings › Storage | `karchy settings storage` | disk, storage, space, bees, smart, nas, smb, samba, share, network shares, mount |
| Settings › Date & Time | `karchy settings datetime` | timezone, time, clock, date, ntp |
| Settings › Security | `karchy settings security` | security, fingerprint, fido2, yubikey, security key, password, passwd, change password, drive password, luks, encryption |
| Settings › SSH & Git | `karchy settings ssh` | ssh, sshd, ssh server, ssh agent, git, github |
| Settings › About | `karchy settings about` | about, version, system info, fastfetch, hyprland config, update, updates, channel |
| Update › Firmware | `karchy updates firmware` (the Updates window at its Firmware part) | firmware, update firmware, fwupd, bios |

The Settings rows are in the window's own order (`karchy-settings --sections`).

Matching (D-136): a word typed is found at the start of a word, never loosely inside one. It matches a row at the start of a word of its name or its path; from two letters on, at the start of a word of an alias (an app's generic name and keywords are its aliases); from three letters on, inside a word of the row's own name ("fox" finds Firefox) or as a whole word of its description. So "b" lists what is named b…, "sc" gives Recording and Settings › Displays (screen, scale) and not Disks for its keyword "disc", "up" gives Update and not Disks for "backup", and "the" gives Theme and not Settings › Network for "ethernet". Several words match in any order, each on its own.

Ranking: a root row named exactly what was typed comes first ("power" is the Power menu, then Settings › Power); then a row that names the query as an alias ("restart" is Power › Reboot, then the Reload rows); then names that start with it, names with a later word that starts with it, paths, aliases that start with it, and last names that only contain it. A row whose own name matches comes before one matched only by an alias, so "suspend" puts Power › Suspend first and Settings › Power second, and "install package" puts Packages › Install Package above the Packages submenu (D-77). "update" gives Update, then Settings › About (which shows the version and the channel, and has the button to the Updates window), then Update › Firmware. `tests/menu-search.js` checks the tree, every alias above and these orders against the shipped menu.

## Where the rows that left went (D-133, D-135)

| Was in the menu | Now |
| --- | --- |
| Appearance › Theme, Background | found by search ("Theme", "Background"); Settings › Appearance |
| Appearance › Font | Settings › Fonts |
| Appearance › Workspace Layout | Settings › Appearance (`karchy-hyprland-workspace-layout-default`) |
| Packages › Install AUR Package | Packages › Install Package, one list with the repositories first |
| Setup › Security (fingerprint, FIDO2) | Settings › Security |
| Setup › Network Shares | Settings › Storage (Keep a share mounted…, Stop keeping) |
| Setup › Set Up Git | Settings › SSH & Git |
| Setup › Keybindings (the viewer) | the Keybinds row: Settings › Keybindings, an editor |
| Setup › Config Files | an "Open config file" link in the header of the matching Settings page (Input: `input.lua`; Keybindings: `bindings.lua`; About: `hyprland.lua`) |
| Update › Update System | the Update row |
| Update › Update Firmware | the Updates window's Firmware part |
| Update › Restart | the Reload submenu |
| Update › Passwords | Settings › Security |
| Update › Set Timezone, Sync Clock | Settings › Date & Time (`karchy menu timezone` still opens the picker by itself) |
| System Info | Settings › About ("More details…" opens the fastfetch window, `karchy-launch-about`) |

Dropped: Agent, Learn, the Install and Remove app catalogs, toggles, the rest of the Capture submenu (text, QR, color; screenshots stay on Print), Share (LocalSend), bar and window style options, channels, kernel picker, branding, Direct Boot, Reset Computer.
