# Architecture

Status: **approved for phase 1** on 2026-11-13, with Q1–Q4 answered (D-41 to D-44). Q5 is still open, for phase 2. It is based on Omarchy `v4.5.0` (`ac2690cd7`), read at `/home/nulifyer/Projects/Omarchy/reference/omarchy-v4.5.0`.

## Repository layout

karchy's code started as a selection of Omarchy v4.5.0, renamed to karchy (D-47) and owned by karchy since (D-46). Code reads its own files from `$KARCHY_PATH/<path>`, as Omarchy's code reads `$OMARCHY_PATH`. On an installed machine `KARCHY_PATH` is `/usr/share/karchy`; dev mode points it at a checkout (D-55).

```
karchy/
├── bin/                      karchy-* commands and the karchy router
├── shell/                    the Quickshell shell, without the dropped plugins
├── themes/                   Omarchy's 23 themes + nulifyer
├── default/                  defaults the code reads: hypr modules, themed templates,
│                             karchy/karchy-menu.jsonc (the menu), karchy/icons.json
│                             (the icon map), user systemd units
├── karchy/                   karchy's composition layer
│   ├── hypr/                 init.lua, bindings.lua, autostart.lua
│   └── shell.json            default bar layout and plugin list
├── config/                   starter files for ~/.config, shipped in /etc/skel
├── system/                   /etc and /usr/lib files: sudoers, mkinitcpio, oomd, PAM,
│                             uwsm env, greetd template, pacman repos and hooks…
├── install/                  installer form, disk, base and setup steps, base package list
├── packaging/                PKGBUILDs (pkgbuilds/) and the build that makes the [karchy] repo
├── tools/                    vm, rebrand, icon-check
├── vendor/upstream.tsv       each file's Omarchy origin path and blob, for upstream review
├── LICENSE                   MIT: karchy's and Omarchy's copyright lines
├── docs/  .agents/
```

## Packages (D-51 to D-54)

The PKGBUILDs live in `packaging/pkgbuilds/`, next to the code they package, so a change and its packaging land in one commit. `packaging/build` packages the repository (a commit, or the working tree for testing) into the `[karchy]` pacman repository, which is published as a GitHub Release of this repo. Machines update with `pacman -Syu` or `karchy update`.

