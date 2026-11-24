# Architecture

How karchy's repository, its packages, its shell and its installer fit together, for people who change it. karchy started from Omarchy `v4.5.0` (`ac2690cd7`) and owns that code now (D-46, D-47); `vendor/upstream.tsv` maps each file to where it came from. The decisions behind what is described here are in `.agents/DECISIONS.md`, by their D numbers.

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
│   ├── hypr/                 init.lua, bindings.lua, keys.lua (the keybinding layers), autostart.lua
│   └── shell.json            default bar layout and plugin list
├── skills/                   agent skills, one folder each (SKILL.md and references/);
│                             see Agent skills below
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
| `karchy` | everything under `/usr/share/karchy`, `/usr/bin` links to its commands, the Hyprland reload-guard pacman hooks, karchy's mark as a font (`/usr/share/fonts/karchy`) | `bin/ shell/ default/ karchy/ install/{helpers,provisioning} logo.txt logo-mark.txt system/fonts/` |
| `karchy-settings` | `/etc` defaults, user and system unit drop-ins, lock-screen PAM, `/etc/skel` starter configs (no `shell.json`: a user's file holds only differences, D-92) | `system/ config/ default/systemd/user` |
| `karchy-themes` | `/usr/share/karchy/themes` | `themes/` |
| `karchy-desktop` | meta: the packages above plus the session, services, fonts and apps | — |
| `karchy-laptop` | meta: power-profiles-daemon, bolt (USB4 docks), sof-firmware; lid and sleep drop-ins | `system/laptop` |
| `karchy-nvidia` | meta: NVIDIA modules for both kernels, utils, VA-API | — |
| `karchy-nvidia-580xx` | meta: the same for Maxwell, Pascal and Volta, with NVIDIA's 580xx driver; provides and conflicts with `karchy-nvidia` | — |
| `karchy-containers` | optional (Quick install): Podman's user socket enabled for all, DOCKER_HOST, compose and docker-notice settings | `packaging/pkgbuilds/karchy-containers` |
| `karchy-printing` | optional (Quick install): cups-browsed user and sandbox drop-in, ipp-usb | `packaging/pkgbuilds/karchy-printing` |

| `karchy-vpn` | transitional and empty (D-156): what the VPN add-on became when the VPN moved into `karchy-settings`; retired | `packaging/pkgbuilds/karchy-vpn` |
| `karchy-project-picker` | add-on (Quick install): the project picker overlay and its Ctrl+Alt+P binding | `addons/project-picker` |
| `guget`, `sqlgo` | apps (Quick install): the user's NuGet and SQL TUIs, `/usr/bin/guget` and `/usr/bin/sqlgo` from a pinned GitHub release (D-155) | `packaging/pkgbuilds/guget`, `packaging/pkgbuilds/sqlgo` |

`karchy-keyring` is planned, with signing (D-52).

**Package tiers (D-108).** Core packages are the dependencies of `karchy`, `karchy-desktop`, `karchy-settings` and the meta-packages; karchy owns that set, adds through `depends` and removes through `default/karchy/retired-packages`, which `karchy update` applies (`karchy-package-retire`: only what is installed as a dependency and required by nothing). Removable apps are the catalog's `default` entries, installed explicitly at install time and the user's from then on. Add-ons and everything from Quick install are the user's. The rules for changing the set: `docs/maintenance.md` › The package set.

**Add-ons (D-106).** Anything that adds to karchy is a pacman package built from karchy's own tree and released with it on every channel; there are no plugins installed from git. An add-on's source lives in `addons/<name>` (imported with its history), its PKGBUILD in `packaging/pkgbuilds/`. It puts its shell UI (a `manifest.json` and its QML) in the root-owned `/usr/share/karchy/plugins/<plugin id>/`, which the shell's plugin registry scans beside its first-party plugins, and Hyprland bindings or rules in `/usr/share/karchy/hypr.d/*.lua`, which `karchy/hypr/init.lua` loads after karchy's own bindings and before the user's files; karchy's pacman hooks reload Hyprland when those change, and the shell scans its plugins again when that folder changes, adding and dropping the add-on's UI without touching the rest (an upgraded add-on's new code runs from the next shell start, as karchy's own does). The shell loads no plugins from the home folder. Every plugin is karchy's own, so the shell trusts them alike: an add-on gets the same shell, bar and services as a built-in one, and its ids share the `karchy.*` namespace; a built-in plugin keeps its id if an add-on repeats it (D-111). Every installed plugin is on unless `disabledPlugins` in `shell.json` lists it; a bar widget is in the bar when the bar layout holds it. `karchy plugin list`, `enable` and `disable` switch them; Quick install turns an add-on's UI on after installing it.

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
| `Color.status.error` / `warning` / `success` and `errorText` / `warningText` / `successText` | Failures and destructive actions; conditions that need attention but aren't failures (captive portal, packet loss); healthy or running state | From the theme's red, yellow and green, or the first palette color of that hue, else karchy's default theme's color; then lightness adjusted to 4.5:1 on the background. `on*` is the text color on a solid status fill. A theme can pin them in `shell.toml` `[status]`. |
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

`Color.accentText` is the text on a solid accent fill (never name a property `on` + capital: QML binds it as a signal handler and it stays black). Panel content sits on `[popups]` and reads `Panel.panelText` / `panelSurface` (`Color.popups.*`), never the bar's colors; so do the OSD and `PanelSlider`.

### Alignment

A window page has two columns and two edges. Labels start at the page's left edge and are `spacing.formLabelWidth` wide (`SettingsLabel`); controls, and the values of a page's lists (`KeyValueGrid.valueColumn`), start at `spacing.formControlColumn`. Dropdowns, text fields, slider tracks and meters end at the page's right edge; where a value or a button follows a slider, that ends there instead. A button for a whole section stands at the left edge, one that belongs to a field in the control column.

Every control is `spacing.controlHeight` tall (buttons, dropdowns and fields alike), a row that shows only text is as tall, and form rows are `spacing.md` apart whether a grid or a `Section` stacks them. What a control needs around itself lies outside its box, so the visible part starts at the column: a switch's focus ring (`ToggleSwitch.flush`), the half knob at each end of a slider (`PageSlider`). `PageHeader` is a control's height with or without buttons beside the title, so every page's title and first row sit at one place.

A bar panel has no label column, only its two edges: headings, slider tracks, values, switches and buttons stand on them, and a flat `Toggle`'s fill under the pointer reaches past them into the panel's padding.

### Components

Every component owns its look; a caller places it and never overrides its height, padding, radius, colors or ring. A caller doesn't dim a disabled control either: each shared control draws `Color.disabledText` when `enabled` is false.

| Component | What it's for |
|---|---|
| `Button` | `variant`: `neutral` (default), `primary` (accent fill; the one action a page or dialog is for), `destructive` (error text and border; keep it apart and confirm it). `busy` spins `ui.busy` and takes no clicks. `focusable: true` in windows. The accessible name is the label, else the tooltip. |
| `PanelActionButton` | The icon button. Its tooltip is its accessible name. |
| `SettingRow` | A switch as one line of a form on a window page: label in the label column, switch, optional `info` behind an (i), and one short `note` (with `warning`) for a consequence or why the setting has no effect, shown only while it applies. The form for every switch in Settings and the VM page (D-113). |
| `ToggleSwitch`, `Toggle` | The switch and the labelled switch row of the bar panels (`flat: true` there: no box inside the panel's own). `ToggleSwitch.flush` makes the track the switch's box, for a form column or a heading line. `busy` pulses the knob (dims it under reduced motion). `accessibleName` wherever no label sits in the control. |
| `PanelToolTip` | The one tooltip. `Button` and `PanelActionButton` use it; the bar's own tooltip window in `Bar.qml` does not yet. |
| `PageHeader` | The top of a window page: title, optional caps status in a status color, optional icon, trailing controls (moved under the title when the page is narrow), and `explanation` behind an (i) button. |
| `InfoTip` | An (i) for one control or label, opening on click, Enter or Space. Not for errors, warnings or what an action does. |
| `ConfigFileLink` | A quiet link in a page's header to a config file of the person's own (`file`, relative to the home folder), opened in their editor and made from karchy's starter when missing (D-133). Never for files karchy generates. |
| `InlineMessage` | A condition that persists: `info`, `warning`, `error`. `text` says what failed in plain words; known failures in `details` (a closed password prompt, no network, a missing program; `Ui/Failure.js`) add a sentence; the raw output stays behind Details. Without `text`, the command's last line stands in. |
| `Section` | A part of a window page: a rule, a small-caps heading with an optional (i) and trailing control, an optional status line, then its content, with no box. `titleTo` continues the heading after an arrow icon ("karchy 0.1.0 → 0.2.0" in Updates). What every page of Settings and of the Updates, VMs and Containers windows is built from (D-114). |
| `Card` | A bordered box for one item among like items (a disk, a key, a connection, an image), with an optional title, subtitle and trailing controls. Not for a part of a page: that is a `Section`. |
| `EmptyState` | Why a list is empty and the next step: inline in panels, `centered` in windows. |
| `ListScrollBar` | The scrollbar of a list or page that can be longer than its view (`ScrollBar.vertical: ListScrollBar {}`): shown whenever there is more than fits, in the theme's text color. Not Qt's `ScrollBar`, which a dark theme hides and which only appears while scrolling. |
| `KeyValueGrid` | Facts as label and value pairs with tabular figures; `columns`, `justify` for the panels' narrow form, copyable values. |
| `PanelHero` | The top of every bar panel: icon (no empty slot without one), title, caps status, trailing control. |
| `ConfirmDialog` | See above. |

### Panels and windows

A bar panel answers "what's running, and is it OK?" and allows one-step actions. A window answers "show me everything and let me change it". Containers, VMs and network follow this; the display panel and the rest of Settings are next.

- **One model per plugin** (`Model.js`) feeds both: the item's name, icon, status line, status color (`statusRole`: success running, warning on its way, secondary text stopped) and what the run switch does. **One row component** (`ContainerRow.qml`, `VmRow.qml`) draws the item in the panel and in the window's sidebar, with the same `ToggleSwitch` for run state.
- **Panel:** `PanelHero` (count in the success color), a separator, a section header, at most six rows (running first, then "N more in the window"), an `EmptyState`, and a pop-out icon button in the hero (`ui.open-external`, "Open as a window"; the same in both panels) that opens the window at the item under the panel's cursor (`karchy containers open <name>`, `karchy vm manage <name>`). Rows carry the run switch and the commonest action (open the port, show the screen). No forms, logs or destructive actions.
- **Ways in:** the bar icon shows only while something runs, so each window is also an app in the launcher while its feature is installed (D-116): `karchy-vms.desktop` ships in `karchy` with `TryExec=qemu-system-x86_64` (VMs have no package; the launcher honors TryExec and looks again each time the menu opens), `karchy-containers.desktop` ships in `karchy-containers`. Removing either app from the launcher runs the feature's own removal (`X-Karchy-Feature`).
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

### Fonts (D-120)

Two fonts are chosen, each in one place, and neither choice writes a file of the user's (D-23).

- **Monospace** is fontconfig's `monospace`, for what is typed or read as code (D-149): the four terminals (their starter configs name `monospace`), code editors, GTK's monospace text, and in the shell `Style.font.mono`, which key names, addresses, paths, file names and commands use (`KeyValueGrid` rows with `mono: true`, `SettingRow.command`, `ConfigFileLink`) (`system/glib-schemas/50_karchy.gschema.override` sets `monospace-font-name` to `monospace 11`). `system/fontconfig/50-karchy.conf` puts Noto Sans Mono right before `monospace`; `karchy font set` writes the same rule for the chosen family to `~/.local/state/karchy/fontconfig/font.conf`, which that file includes first, so the chosen family comes ahead of the default. Both rules use `mode="prepend"` at `monospace`: a font asked for by name stays first, and `monospace` stays in the pattern for later rules. The user's `~/.config/fontconfig/` loads afterwards (`50-user.conf`) and wins with a `prepend_first`, `binding="strong"` rule.
- **The interface font** is for text that is read: GNOME's `font-name`, Noto Sans by the same gschema override unless `karchy font app set` changed it (dconf, the store the text size uses). Apps use it (GTK, and Qt through `QT_QPA_PLATFORMTHEME=gtk3`), and so does the shell: `Style.font.family` is the family `karchy-font-app-current` prints, read at start and again whenever `gsettings monitor` reports a change, so the shell follows without a restart. `monospace` there follows the monospace font. Window titles drawn by Hyprland (group tabs, title bars) ask for `sans-serif`, which is Noto Sans; they do not follow another choice. `karchy font list` and `set` take Noto Sans Mono by name: fontconfig doesn't mark it fixed-width, because some of its symbols are wider.
- **Icons in text.** `50-karchy.conf` lists Symbols Nerd Font Mono after `monospace`, `sans-serif` and `serif`, so an icon in text is drawn whichever text font is chosen or installed. fontconfig prefers an installed Nerd text font for them (it also covers the language), and falls back to the symbols font. The shell's own icons never depend on this (Icons, below). karchy's mark follows the symbols font in the same lists: it is U+100000 in karchy Symbols (`/usr/share/fonts/karchy/karchy-symbols.ttf`, in the `karchy` package), a codepoint no Nerd Font uses, so text in any font can show it; the fish prompt does.
- **The shell restarts** on a monospace change, because Qt resolves `monospace` once (not on an interface font change, which names the family). Settings runs `karchy-font-set` detached and the command opens Settings › Fonts again. A running terminal keeps the font it started with, also after a config reload (kitty's `SIGUSR1` and Ghostty's `SIGUSR2` were tried): open windows stay, and a terminal started afterwards uses the new font. foot's server is a running terminal, so `karchy-footclient` restarts it when it has no windows, or names the family for the new window.
- **More fonts** are Quick install entries in the Fonts category (`font` names the family), installed by the same root helper (D-109). `karchy-font-list --json` joins the installed families with those entries for Settings › Fonts. Each entry has a picture in `default/karchy/font-specimens/`, drawn by `tools/font-specimens` and committed, so a font is shown in its own face before it is installed; `FontPicker.qml` paints the text color through the picture.
- **Checks.** `tests/fonts.sh` runs the fontconfig rules through `fc-pattern` and the commands against a fake `fc-list` and `gsettings`.

### Icons

- **Family.** One family: Material Design icons, filled, from the Nerd Font symbols (`nf-md-*`, U+F0001–F1AF0). They are drawn in `Icons.family`, "Symbols Nerd Font Mono" (`ttf-nerd-fonts-symbols-mono`, a `karchy` dependency), never in the text font, so `karchy font set` doesn't change them. Use an `_outline` variant only where it means something (an empty Wi-Fi signal, an unused state). Brand marks (Arch, Hyprland, editors, browsers, operating systems) are an exception and only under `brand.*` names; the two password dots are the other (Symbols, below). karchy's own mark is `brand.karchy`, from karchy's own font (The mark, below).
- **One map.** `default/karchy/icons.json` maps names to codepoints: `"system.lock": {"cp": "f033e", "nf": "md-lock"}`. It is the only place a codepoint may appear.
  - QML: `Icons.glyph("system.lock")` with `font.family: Icons.family`. `Button.iconText`, `PanelActionButton.iconText`, `BarIconButton`/`WidgetButton` glyphs and `OpticalGlyph` users already draw in the icon family. `Icons.resolve(value)` takes a name or a raw glyph, for icons that come from outside the shell: menu JSONC `"icon"`, dmenu rows, OSD requests.
  - Menu entries: `"iconName": "system.lock"`. A literal `"icon"` glyph still works for user menus and plugins.
  - Bash: `karchy-notification-send -g system.lock` (a raw glyph still works), `"$(karchy-icon system.lock)"` elsewhere, `karchy-icon --list` for the names.
  - JS models stay plain JavaScript: they return names, and the QML that draws them calls `Icons.glyph`.
  - `tools/icon-check` fails on a codepoint anywhere else (QML, JS, JSON, Lua, bash), on a name used in code that the map lacks, and on a non-`brand.*` entry outside Material Design. It also fails on the two ways a symbol ends up in the text font (Symbols, below).
- **Symbols.** Every symbol is an icon, so it looks the same whichever font is chosen in Settings › Fonts (D-157). A text font draws an arrow, a dot or a shape its own way, or lacks it and lets another font stand in: under Noto Sans the lock screen's dots were twice the size they were under JetBrains Mono.
  - No symbol as a character. An arrow (→ ↑ ↓), a geometric shape (● ■ ▶), a technical or miscellaneous symbol, a dingbat (✓ ✗), a braille pattern or a box or block character isn't written in the shell's QML and JS, as a character or as a `\u` escape. Use the map's icon in its own `Text` with `font.family: Icons.family` (`ui.arrow.*`, `ui.chevron.*`, `ui.check`), or a word. `tools/icon-check` lists the ranges (`SYMBOL_RANGES`); comments may hold them.
  - No glyph joined to text. `Icons.glyph("input.keyboard") + "  " + label` is one string in one font, the text font. Put the glyph and the words in a `Row` of two `Text`s. `tools/icon-check` fails on the `+`; `Settings › Fonts`' sample joins them on purpose and is named in the tool (`JOIN_EXEMPT`).
  - Punctuation stays text: … · — – “ ” × ° and the `›` that separates a path in a sentence ("Power › Reboot"). A chevron that means "opens a menu" or "back" is `ui.chevron.*`.
  - A row of two icons needs a gap (`Row.spacing`): each fills its em, so they would touch.
  - Password dots. A field that hides what is typed shows a dot of the icon font for each character: `Ui/PasswordInput` (the lock screen, the login screen), `Ui/TextField` with `password: true`, and the password dialog. `TextInput.passwordCharacter` takes one UTF-16 unit and a Material Design glyph takes two, so the map keeps two names outside Material Design for it: `ui.password-dot` (`oct-dot_fill`, a dot half its em wide, for a field at the text's size) and `ui.password-dot.large` (`fa-circle`, a disc that fills its em, so the font size is its diameter). A masked `TextField` keeps the text font's height and switches to the icon font only while it holds text, so its placeholder stays text.
- **The mark.** karchy's mark (Tiles, `docs/logo.svg`) is a glyph: `brand.karchy`, U+100000 in the font "karchy Symbols" (D-125). `tools/karchy-glyph-font` builds `system/fonts/karchy-symbols.ttf` from the SVG's paths with fonttools; the file is committed and the `karchy` package installs it. U+100000 is the first codepoint of Supplementary Private Use Area-B, which Nerd Fonts leave empty (`tools/karchy-glyph-font --check` reads the installed Nerd Fonts to confirm). The glyph is made for text: one terminal cell wide (0.6 em), a square of JetBrains Mono's x-height (0.55 em) on the baseline, in an em with the symbols font's ascent and descent. It doesn't fill its em as the Material Design icons do, so size it by ink (`BarIconButton`, `OpticalGlyph` with `paintedSize`) or use it in a line of text. fontconfig lists the font after the symbols font, so `Icons.family` and every text font find it. The Linux console can't show it; the prompt there has no logo.
- **Names.** Lowercase words joined by dots, from the general to the specific: `audio.volume.muted`, `net.wifi.3`, `power.battery.charging.40`, `ui.chevron.down`. A name says what the icon means, not what it shows (`window.minimized`, not `window-minimize`). One concept has one name and one glyph everywhere, and two operations in one view never share a glyph. Ladders are numbered names (`net.wifi.0`–`4`, `power.battery.10`–`100`).
- **Color.** An icon takes the color of the text or state it belongs to: its surface's text role, the selected or hover state color, `Color.secondaryText()` for a dimmed icon that still means something, `Color.disabledText()` for a disabled one, `Color.status.*` for status. No hex colors and no `Qt.darker()` on icons. App, tray and brand images keep their own colors.
- **Sizes.** A Symbols Mono glyph fills its em, so the font size is the icon size. Bar: `BarIconButton` sizes by ink to `Style.bar.iconSize`. Inline with body text (chevrons, row checks): `Style.font.iconSmall`. List rows, panel rows and buttons: `Style.font.icon`. Dialogs, cards and inline empty states: `Style.font.iconLarge`. Panel and page heroes: `Style.font.iconHero`. Centered empty states: `Style.font.displayLarge`.
- **Rendering.** The bar's scaled icons are distance-field text. `karchy-launch-shell` sets `QSG_DISTANCEFIELD_ANTIALIASING=gray`; Qt otherwise picks subpixel antialiasing from the screen and fringes them red and blue.
- **GTK and Qt apps.** Papirus (`papirus-icon-theme`), Papirus-Dark or Papirus-Light by the theme's mode. On every theme switch `karchy-theme-set-gnome` writes a small theme, `~/.local/share/icons/karchy-icons-{a,b}`, that inherits it and holds only the folder icons, recolored to the theme's accent (Papirus' blue `#5294e2` to the accent, its `#4877b1` back and `#1d344f` emblem to 80% and 35% of it). The name alternates like the GTK theme's, so open apps reload it. A theme may still ship `icons.theme` naming an installed icon theme to use instead.

## Networking ownership (D-68)

One owner per job. NetworkManager connects; systemd-resolved resolves; avahi alone answers `.local`; ufw owns incoming rules, of which karchy writes only its tagged LocalSend rule. karchy owns which networks are trusted and the upstream DNS. The VPN (part of karchy since D-156, `docs/vpn.md`) owns its tunnel, its DNS while the tunnel is up and its outgoing block, and reads trust from karchy.

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
- Readers today: `karchy-localsend-firewall` (LocalSend's port 53317, and while each is installed KDE Connect's 1714 to 1764, Jellyfin's 8096 and Plex's 32400, open on trusted devices only), `karchy-network-dns` and the VPN's policy (Auto stands by on a trusted network). After a trust change `karchy-trusted-networks set` asks the VPN to look again with `/usr/lib/karchy-vpn/control refresh`.

**DNS: karchy upstream, the VPN in its tunnel.**
- `karchy-network-dns` (in karchy, run as root by `95-karchy-dns` in karchy-settings and after every trust change) gives Wi-Fi and Ethernet connections that aren't trusted the DNS from `/etc/karchy/dns`: `provider=quad9|cloudflare|custom|network`, `servers=` (custom), `encrypted=yes`, `trusted=no` (yes: trusted networks too). Without the file: Quad9 over TLS, trusted networks on the router's DNS. `fallback=no` is "encrypted only". Only `karchy-network-dns set key=value…` writes the file: Settings › Network › DNS runs it as the user, it asks for a password through pkexec of its packaged path (`org.karchy.network-dns`), and root checks every value, replaces the file and decides every connection again at once.
- It changes only the applied connection: `nmcli device modify <dev> ipv4.dns dns+tls://9.9.9.9#dns.quad9.net,… ipv4.ignore-auto-dns yes ipv6.… connection.dns-over-tls yes`. NetworkManager keeps that through DHCP renewals and drops it when the connection goes down; resolved gets per-link servers and `+DNSOverTLS`. `resolvectl` per-link changes were not used: NetworkManager rewrites them on every renewal. Global DNS was not used: it would override the VPN's.
- It waits for NetworkManager's first connectivity verdict on the device (its check uses the network's DNS, so a captive portal is still detected), hands the network its DNS back while a portal waits for sign-in, and, if the encrypted servers don't answer a test query, keeps the network's DNS until the connection next comes up and logs it (`journalctl -t karchy-network-dns`). `karchy-network-dns status` shows the state per device.
- While a VPN tunnel is up, its profile's negative `dns-priority` with `~.` makes its DNS the only one used; karchy's servers stay on the link underneath and return when the tunnel goes down. The VPN sets DNS only on its tunnel and never edits saved networks.

**The VPN.** Part of karchy since D-156 (an add-on before, D-106): `karchy-settings` installs its system half from `system/vpn` at the add-on's old paths, `karchy` its command (`bin/karchy-vpn`); `docs/vpn.md` describes it. Nothing of it runs until it is set up with a WireGuard profile. It takes trust from `karchy-trusted-networks` and the DNS for untrusted networks from `karchy-network-dns`. Root code in `/usr/lib/karchy-vpn`, units in `/usr/lib/systemd/system`, the dispatcher in `/usr/lib/NetworkManager/dispatcher.d`; `karchy-vpn setup` writes the config through a root helper. The contract:
- **Status, the VPN writes and karchy reads:** `/run/karchy-vpn/status`, JSON, replaced atomically on every change and only then: `mode` (`off|auto|on`), `state` (`off`, `standing-by`, `connecting`, `protecting`, `failed`, `paused`), `reason` (`mode`, `no-profile` (its profile is gone: nothing is blocked until it is set up again), `trusted`, `no-network`, `starting`, `no-handshake`, `activation-failed`, `tunnel-up`, `sign-in`), `network` (device, name, uuid, type, trusted, trust reason), `tunnel` (the profile's name and interface), `until` (a sign-in pause's deadline), `since`. The network panel watches it (FileView) through the adapter in `shell/plugins/panels/network/Model.js`.
- **Commands, karchy calls:** `karchy-vpn mode off|auto|on`, `karchy-vpn portal-pause`, `karchy-vpn reconnect`. pkexec of `/usr/lib/karchy-vpn/control`; its polkit rule allows exactly these for local, active members of wheel without a password. `karchy-network-captive-portal` runs `portal-pause` while the VPN is connecting, failed or paused: web traffic (TCP 80, 443) and the network's DNS on that link for at most five minutes with the tunnel down, ending by itself once NetworkManager reports full connectivity.
- **Trust:** the policy asks `karchy-trusted-networks status --json` (`.active[] | select(.device == upstream) | .trusted`) on dispatcher events; health checks reuse the answer for the same activation.
- **DNS:** the VPN sets DNS only on its tunnel (negative `dns-priority`, `~.`). On a trusted network in On mode the tunnel's live connection gets the default VPN priority (50) instead, so the router's own domains (`nas.lan`, the DHCP search domain) resolve through the router on the physical link and everything else through the VPN; the guard lets the local network through.
- **Firewall:** the kill switch is the VPN's own nftables table (`inet karchy_vpn_guard`, output only). While closed it allows DHCP, IPv6 ND, NTP, the WireGuard endpoint, karchy's DNS-over-TLS servers (TCP 853), a ping to the router (karchy reads the router's address for trust) and the tunnel's probe. It never writes ufw's chains; a broken home hairpin NAT is fixed with a stateless source rewrite in the same table (`TRUSTED_GATEWAY`).
- **Timers:** the policy runs on dispatcher events, commands and trust changes. WireGuard has no handshake event, so it sets one transient timer: 2 s while connecting, 60 s while protecting, 10 s after a failure (a fresh attempt each minute), and at a pause's deadline. Nothing runs in Off mode or while standing by.

**Airplane mode: the kernel owns the key.** `karchy-airplane on|off|toggle` blocks or unblocks every radio with rfkill (`/dev/rfkill` is the seat user's, no password) and shows the OSD; systemd-rfkill restores the blocks at boot. Turning it on is remembered in `$XDG_STATE_HOME/karchy/airplane`, and airplane mode is that choice while every radio is still blocked: NetworkManager's Wi-Fi switch blocks the Wi-Fi radio too, so "all blocked" alone would call Wi-Fi off plus Bluetooth off airplane mode. The airplane key (`XF86RFKill`) is toggled by the kernel's rfkill input handler (`CONFIG_RFKILL_INPUT`, set in Arch's and CachyOS's kernels), also at the login prompt and on a text console; Hyprland's binding runs `karchy-airplane key`, which records and shows the result and toggles itself only when `/proc/bus/input/handlers` has no rfkill handler. A program issuing `RFKILL_IOCTL_NOINPUT` (GNOME's settings daemon) would take the key from the kernel; karchy ships none. The network panel follows `rfkill event` and the remembered choice; nothing polls.

**Settings › Network** (D-66: the panel's "Network settings…" opens it at the connection under the cursor or in use, `karchy-settings network <name|uuid|device|dns|vpn|…>`). It reads `karchy-network-status --json` (every active connection with addresses, gateway, DNS in use from resolvectl and whether it is encrypted, link and MAC), `karchy-network-profile list` (saved Wi-Fi and Ethernet profiles), `karchy-trusted-networks status --json`, `karchy-network-dns status`, `karchy-network-vpn status`, `karchy-localsend-firewall status` (ufw on, its incoming policy from `/etc/default/ufw`, and where karchy opened LocalSend's port, recorded in `/run/karchy/localsend-open`) and `karchy-network-country status --json`, and follows `nmcli monitor`. Writes:
- Saved networks: `karchy-network-profile set|forget|join-hidden` through nmcli, which NetworkManager's polkit rule allows for local members of wheel without a password; values are checked first and a refusal is one sentence on stderr. Changes that apply on connecting (IP settings, private address) reconnect a network in use; metered changes the live connection with `nmcli device modify`, so karchy's DNS on it stays. A hidden network's password goes over stdin, never argv.
- Trust: `karchy-trusted-networks set` (above). DNS: `karchy-network-dns set` (above).
- Wi-Fi country: `karchy-network-country set XX|auto` writes or removes `/etc/karchy/wifi-country` through pkexec of its packaged path (`org.karchy.network-country`) and runs `/usr/lib/karchy/wifi-regdomain` (karchy-settings) at once; `auto` returns to the world domain first, then the timezone's country.
- Connectivity check: NetworkManager's `ConnectivityCheckEnabled` over D-Bus (allowed for the active session; NetworkManager keeps it across restarts).
- VPN: "Set up VPN" is `karchy-network-vpn setup <uuid> [dns]`: it sets what the VPN needs on the user's own WireGuard profile (a fixed listen port, the VPN's DNS for every name, no autoconnect; no password), refuses a profile the VPN can't use in plain words (more than one peer, not a full tunnel, no IPv4 endpoint, no DNS server: exit 3, and the page asks for one), writes the VPN's configuration from the profile and hands it to `karchy-vpn setup`, whose root helper checks it again (an administrator's password, `org.karchy.vpn.configure`; no rule waives it). Then `karchy-vpn mode` and, for "Local devices on trusted networks", `karchy-network-vpn home-lan`, which hands the configuration with `HOME_LAN` changed to `karchy-vpn setup` (its own root helper checks it; an administrator's password). Every VPN profile is a card: while a WireGuard tunnel is connected, its health (`pkexec /usr/lib/karchy/wireguard-status`, action `org.karchy.wireguard-status`: the active local session, no password; read every 10 seconds while the page shows it, as WireGuard sends no event for a handshake): the last handshake and whether the server still answers (`wireguardHealth` in the panel's `Model.js`: older than 180 s on a tunnel that carries everything or sends keepalives means it stopped), the server, the data received and sent. "Use for the VPN" on another WireGuard profile sets the VPN up with it; other kinds of VPN (OpenVPN and the like, which the VPN doesn't run) get a switch, `karchy-network-vpn switch`. Remove on every card is `karchy-network-vpn remove <uuid>`: `nmcli connection delete`, after `karchy-vpn mode off` when it is the VPN's profile. `karchy-network-vpn import` adds a WireGuard `.conf` chosen in the portal's file chooser (`karchy-file-choose`) with `nmcli connection import`, under a valid interface name and with autoconnect off.

**What the panel reports.** `karchy-network-status` describes the underlying link: the lowest-metric default route in the main table that isn't a tunnel (WireGuard, tun, IP-in-IP and GRE kinds, or no link layer), and separately a `vpn_*` block (name, interface, address, whether the internet goes through it). The panel keeps the Wi-Fi QR share and the real IP and gateway with a VPN up, shows the VPN as its own line with the tunnel's last handshake, server and data (read as root through `wireguard-status` every 5 seconds while the panel is open), and names the speed test "Home-5G via VPN" when the tunnel carries it. NetworkManager checks the internet on the physical link, outside the tunnel, and the kill switch stops that check, so NetworkManager reports Limited while the internet works through the VPN; the panel takes the VPN's own `protecting` (a fresh handshake and its DNS answering through the tunnel) as the internet working, through the VPN (`internetState` in `Model.js`): "VPN protecting" or "Connected through VPN" and the lock icon, never "No internet".

## Agent skills (D-115)

karchy ships [Agent Skills](https://agentskills.io) so an AI coding agent on the machine knows how karchy works: where its files are, which command owns a setting, and how much care a change needs. Each skill is a folder in `skills/` with a `SKILL.md` and, for topics only some tasks need, files in `references/`. A skill is installed by the package it describes, so an agent hears only about what is installed.

| Skill | Installed by | Covers |
| --- | --- | --- |
| `karchy` | `karchy` | Customizing and running the system; holds the change rules the other skills refer to |
| `karchy-troubleshoot` | `karchy` | Logs, core dumps, boot problems and rollback, hardware and network checks, bug reports |
| `karchy-vms` | `karchy`, linked only while QEMU is installed | `karchy vm` and `~/VMs` |
| `karchy-containers` | `karchy-containers` | Rootless Podman, the `docker` command and Compose |

Every package installs its skills into one folder, `/usr/share/karchy/agents/skills/<name>`. VMs are not a karchy package (Quick install adds QEMU itself, D-67), so `karchy-vms` ships in `karchy` with a `.requires` file naming `qemu-system-x86_64`; a skill with that file is linked only while each command in it is installed.

`karchy-agent-skills` sets up one shared skills folder and links karchy's skills into it (D-115, D-168). Its header is the reference; in short:

- `~/.agents/skills` is the one real skills folder, where every skill is managed, and is made if missing. Each karchy skill is a link there, `~/.agents/skills/<name>` → the packaged folder.
- An agent that doesn't read `~/.agents/skills` has its own skills folder made a link to it, so every agent sees the same skills, the user's and karchy's, and nothing is relinked when a skill is added. Claude Code's `~/.claude/skills` is linked ahead of time, even before Claude Code is installed. The others (`FOLDER_AGENTS`: Antigravity, Kiro) are linked once the agent's config folder exists, so no dot-folders appear for agents the user never installs.
- An agent that manages its own skills folder never has it redirected. Hermes copies its bundled skills, a manifest and hub state into `~/.hermes/skills` (and each profile's `skills`), and its sync would act on every skill in a shared folder, so karchy's skills are linked into those one by one (`EACH_AGENTS`). Codex keeps its built-in skills in `~/.codex/skills/.system` and reads `~/.agents/skills` itself, so nothing of Codex's is touched; the same goes for the other agents that read `~/.agents/skills`, which a link from their own folder would show every skill twice.
- A `FOLDER_AGENTS` skills folder that is already a real folder is brought in: everything in it moves into `~/.agents/skills` (hidden entries and what isn't a skill, such as Claude Code's `synced/` and `.trash/`, too), then it is removed and made the link. Only renames move things, so nothing is copied and deleted. karchy's own per-skill links from before D-168 are dropped; an entry already in `~/.agents/skills` (a link to the same place, or identical content) is removed from the folder; an entry whose name is karchy's link there replaces that link; and a name taken by something different keeps both, the folder's copy going to `~/.agents/skill-clashes/<agent>/<name>`, where no agent reads it. A folder on another filesystem than `~/.agents/skills` (or with an entry that is), or nested with it, is left as it is with karchy's skills linked into it one by one, and a line says why. A folder that is a link to somewhere else is left alone, and that is said once. Each step is a rename or a link made beside the original, so an interrupted run leaves every entry in one place or the other and the next run finishes; runs take a lock on `~/.agents/skills`.
- What was moved is recorded in `~/.local/state/karchy/agent-skills-moved`. `karchy agent skills keep <folder>` is the way back: the folder becomes a real folder again with what was brought in from it (an identical entry that was removed is copied back), is remembered as kept (`agent-skills-kept`), and gets karchy's skills one by one; `share <folder>` brings it in again.
- Bringing a folder in happens only where its output is read: `karchy update`, which shows each line and repeats what moved in its summary, Quick install's terminal path, and by hand. The session's unit, `karchy-feature-vms`, Quick install's window and the new account's setup run `karchy-agent-skills --no-move`, which leaves such a folder waiting, with karchy's skills linked into it, until the next update.
- It never replaces a skill of the same name that is the user's (a folder, or a link pointing elsewhere), never overwrites, and touches nothing of git's: in a repository, what moved shows as new files and the run says so. It removes only its own per-skill links, when the skill's package is gone, and a folder link only on `keep`.
- If `~/.agents` is the user's git repository, a marked `skills/karchy*` line goes into its `.gitignore` once, or into `.git/info/exclude` when there is no `.gitignore`. Nothing is committed, and a line the user takes out is not put back (`~/.local/state/karchy/agent-skills-ignored` records that it was done).
- karchy links no shared instructions file (`AGENTS.md`, `CLAUDE.md`) into any agent. Those are the user's.

It runs from these places, all of which do nothing when the links are in place: the user unit `karchy-agent-skills.service` at session start; `karchy-agent-skills.path`, which watches the skills folder, so installing or removing a feature package with Quick install or pacman adds or removes its link at once; the end of `karchy update`, also when there is nothing to update; Quick install, after it installs an app of the `ai` category, so an agent installed just now is set up before its first run; `karchy-feature-vms`, after adding or removing QEMU; and the installer's user setup. No migration is needed, per skill or for bringing folders in (D-168): every `karchy update`, including the one that installs this version (the update already running calls the new command after the packages), runs the command and shows its lines, which a migration's log would hide.

Where each agent looks, from its documentation or source on 2026-11-18:

| Agent | User-level skill folders | Reads `~/.agents/skills` | karchy does |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/skills` ([docs](https://code.claude.com/docs/en/skills)); its claude.ai skill sync writes `synced/` and `.trash/` there | no | folder link, always; a real folder is brought in |
| Antigravity | `~/.gemini/config/skills` ([docs](https://antigravity.google/docs/skills)) | no (only in a workspace) | folder link when `~/.gemini/config` exists; a real folder is brought in |
| Kiro CLI | `~/.kiro/skills` ([docs](https://kiro.dev/docs/skills/)) | not documented | folder link when `~/.kiro` exists; a real folder is brought in |
| Hermes | `~/.hermes/skills`, `~/.hermes/profiles/<name>/skills` ([docs](https://hermes-agent.nousresearch.com/docs/user-guide/features/skills)); it writes its bundled skills there | only through `skills.external_dirs` in its config | per-skill links when the folder's parent exists |
| Codex | `~/.agents/skills` ([docs](https://developers.openai.com/codex/skills)); built-ins in `~/.codex/skills/.system` | yes | nothing |
| Gemini CLI | `~/.gemini/skills`, `~/.agents/skills` ([docs](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md)) | yes | nothing |
| Pi | `~/.pi/agent/skills`, `~/.agents/skills` ([docs](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/docs/skills.md)) | yes | nothing |
| OpenCode | `~/.config/opencode/skills`, `~/.claude/skills`, `~/.agents/skills` ([docs](https://opencode.ai/docs/skills/)) | yes | nothing |
| GitHub Copilot CLI | `~/.copilot/skills`, `~/.agents/skills` ([docs](https://docs.github.com/en/copilot/concepts/agents/about-agent-skills)) | yes | nothing |
| Cursor, Amp, Goose, Crush, Qwen Code, Cline, Droid, Kilo Code | their own folder and `~/.agents/skills` | yes | nothing |

Of the coding agents in the Quick install catalog (Claude Code, Codex, Crush, Cursor, Gemini CLI, GitHub Copilot CLI, OpenCode), only Claude Code needs a link. To add an agent, put it in `FOLDER_AGENTS` (it writes nothing of its own into its skills folder) or `EACH_AGENTS` (it does) in `bin/karchy-agent-skills`, and add a row here. `tests/agent-skills.sh` runs the command in a made-up home; never run it against a real home to test it.

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

The **form** is a gum TUI in Omarchy's style (D-08). It starts by itself on the karchy ISO and runs the same from the stock Arch ISO. It asks for: keyboard, disk (with typed confirmation), disk encryption (D-130), what to do with each other internal disk (D-132), username, one password, name and email, hostname, timezone, release channel (D-61), Secure Boot when the firmware is in Setup Mode (default yes), and bees (on by default). `docs/installing.md` is the guide for a person; an answer file replaces the form (`karchy-install --config`).

**Disk and base (D-41).** archinstall is not used. archinstall 4.5 replaces `systemd`/`sd-encrypt` with udev/busybox `encrypt` unless the disk uses a hardware security key (`archinstall/lib/installer.py:125`), and its only swap option is zram. Both conflict with D-12 and D-10. karchy's own `install/disk.sh` + `install/base.sh` do:

1. `sgdisk`: 4 GiB ESP plus a LUKS partition.
2. `cryptsetup luksFormat --type luks2` (left out on an install without disk encryption, where btrfs goes straight on the partition).
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
2. greetd: auto-login for the user after the disk password and karchy's login screen after logging out; without disk encryption, the login screen at every boot. A login at that screen goes through the PAM service `karchy-login`, which opens the keyring with the login password or leaves it to its key (D-130, D-131, D-142). mDNS in `nsswitch.conf`, ufw enabled.
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
