# Menu

The Omarchy menu engine with a karchy tree (D-18). Super+Space opens it, and typing searches apps. Tags: [O] Omarchy entry kept, [New] karchy addition.

**What belongs here** (D-133, user 2026-11-19): the menu is for what you do now. A row is an action (restart, record, install, shut down), a quick-open link (Settings, Update System, Keybindings) or an app launch. What you set and leave (preferences, enrolment, accounts, passwords) is in the Settings window, and every Settings page is found from the menu's search. Theme and Background are the two pickers kept in the menu, because they are used often. A new row that is a preference picker goes to Settings instead.

Every row says what it does, so a search result reads on its own ("Restart Wi-Fi", not "Wi-Fi"); one card width at every level; the header shows where you are ("Restart"), or "Search…" at the top; Title Case throughout (D-73). The root is ten rows (527 px). A list ends in a cut-off row only when it is more than one row over 70% of the screen's height, so the root shows whole, Power included, from about 680 px of screen height up: 1280×800 at scale 1, 1920×1200 at 1.6.

- **Apps:** search installed desktop apps [O]. App results carry no "Apps" subtitle. The Virtual Machines and Containers windows are apps here while their feature is installed (D-116), not menu rows.
- **Packages**
  - Quick Install: the Quick install window, common apps and karchy's optional features by category, searched like fzf (D-70) [New]
  - Install Package: fzf over repo packages, `pacman -Sii` preview, multi-select [O]
  - Install AUR Package: the same flow through paru [O]
  - Remove Package [O]
  - Install Web App, Remove Web App (once one exists): icons from the site, then Dashboard Icons (D-82) [O] + [New]
- **Record Screen:** Stop Recording while one runs; No Audio, Desktop Audio, Desktop + Microphone, Desktop + Microphone + Webcam (only when a webcam is present). Then pick a region, window or monitor [O] + [New]
- **Theme:** opens the theme picker [O]. Also in Settings › Appearance.
- **Background:** opens the background picker [O]. Also in Settings › Appearance.
- **Settings:** opens the karchy Settings window (D-27) [New]
- **Update System:** the Updates window (`karchy updates`; D-81) [New]
- **Keybindings:** the keybinding viewer (Super+K) [O]
- **Restart:** Restart Shell, Reload Hyprland, Restart Audio, Restart Wi-Fi, Restart Bluetooth (with an adapter), Restart Trackpad (with a touchpad) [O]
- **Power:** Lock, Suspend, Hibernate (only if available), Log Out, Reboot, Shutdown; Super+Escape and the power key open it [O]

## Search-only rows

Settings and Update System are rows that open a window, so their children never list. Searching offers them, each labelled as where it goes, with no subtitle: "Settings › Security". The aliases are the words people type for what the page holds, including every row that used to be in the menu.

| Row | Opens | Found by |
| --- | --- | --- |
| Settings › Displays | `karchy settings displays` | displays, monitors, screen, resolution, scale, night light |
| Settings › Input | `karchy settings input` | keyboard, mouse, touchpad, trackpad, input, input config, edit keybindings |
| Settings › Power | `karchy settings power` | power, battery, sleep, lid, idle, suspend, hibernate |
| Settings › Network | `karchy settings network` | network, wifi, wi-fi, ethernet, vpn, dns |
| Settings › Notifications | `karchy settings notifications` | notifications, do not disturb, dnd, silent |
| Settings › Storage | `karchy settings storage` | disk, storage, space, bees, smart, nas, smb, samba, share, network shares, mount |
| Settings › Security | `karchy settings security` | security, fingerprint, fido2, yubikey, security key, password, passwd, change password, drive password, luks, encryption |
| Settings › SSH & Git | `karchy settings ssh` | ssh, sshd, ssh server, ssh agent, git, github |
| Settings › Date & Time | `karchy settings datetime` | timezone, time, clock, date, ntp |
| Settings › Appearance | `karchy settings appearance` | appearance, style, bar style, lock screen clock, workspace layout, tiling, floating, looknfeel |
| Settings › Fonts | `karchy settings fonts` | font, fonts, text size, monospace font, app font, terminal font |
| Settings › Default Apps | `karchy settings apps` | default apps, default browser, file associations |
| Settings › About | `karchy settings about` | about, version, system info, fastfetch, hyprland config |
| Update System › Firmware | `karchy updates firmware` (the Updates window at its Firmware part) | firmware, fwupd, bios |

Ranking: a row whose own name matches comes before one matched only by an alias, so "suspend" puts the Suspend action first and Settings › Power second, and "install package" puts Install Package above the Packages submenu (D-77). A row that names the query as an alias comes before rows whose label merely contains it. `tests/menu-search.js` checks every alias above against the shipped menu.

## Where the rows that left went (D-133)

| Was in the menu | Now |
| --- | --- |
| Appearance › Theme, Background | top-level rows; also Settings › Appearance |
| Appearance › Font | Settings › Fonts |
| Appearance › Workspace Layout | Settings › Appearance (`karchy-hyprland-workspace-layout-default`) |
| Setup › Security (fingerprint, FIDO2) | Settings › Security |
| Setup › Network Shares | Settings › Storage (Keep a share mounted…, Stop keeping) |
| Setup › Set Up Git | Settings › SSH & Git |
| Setup › Keybindings | top-level row |
| Setup › Config Files | an "Open config file" link in the header of the matching Settings page (Input: `input.lua`, `bindings.lua`; About: `hyprland.lua`) |
| Update › Update System | top-level row |
| Update › Update Firmware | the Updates window's Firmware part |
| Update › Restart | top-level submenu |
| Update › Passwords | Settings › Security |
| Update › Set Timezone, Sync Clock | Settings › Date & Time (`karchy menu timezone` still opens the picker by itself) |
| System Info | Settings › About ("More details…" opens the fastfetch window, `karchy-launch-about`) |

Dropped: Agent, Learn, the Install and Remove app catalogs, toggles, the rest of the Capture submenu (text, QR, color; screenshots stay on Print), Share (LocalSend), bar and window style options, channels, kernel picker, branding, Direct Boot, Reset Computer.