| Package | Contents | From |
|---|---|---|
| `karchy` | everything under `/usr/share/karchy`, `/usr/bin` links to its commands, the Hyprland reload-guard pacman hooks | `bin/ shell/ default/ karchy/ install/{helpers,provisioning} logo.txt` |
| `karchy-settings` | `/etc` defaults, user and system unit drop-ins, lock-screen PAM, `/etc/skel` starter configs (no `shell.json`: a user's file holds only differences, D-92) | `system/ config/ default/systemd/user` |
| `karchy-themes` | `/usr/share/karchy/themes` | `themes/` |
| `karchy-desktop` | meta: the packages above plus the session, services, fonts and apps | — |
| `karchy-laptop` | meta: power-profiles-daemon, bolt (USB4 docks), sof-firmware; lid and sleep drop-ins | `system/laptop` |
| `karchy-nvidia` | meta: NVIDIA modules for both kernels, utils, VA-API | — |
| `karchy-nvidia-580xx` | meta: the same for Maxwell, Pascal and Volta, with NVIDIA's 580xx driver; provides and conflicts with `karchy-nvidia` | — |
| `karchy-containers` | optional (Quick install): Podman's user socket enabled for all, DOCKER_HOST, compose and docker-notice settings | `packaging/pkgbuilds/karchy-containers` |
| `karchy-printing` | optional (Quick install): cups-browsed user and sandbox drop-in, ipp-usb | `packaging/pkgbuilds/karchy-printing` |

`karchy-keyring` is planned, with signing (D-52). Each plugin will be its own package.

`/usr/bin/karchy-*` are links into `/usr/share/karchy/bin`, so code that calls `$KARCHY_PATH/bin/…` runs the packaged command, or the checkout's in dev mode. Code that root runs (PAM, sudo rules, pacman hooks, system units) uses `/usr/bin` paths only (D-50).

**Versions (D-53).** `packaging/build` rebuilds every package and hashes its contents: files, modes, link targets, and `.PKGINFO` without version, date, size and packager. Only a package whose hash changed gets a new version, `YYYY.MM.DD.N`. The hashes live in `karchy.versions` next to the repository database, so the published repository is the only state.

**Starter configs.** `/etc/skel` seeds a new user's `~/.config` once (D-07). Updates change the defaults the configs load from `/usr/share/karchy`, never the user's files.

## Upstream review (D-46)

There is no sync. `vendor/upstream.tsv` lists, for each karchy file taken from Omarchy, its upstream path and v4.5.0 blob. `tools/rebrand text` and `tools/rebrand path` turn an upstream file and path into karchy's names, so a later Omarchy release can be diffed against karchy's copies and changes taken by hand. `tools/upstream-review` does this against an Omarchy clone: with no arguments it lists the files Omarchy changed since v4.5.0 (`--log` adds each file's commits); `diff <path>` shows one upstream change with karchy's names; `merge <path>` merges it three-way into karchy's copy for review.

## Themes

Omarchy's 23 themes (about 80 MB, mostly wallpapers) are committed under `themes/`, alongside karchy's `nulifyer` (D-42). They ship as `karchy-themes`, which changes rarely, so desktop updates don't download them again.

## Shell design foundations

The shell's shared look lives in `shell/Commons`: `Color` owns color roles, `Style` owns sizes, spacing, type and control states, and `Border` turns them into border specs. Components in `shell/Ui` read those; plugins use the components and roles rather than picking colors of their own. The roles below are derived from each theme's `colors.toml`, so all themes get them without per-theme files.

| Role | Use it for | Rule |
|---|---|---|
| `Color.secondaryText(text, surface)`, `Color.textSecondary` | Descriptions, metadata, section headers, placeholders, a dimmed icon that still carries meaning | The text color blended toward its surface, then backed off until it reaches 4.5:1. Quieter than the text in dark and light themes alike. |
| `Color.disabledText(text, surface)`, `Color.textDisabled` | A control that can't be used now, content outside the current scope (days outside the shown month) | A stronger blend with a 2:1 floor. Not for anything people must read. |
| `Color.status.error` / `warning` / `success` and `onError` / `onWarning` / `onSuccess` | Failures and destructive actions; conditions that need attention but aren't failures (captive portal, packet loss); healthy or running state | From the theme's red, yellow and green, or the first palette color of that hue, else karchy's default theme's color; then lightness adjusted to 4.5:1 on the background. `on*` is the text color on a solid status fill. A theme can pin them in `shell.toml` `[status]`. |
| `Color.focus`, `Border.focusSpec()`, `Ui/FocusRing` | Where the keyboard is: Qt focus, and the keyboard cursor of the panels, the menu and the clipboard | The accent, lightness adjusted to 3:1 against the background and the selected fill, drawn as a ring inside the control so focus never shifts layout. Hover is a faint foreground fill and border; selection is a stronger fill. `[controls] focus-*` in `shell.toml` can restyle it. |

Don't dim text with `Qt.darker()` or a hand-picked alpha: `Qt.darker()` makes dark text darker, so in light themes it inverts the hierarchy. Don't use `Color.urgent` for errors; it is the theme's raw `red`, which isn't red or readable in every theme, and it stays only for the bar's attention mark (`[bar] active`).

`Ui/ConfirmDialog` asks before destructive actions. It is built from `Ui/Button`. It opens with Cancel selected (`destructive`, the default), so pressing Enter on the request and again in the dialog never destroys anything. A host can open every confirm on Cancel with `defaultIndex: 0`; Settings does, for resets and the release-channel switch.

**Focus ring only for the keyboard.** `Ui/FocusRing` shows where the keyboard is, and only there:
- A control with Qt focus shows the ring unless a click gave it that focus (`focusReason`). Text fields keep the ring however they got focus (`textEntry`).
- A panel, menu or list cursor has no Qt focus, so the ring follows `Commons/InputMode`. Key handlers (`PanelKeyCatcher`, the menu, the clipboard, `ConfirmDialog`, window lists) call `InputMode.keyPressed()`. Real pointer movement calls `InputMode.pointerMoved()`, through `PanelKeyCatcher`'s hover handler and `PointerMoveGate`. A row under the pointer gets the hover look; a row reached with j/k also gets the ring.

**Tokens** (`Style`), beside the spacing scale and the type sizes:

| Token | Values | Use |
|---|---|---|
| Type roles | `pageTitle` = heading bold, `title` = title bold, `body`, `secondary` = bodySmall in `secondaryText`, `label` = caption bold caps with `font.labelSpacing` | `caption` is 11px at the default size; nothing people read is smaller. One page title per view. |
| `font.iconSmall` / `icon` / `iconLarge` / `iconHero` | 10 / 13 / 16 / 22 at base 12 | Inline with body / rows and buttons / dialogs and cards / panel and page heroes. A Symbols Mono icon fills its em, so one step above the adjacent text matches its capitals. |
| `radius.surface` / `radius.control` | Hyprland rounding / `min(rounding, 4)` | Cards, windows, panels, popups, tooltips / buttons, rows, fields inside them. |
| `border.surface` / `border.control` | `max(1, space(2))` / `normalBorderWidth` | Popups, the menu, polkit, the OSD / controls, cards, tooltips. |
| `motion.fast` / `base` / `slow` | 120 / 200 / 320 ms, always through `Style.duration()` | Hover and color / open, morph, move / toasts, progress. |
| `spacing.panelWidth`, `panelWidthWide`, `sidebarWidth`, `formLabelWidth`, `actionButtonSize`, `heroGap` | 380, 560, 200, 170, 22, 14 | The sizes panels, windows and forms had repeated as literals. |

`Color.onAccent` is the text on a solid accent fill. Panel content sits on `[popups]` and reads `Panel.panelText` / `panelSurface` (`Color.popups.*`), never the bar's colors; so do the OSD and `PanelSlider`.

### Components

Every component owns its look; a caller places it and never overrides its height, padding, radius, colors or ring. A caller doesn't dim a disabled control either: each shared control draws `Color.disabledText` when `enabled` is false.

| Component | What it's for |
|---|---|
| `Button` | `variant`: `neutral` (default), `primary` (accent fill; the one action a page or dialog is for), `destructive` (error text and border; keep it apart and confirm it). `busy` spins `ui.busy` and takes no clicks. `focusable: true` in windows. The accessible name is the label, else the tooltip. |
| `PanelActionButton` | The icon button. Its tooltip is its accessible name. |
| `ToggleSwitch`, `Toggle` | The switch and the labelled switch row. `busy` pulses the knob (dims it under reduced motion). `accessibleName` wherever no label sits in the control. |
| `PanelToolTip` | The one tooltip. `Button` and `PanelActionButton` use it; the bar's own tooltip window in `Bar.qml` does not yet. |
| `PageHeader` | The top of a window page: title, optional caps status in a status color, optional icon, trailing controls (moved under the title when the page is narrow), and `explanation` behind an (i) button. |
| `InfoTip` | An (i) for one control or label, opening on click, Enter or Space. Not for errors, warnings or what an action does. |
| `InlineMessage` | A condition that persists: `info`, `warning`, `error`. `text` says what failed in plain words; known failures in `details` (a closed password prompt, no network, a missing program; `Ui/Failure.js`) add a sentence; the raw output stays behind Details. Without `text`, the command's last line stands in. |
| `Card` | A bordered group on a window page, with an optional title, subtitle and trailing controls. |
| `EmptyState` | Why a list is empty and the next step: inline in panels, `centered` in windows. |
| `KeyValueGrid` | Facts as label and value pairs with tabular figures; `columns`, `justify` for the panels' narrow form, copyable values. |
| `PanelHero` | The top of every bar panel: icon (no empty slot without one), title, caps status, trailing control. |
| `ConfirmDialog` | See above. |

### Panels and windows

A bar panel answers "what's running, and is it OK?" and allows one-step actions. A window answers "show me everything and let me change it". Containers, VMs and network follow this; the display panel and the rest of Settings are next.

- **One model per plugin** (`Model.js`) feeds both: the item's name, icon, status line, status color (`statusRole`: success running, warning on its way, secondary text stopped) and what the run switch does. **One row component** (`ContainerRow.qml`, `VmRow.qml`) draws the item in the panel and in the window's sidebar, with the same `ToggleSwitch` for run state.
- **Panel:** `PanelHero` (count in the success color), a separator, a section header, at most six rows (running first, then "N more in the window"), an `EmptyState`, and a full-width "Manage …" button that opens the window at the item under the panel's cursor (`karchy containers open <name>`, `karchy vm manage <name>`). Rows carry the run switch and the commonest action (open the port, show the screen). No forms, logs or destructive actions.
- **Window:** a sidebar listing the items with the same rows, then a page: a `PageHeader` with one `primary` button, `Card`s, and a "Can't be undone" section at the bottom whose `destructive` buttons confirm with Cancel focused.
- **Window keyboard:** Tab goes from the sidebar (filter, the list as one stop, its buttons) to the page; j/k or the arrows move through the list and the page follows; Ctrl+F filters; Escape closes. The focused control scrolls into view.

### The bar: floating and docked

`bar.style` in `~/.config/karchy/shell.json` decides how the bar sits on each monitor. Set it with `karchy bar style <auto|floating|docked|cycle>` or in Settings › Appearance.

| Style | Behavior |
|---|---|
| `auto` (default; a missing key is auto) | Floats, and docks on a monitor while a window on a workspace it shows is maximized. A hidden special workspace (minimized windows) doesn't count; an open one (the drop-down terminal) does. |
| `floating` | Always floats. |
| `docked` | Always docked, the bar from before floating existed. |

- **Floating.** The strip stands off the screen edge and both its ends by `Style.bar.floatMargin` and rounds its corners by `Style.bar.floatRadius`. They follow the windows (`gapsOut`, half of Hyprland's `gaps_out`, and `cornerRadius`) unless the theme's `shell.toml` `[bar]` sets `float-margin` or `float-radius`. With gaps off, floating looks docked.
- **Docked.** The strip fills its edge at its thickness, radius 0. A top bar thickened to cover a display notch is always docked.
- **Reserved space follows the bar** (the user's choice over a constant reservation): floating reserves margin + thickness, docked the thickness. The exclusive zone takes the new state at once, not the animation, so a maximized window resizes in the same step as the maximize. On a workspace switch the windows of the arriving workspace slide by the margin together with the bar.
- **Transition.** 200 ms, `Style.duration` and `Style.easeOut`; instant when Hyprland animations are off.
- **Under a real fullscreen window** nothing changes: the bar stays under it and takes no input.
- **What others read.** `bar.barSizeFor(screen)` and `screenBarSizes` publish the footprint, thickness plus the drawn margin. Panels, popups, toasts and plugins clear the bar by it, so they move with the strip.
- **Input.** Floating, the band between the strip and the screen edge takes input too, so a pointer pushed against the edge stays on the bar.
- **Events.** The bar refreshes Hyprland's window list on `fullscreen` (sent for maximize too), `openwindow` and `movewindowv2`, and its monitor list on `activespecialv2`, `moveworkspacev2` and monitor hotplug. A burst refreshes each once. `BarModel.dockedOn` decides the state; `tools/bar-model-check` tests it.

### Icons

- **Family.** One family: Material Design icons, filled, from the Nerd Font symbols (`nf-md-*`, U+F0001–F1AF0). They are drawn in `Icons.family`, "Symbols Nerd Font Mono" (`ttf-nerd-fonts-symbols-mono`, a `karchy` dependency), never in the text font, so `karchy font set` doesn't change them. Use an `_outline` variant only where it means something (an empty Wi-Fi signal, an unused state). Brand marks (Arch, Hyprland, editors, browsers, operating systems) are the one exception and only under `brand.*` names.
- **One map.** `default/karchy/icons.json` maps names to codepoints: `"system.lock": {"cp": "f033e", "nf": "md-lock"}`. It is the only place a codepoint may appear.
  - QML: `Icons.glyph("system.lock")` with `font.family: Icons.family`. `Button.iconText`, `PanelActionButton.iconText`, `BarIconButton`/`WidgetButton` glyphs and `OpticalGlyph` users already draw in the icon family. `Icons.resolve(value)` takes a name or a raw glyph, for icons that come from outside the shell: menu JSONC `"icon"`, dmenu rows, OSD requests.
  - Menu entries: `"iconName": "system.lock"`. A literal `"icon"` glyph still works for user menus and plugins.
  - Bash: `karchy-notification-send -g system.lock` (a raw glyph still works), `"$(karchy-icon system.lock)"` elsewhere, `karchy-icon --list` for the names.
  - JS models stay plain JavaScript: they return names, and the QML that draws them calls `Icons.glyph`.
  - `tools/icon-check` fails on a codepoint anywhere else (QML, JS, JSON, Lua, bash), on a name used in code that the map lacks, and on a non-`brand.*` entry outside Material Design.
- **Names.** Lowercase words joined by dots, from the general to the specific: `audio.volume.muted`, `net.wifi.3`, `power.battery.charging.40`, `ui.chevron.down`. A name says what the icon means, not what it shows (`window.minimized`, not `window-minimize`). One concept has one name and one glyph everywhere, and two operations in one view never share a glyph. Ladders are numbered names (`net.wifi.0`–`4`, `power.battery.10`–`100`).
- **Color.** An icon takes the color of the text or state it belongs to: its surface's text role, the selected or hover state color, `Color.secondaryText()` for a dimmed icon that still means something, `Color.disabledText()` for a disabled one, `Color.status.*` for status. No hex colors and no `Qt.darker()` on icons. App, tray and brand images keep their own colors.
- **Sizes.** A Symbols Mono glyph fills its em, so the font size is the icon size. Bar: `BarIconButton` sizes by ink to `Style.bar.iconSize`. Inline with body text (chevrons, row checks): `Style.font.iconSmall`. List rows, panel rows and buttons: `Style.font.icon`. Dialogs, cards and inline empty states: `Style.font.iconLarge`. Panel and page heroes: `Style.font.iconHero`. Centered empty states: `Style.font.displayLarge`.
- **Rendering.** The bar's scaled icons are distance-field text. `karchy-launch-shell` sets `QSG_DISTANCEFIELD_ANTIALIASING=gray`; Qt otherwise picks subpixel antialiasing from the screen and fringes them red and blue.
- **GTK and Qt apps.** Papirus (`papirus-icon-theme`), Papirus-Dark or Papirus-Light by the theme's mode. On every theme switch `karchy-theme-set-gnome` writes a small theme, `~/.local/share/icons/karchy-icons-{a,b}`, that inherits it and holds only the folder icons, recolored to the theme's accent (Papirus' blue `#5294e2` to the accent, its `#4877b1` back and `#1d344f` emblem to 80% and 35% of it). The name alternates like the GTK theme's, so open apps reload it. A theme may still ship `icons.theme` naming an installed icon theme to use instead.

## Networking ownership (D-68)

One owner per job. NetworkManager connects; systemd-resolved resolves; avahi alone answers `.local`; ufw owns incoming rules, of which karchy writes only its tagged LocalSend rule. karchy owns which networks are trusted and the upstream DNS. The VPN package (`nulifyer-vpn`) owns its tunnel, its DNS while the tunnel is up and its outgoing block, and reads trust from karchy.

**Trust: karchy writes, everyone reads.**
- `/etc/karchy/trusted-networks` (root, 0644) is written only by `karchy-trusted-networks set <uuid> <true|false>`, through pkexec at its packaged path (`org.karchy.trusted-networks`). Format 2, one network per line, tab-separated: `uuid  router-mac  ssid-hex  security  name`; `ssid-hex` and `security` are `-` for Ethernet. A line with only a UUID is from format 1 and reads as "needs re-trust".
- Trusting needs the network connected: it records the profile's UUID, the default gateway's MAC address from the neighbour table on that device (IPv4 gateway, else IPv6), and for Wi-Fi the SSID and the access point's security as NetworkManager reports them. One profile may have several trusted routers (home and office on "Wired connection 1"). Untrusting removes them all.
- A connection is trusted only while its UUID, router MAC and, on Wi-Fi, SSID and security all match one record. The router MAC can be spoofed by someone on the same network; it stops the common cases: one Ethernet profile used for every jack, and a look-alike access point with the same name.
- **The query** is the contract, not the file: `karchy-trusted-networks status --json` (any user; the dispatcher hooks run it as root by its `/usr/bin` path). `.active` has one entry per active Wi-Fi or Ethernet connection:

  ```json
  {"uuid": "…", "device": "wlan0", "type": "wifi", "name": "Home-5G",
   "trusted": true, "reason": "trusted", "router_mac": "02:88:00:00:00:01"}
  ```

  `reason` is `trusted`, `not trusted` (no record), `different router` (records exist, none match), `router unknown` (records exist, the router's address couldn't be read) or `needs re-trust` (only a format-1 record). `trusted` is true only for `trusted`. `.networks` lists saved profiles for Settings; `version` is 2. Readers ask again on NetworkManager's `up`, `down`, `connectivity-change` and DHCP changes; nothing polls.
- Readers today: `karchy-localsend-firewall` (port 53317 open on trusted devices only), `karchy-network-dns` and the VPN's policy (Auto stands by on a trusted network). After a trust change `karchy-trusted-networks set` asks the VPN to look again with `/usr/lib/nulifyer-vpn/control refresh` when the package is installed.

**DNS: karchy upstream, the VPN in its tunnel.**
- `karchy-network-dns` (in karchy, run as root by `95-karchy-dns` in karchy-settings and after every trust change) gives Wi-Fi and Ethernet connections that aren't trusted the DNS from `/etc/karchy/dns`: `provider=quad9|cloudflare|custom|network`, `servers=` (custom), `encrypted=yes`, `trusted=no` (yes: trusted networks too). Without the file: Quad9 over TLS, trusted networks on the router's DNS. `fallback=no` is "encrypted only". Only `karchy-network-dns set key=value…` writes the file: Settings › Network › DNS runs it as the user, it asks for a password through pkexec of its packaged path (`org.karchy.network-dns`), and root checks every value, replaces the file and decides every connection again at once.
- It changes only the applied connection: `nmcli device modify <dev> ipv4.dns dns+tls://9.9.9.9#dns.quad9.net,… ipv4.ignore-auto-dns yes ipv6.… connection.dns-over-tls yes`. NetworkManager keeps that through DHCP renewals and drops it when the connection goes down; resolved gets per-link servers and `+DNSOverTLS`. `resolvectl` per-link changes were not used: NetworkManager rewrites them on every renewal. Global DNS was not used: it would override the VPN's.
- It waits for NetworkManager's first connectivity verdict on the device (its check uses the network's DNS, so a captive portal is still detected), hands the network its DNS back while a portal waits for sign-in, and, if the encrypted servers don't answer a test query, keeps the network's DNS until the connection next comes up and logs it (`journalctl -t karchy-network-dns`). `karchy-network-dns status` shows the state per device.
- While a VPN tunnel is up, its profile's negative `dns-priority` with `~.` makes its DNS the only one used; karchy's servers stay on the link underneath and return when the tunnel goes down. The VPN sets DNS only on its tunnel and never edits saved networks.

**The VPN: the `nulifyer-vpn` package.** Built by `packaging/pkgbuilds/nulifyer-vpn` from a pinned tag of Nulifyer/omarchy-vpn-plugin, which stays usable on stock Omarchy (`INTEGRATION=auto` in `/etc/nulifyer-vpn/config` picks karchy's trust and DNS when `karchy-trusted-networks` and `karchy-network-dns` exist). Root code in `/usr/lib/nulifyer-vpn`, units in `/usr/lib/systemd/system`, the dispatcher in `/usr/lib/NetworkManager/dispatcher.d`; `nulifyer-vpn setup` writes the config through a root helper. The contract:
- **Status, the VPN writes and karchy reads:** `/run/nulifyer-vpn/status`, JSON, replaced atomically on every change and only then: `mode` (`off|auto|on`), `state` (`off`, `standing-by`, `connecting`, `protecting`, `failed`, `paused`), `reason` (`mode`, `trusted`, `no-network`, `starting`, `no-handshake`, `activation-failed`, `tunnel-up`, `sign-in`), `network` (device, name, uuid, type, trusted, trust reason), `until` (a sign-in pause's deadline), `since`. The network panel watches it (FileView) through the adapter in `shell/plugins/panels/network/Model.js`.
- **Commands, karchy calls:** `nulifyer-vpn mode off|auto|on`, `nulifyer-vpn portal-pause`, `nulifyer-vpn reconnect`. pkexec of `/usr/lib/nulifyer-vpn/control`; the package's polkit rule allows exactly these for local, active members of wheel without a password. `karchy-network-captive-portal` runs `portal-pause` while the VPN is connecting, failed or paused: web traffic (TCP 80, 443) and the network's DNS on that link for at most five minutes with the tunnel down, ending by itself once NetworkManager reports full connectivity.
- **Trust:** the policy asks `karchy-trusted-networks status --json` (`.active[] | select(.device == upstream) | .trusted`) on dispatcher events; health checks reuse the answer for the same activation.
- **DNS:** the VPN sets DNS only on its tunnel (negative `dns-priority`, `~.`). On a trusted network in On mode the tunnel's live connection gets the default VPN priority (50) instead, so the router's own domains (`nas.lan`, the DHCP search domain) resolve through the router on the physical link and everything else through the VPN; the guard lets the local network through.
- **Firewall:** the kill switch is the VPN's own nftables table (`inet nulifyer_vpn_guard`, output only). While closed it allows DHCP, IPv6 ND, NTP, the WireGuard endpoint, karchy's DNS-over-TLS servers (TCP 853), a ping to the router (karchy reads the router's address for trust) and the tunnel's probe. It never writes ufw's chains; a broken home hairpin NAT is fixed with a stateless source rewrite in the same table (`TRUSTED_GATEWAY`).
- **Timers:** the policy runs on dispatcher events, commands and trust changes. WireGuard has no handshake event, so it sets one transient timer: 2 s while connecting, 60 s while protecting, 10 s after a failure (a fresh attempt each minute), and at a pause's deadline. Nothing runs in Off mode or while standing by.

**Airplane mode: the kernel owns the key.** `karchy-airplane on|off|toggle` blocks or unblocks every radio with rfkill (`/dev/rfkill` is the seat user's, no password) and shows the OSD; systemd-rfkill restores the blocks at boot. Turning it on is remembered in `$XDG_STATE_HOME/karchy/airplane`, and airplane mode is that choice while every radio is still blocked: NetworkManager's Wi-Fi switch blocks the Wi-Fi radio too, so "all blocked" alone would call Wi-Fi off plus Bluetooth off airplane mode. The airplane key (`XF86RFKill`) is toggled by the kernel's rfkill input handler (`CONFIG_RFKILL_INPUT`, set in Arch's and CachyOS's kernels), also at the login prompt and on a text console; Hyprland's binding runs `karchy-airplane key`, which records and shows the result and toggles itself only when `/proc/bus/input/handlers` has no rfkill handler. A program issuing `RFKILL_IOCTL_NOINPUT` (GNOME's settings daemon) would take the key from the kernel; karchy ships none. The network panel follows `rfkill event` and the remembered choice; nothing polls.

**Settings › Network** (D-66: the panel's "Network settings…" opens it at the connection under the cursor or in use, `karchy-settings network <name|uuid|device|dns|vpn|…>`). It reads `karchy-network-status --json` (every active connection with addresses, gateway, DNS in use from resolvectl and whether it is encrypted, link and MAC), `karchy-network-profile list` (saved Wi-Fi and Ethernet profiles), `karchy-trusted-networks status --json`, `karchy-network-dns status`, `karchy-network-vpn status`, `karchy-localsend-firewall status` (ufw on, its incoming policy from `/etc/default/ufw`, and where karchy opened LocalSend's port, recorded in `/run/karchy/localsend-open`) and `karchy-network-country status --json`, and follows `nmcli monitor`. Writes:
- Saved networks: `karchy-network-profile set|forget|join-hidden` through nmcli, which NetworkManager's polkit rule allows for local members of wheel without a password; values are checked first and a refusal is one sentence on stderr. Changes that apply on connecting (IP settings, private address) reconnect a network in use; metered changes the live connection with `nmcli device modify`, so karchy's DNS on it stays. A hidden network's password goes over stdin, never argv.
- Trust: `karchy-trusted-networks set` (above). DNS: `karchy-network-dns set` (above).
- Wi-Fi country: `karchy-network-country set XX|auto` writes or removes `/etc/karchy/wifi-country` through pkexec of its packaged path (`org.karchy.network-country`) and runs `/usr/lib/karchy/wifi-regdomain` (karchy-settings) at once; `auto` returns to the world domain first, then the timezone's country.
- Connectivity check: NetworkManager's `ConnectivityCheckEnabled` over D-Bus (allowed for the active session; NetworkManager keeps it across restarts).
- VPN: with the package, `nulifyer-vpn mode` and, for "Allow local devices on trusted networks", `karchy-network-vpn home-lan`, which hands the package's configuration with `HOME_LAN` changed to `nulifyer-vpn setup` (its own root helper checks it; an administrator's password). Without it, `karchy-network-vpn switch` connects NetworkManager's VPN and WireGuard profiles. `karchy-network-vpn import` adds a WireGuard `.conf` chosen in the portal's file chooser (`karchy-file-choose`) with `nmcli connection import`, under a valid interface name and with autoconnect off.

**What the panel reports.** `karchy-network-status` describes the underlying link: the lowest-metric default route in the main table that isn't a tunnel (WireGuard, tun, IP-in-IP and GRE kinds, or no link layer), and separately a `vpn_*` block (name, interface, address, whether the internet goes through it). The panel keeps the Wi-Fi QR share and the real IP and gateway with a VPN up, shows the VPN as its own line, and names the speed test "Home-5G via VPN" when the tunnel carries it.

## karchy's Hyprland composition

`~/.config/hypr/hyprland.lua` (a stub, created once):

```lua
dofile(os.getenv("KARCHY_PATH") .. "/default/hypr/bootstrap.lua")
require("karchy.hypr.init")    -- karchy's pick of default.hypr modules + bindings + autostart
require("hypr.monitors")        -- user layer (dotfiles)
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")
require("default.hypr.toggles")
```

`karchy/hypr/init.lua` requires the `default.hypr` modules karchy keeps, in Omarchy's order, plus Omarchy's media and clipboard bindings, then `karchy.hypr.bindings` (exactly `docs/keybindings.md`) and `karchy.hypr.autostart`. That autostart runs the shell, the monitor watcher, udiskie and power profiles. It leaves out herdr and Omarchy's first-run provisioning.

## Seams found (kept code that refers to dropped features)

| Where | What | Handling |
|---|---|---|
| `default/hypr/qconsole.lua:17-27` | Runs `omarchy-agent` the first time the drop-down opens | karchy's `karchy/hypr/qconsole.lua` starts a foot window instead |
| `default/hypr/omarchy.lua`, `autostart.lua` | Loads every binding, herdr and first-run | Replaced by `karchy.hypr.init` |
| `shell/plugins/menu/MenuModel.js`, `Menu.qml` | Guards and providers for dropped entries (agent, dock, kernel, channel, dictation, nightlight) | Inert once karchy's `default/karchy/karchy-menu.jsonc` drops those entries; checked in the VM |
| `shell/plugins/panels/network/Panel.qml` | DNS provider switch (`omarchy-dns` + NOPASSWD sudoers), always shown (lines 125–248) | `override` without the DNS section; `omarchy-dns` and its sudoers rule are not vendored (D-44) |
| `bin/omarchy-theme-set:531-554` | Runs 17 per-app theme commands and reports missing ones as failures | Vendor all of them; each exits early when its app is absent. `omarchy-theme-set-vscode` gets an override (D-23) |
| `bin/omarchy-pkg-aur-install` | Hard-codes `yay` | karchy override that uses paru (D-20) |
| `config/omarchy/shell.json` | Default bar layout includes the dropped modules | `karchy/shell.json` |
| `omarchy-default-{browser,editor,terminal}` | Offer to install a missing default | Kept; the defaults are always installed, so the install path never runs |

## Installer

The **form** is a gum TUI in Omarchy's style (D-08), run from the stock Arch ISO. It asks for: disk (with typed confirmation), keyboard, username, one password, name and email, hostname, timezone, Secure Boot when the firmware is in Setup Mode (default yes), and bees (on by default).

**Disk and base (D-41).** archinstall is not used. archinstall 4.5 replaces `systemd`/`sd-encrypt` with udev/busybox `encrypt` unless the disk uses a hardware security key (`archinstall/lib/installer.py:125`), and its only swap option is zram. Both conflict with D-12 and D-10. karchy's own `install/disk.sh` + `install/base.sh` do:

1. `sgdisk`: 4 GiB ESP plus a LUKS partition.
2. `cryptsetup luksFormat --type luks2`.
3. `mkfs.btrfs` and the D-09 subvolumes.
4. Mount with `zstd:1,noatime`.
5. Swap file on `@swap` via `btrfs filesystem mkswapfile`.
6. `pacstrap` the base list.
7. fstab, locale, user, mkinitcpio `HOOKS` with `systemd … sd-encrypt`.
8. Limine + limine-entry-tool + limine-snapper-sync, with `rd.luks.name=` on the kernel command line.

That's about 300 lines of bash, with each step logged and safe to retry.

Optional features get a package only when they put files in `/etc` or `/usr` (D-67); their `bin/karchy-feature-*` command installs it and does the per-user and service steps. CachyOS's CPU-tuned repositories (`cachyos-v3`, `-v4` or `-znver4`, with their core and extra) go before its generic one when the CPU supports them, picked like CachyOS's installer (`ld.so --help` for the x86-64 level, AMD family 0x19 with AVX-512 or 0x1a for Zen 4/5); `Architecture` lists the levels so the Arch ISO's pacman accepts them (D-79).

The base pacstrap includes `karchy-settings`, so the sudo policy, the mkinitcpio drop-in, the snapper template and `/etc/skel` exist before the user is created and the initramfs is built. The `[karchy]` repository is configured on the live system and in the target, after `[cachyos]`, Arch's and `[omarchy]` (D-45, D-51).

**Setup** (`install/setup.sh`) does only what depends on this machine and user (D-54):

1. Packages: `karchy-desktop`, plus `karchy-laptop` with a battery and `karchy-nvidia` (Turing and newer) or `karchy-nvidia-580xx` (Maxwell, Pascal, Volta) with an NVIDIA GPU.
2. greetd auto-login for the user, mDNS in `nsswitch.conf`, ufw enabled.
3. Services: greetd, bluetooth, avahi, ufw, smartd, paccache, oomd, power-profiles-daemon (laptop); for every user, the foot server and karchy's sleep-lock and internal-monitor units.
4. The default theme, nulifyer, applied without a session.

## VM (`tools/vm`)

- `tools/vm fetch` downloads the current Arch ISO and checks its signature.
- `tools/vm new` creates a 40 GiB qcow2 disk and UEFI variables (OVMF; the Secure Boot firmware with `--secureboot`) and defines the VM in libvirt (`qemu:///system`) as `karchy-<vm>`, so it shows in virt-manager.
- `tools/vm run` starts it and opens its console in virt-manager (`--headless` skips the window): 4 vCPUs, 8 GiB RAM, virtio graphics over SPICE (3D with `KARCHY_VM_GL=1`), QEMU's user network, and the karchy checkout shared read-only over 9p, so the installer runs from the local branch without a push. The CD drive boots first and is saved empty, so starting the VM anywhere (virt-manager included) boots the disk; `--iso` loads the ISO for that one boot.
- `screenshot`, `type` and `key` go through virsh, so unattended checks work on a VM you are also watching.
- `tools/vm repo` serves a local `packaging/build` to guests at `http://10.0.2.2:8090`; `tests/vm-install.conf` installs from it.
- `tools/vm snap` and `restore` use qcow2 snapshots for quick retries.

Host check: `qemu-desktop` 11.1.3, libvirt 12.9, `edk2-ovmf` (including `OVMF_CODE.secboot.4m.fd`), swtpm and `/dev/kvm` are present. libvirt runs QEMU as `libvirt-qemu`; `tools/vm` adds an execute-only ACL for it only on directories under `$HOME` that it can't already enter.

## Milestone 1 scope

**In:**
- installer, disk and base
- setup with the Always tier (Detected tier for the VM's hardware only)
- greetd → Hyprland → shell
- karchy bindings and menu
- nulifyer and theme switching
- `karchy update`

**Deferred to phase 2:**
- the Settings window, GTK color template and VS Code theme extension
- the Thunar actions and NAS flow
- LocalSend firewall hook
- bees and Secure Boot
- the keyring choice (decided: D-57)
- the dotfiles user layer: milestone 1 uses karchy's stubs only

## Questions

- **Q1. Disk and base:** karchy's own pacstrap scripts (D-41).
- **Q2. Themes:** committed (D-42).
- **Q3. Command names:** vendored commands keep their `omarchy-*` names; karchy's own are `karchy-*`, with a `karchy` router for `karchy update` and `karchy vm`; the `omarchy` router stays (D-43).
- **Q4. DNS switch:** removed (D-44).
- **Q5. Dotfiles checkout location** (phase 2, still open): `~/.local/share/karchy-user` or `~/Projects/dotfiles`?

## Appendix: commands taken from Omarchy v4.5.0

Historical: the selection before the ownership audit (`docs/ownership-audit.md`) dropped more, and before the rebrand to `karchy-*`. The 205 found by tracing, by group (the `omarchy-` prefix is omitted):

- **apply:** `apply-lock`
- **audio:** `audio-input-mute`, `audio-input-set-default`, `audio-output-set-default`, `audio-output-sink`, `audio-output-switch`, `audio-output-volume`, `audio-sink-availability`, `audio-source-switch`, `audio-tuning`
- **bar:** `bar`, `bar-text-color`
- **battery:** `battery-low`, `battery-status`
- **bluetooth:** `bluetooth-device`, `bluetooth-power`
- **brightness:** `brightness-display`, `brightness-display-apple`, `brightness-display-ddc`, `brightness-keyboard`, `brightness-keyboard-mute`
- **capture:** `capture-region`, `capture-screenrecording`, `capture-screenrecording-process`, `capture-screenshot`, `capture-webcam-list`, `capture-webcam-resize`
- **clipboard:** `clipboard-open`, `clipboard-paste-file`, `clipboard-paste-text`
- **cmd:** `cmd-browser-handoff`, `cmd-default-browser`, `cmd-missing`, `cmd-present`, `cmd-terminal-cwd`
- **default:** `default-browser`, `default-editor`, `default-terminal`
- **disk, display, drive:** `disk-speedtest`, `display-text-size`, `drive-info`, `drive-password`, `drive-select`
- **font:** `font-current`, `font-list`, `font-set` (override per D-23)
- **misc:** `git-url-check`, `hibernation-available`, `hook`, `i18n`, `language`, `lifecycle-dispatch`, `locale-generate`, `monitor-state`, `notification-send`, `osd`, `reminder`, `screensaver`, `show-done`, `sleep-disabled`, `state`, `sudo-keepalive`, `update-firmware`, `update-time`
- **hw:** `hw-clamshell`, `hw-display`, `hw-external-monitors`, `hw-fingerprint`, `hw-laptop`, `hw-laptop-closed`, `hw-match`, `hw-nvidia`, `hw-nvidia-display`, `hw-nvidia-gsp`, `hw-nvidia-without-gsp`, `hw-platform`
- **hyprland:** `hyprland-corners`, `hyprland-focus-app`, `hyprland-monitor-clamshell`, `hyprland-monitor-external-active`, `hyprland-monitor-focused`, `hyprland-monitor-focused-apple`, `hyprland-monitor-internal`, `hyprland-monitor-internal-mirror`, `hyprland-monitor-laptop`, `hyprland-monitor-modeless`, `hyprland-monitor-scaling`, `hyprland-monitor-watch`, `hyprland-reload-guard`, `hyprland-session-lock-stranded`, `hyprland-session-locked`, `hyprland-toggle`, `hyprland-toggle-disabled`, `hyprland-toggle-enabled`, `hyprland-window-close-all`, `hyprland-window-minimize`, `hyprland-window-transparency`, `hyprland-workspace-layout-current`, `hyprland-workspace-layout-default`, `hyprland-workspace-layout-toggle`
- **launch:** `launch-about`, `launch-browser`, `launch-config-editor`, `launch-editor`, `launch-or-focus`, `launch-or-focus-tui`, `launch-or-focus-webapp`, `launch-screensaver`, `launch-shell`, `launch-terminal`, `launch-tui`, `launch-webapp`
- **menu:** `menu`, `menu-images`, `menu-keybindings`, `menu-plugin`, `menu-select`, `menu-timezone`
- **network:** `network-band`, `network-captive-portal`, `network-qr`, `network-speedtest`, `network-status`
- **pkg:** `pkg-add`, `pkg-aur-install` (override: paru), `pkg-drop`, `pkg-install`, `pkg-missing`, `pkg-present`, `pkg-remove`
- **plugin:** `plugin-add`, `plugin-catalog`, `plugin-clone`, `plugin-disable`, `plugin-enable`, `plugin-list`, `plugin-remove`, `plugin-update`, `plugin-validate`
- **powerprofiles:** `powerprofiles-init`, `powerprofiles-list`, `powerprofiles-set`
- **remove/setup:** `remove-launcher-entry`, `remove-security-fido2`, `remove-security-fingerprint`, `remove-security-ssh-agent`, `remove-security-sshd`, `setup-git`, `setup-input`, `setup-keyboard`, `setup-security-fido2`, `setup-security-fingerprint`, `setup-security-ssh-agent`, `setup-security-sshd`
- **restart:** `restart-audio`, `restart-bluetooth`, `restart-btop`, `restart-hyprctl`, `restart-shell`, `restart-terminal`, `restart-trackpad`, `restart-wifi`, `restart-xcompose`
- **router/shell/system:** `omarchy`, `shell`, `shell-config`, `system`, `system-lid-inhibit`, `system-lock`, `system-sleep-lock`, `system-stats`, `system-wake`
- **theme:** `theme-bg-boot-intro`, `theme-bg-cache`, `theme-bg-next`, `theme-bg-set`, `theme-bg-switcher`, `theme-color`, `theme-colors-from-alacritty`, `theme-extras`, `theme-install`, `theme-list`, `theme-osc`, `theme-refresh`, `theme-remove`, `theme-set`, `theme-set-browser`, `theme-set-browser-policy`, `theme-set-claude`, `theme-set-foot`, `theme-set-glass`, `theme-set-gnome`, `theme-set-t3code`, `theme-set-templates`, `theme-set-tmux`, `theme-set-vscode` (override per D-23), `theme-switcher`
- **toggle:** `toggle`, `toggle-animations`, `toggle-bar`, `toggle-enabled`, `toggle-input-device`, `toggle-touchpad`
- **webapp:** `webapp-install`, `webapp-remove`, `webapp-window-class`

Plus 11 commands that `theme-set` calls and that exit early when their app is absent: `theme-set-hunk`, `-pi`, `-hermes`, `-obsidian`, `-keyboard`, `-keyboard-asus-rog`, `-keyboard-f16`, `-fcitx5`, `-herdr-machines`, plus `restart-opencode` and `restart-helix`. The exact count is settled by `tools/vendor-sync --closure`.
