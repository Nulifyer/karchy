# karchy iconography audit and proposal

Audit of `/home/nulifyer/Projects/karchy` at `b4f1d5a` plus the uncommitted working tree, 2026-11-14. No repo files were edited.

Evidence files in the same scratchpad folder:

- `glyphs.tsv`: every private-use glyph in the repo (289 occurrences, 66 files), with file, line, codepoint, Nerd Font family and name, and context. Produced by `scripts/scan.py`, which reads literal characters, `\uXXXX`, `\u{…}`, `\U000…`, surrogate pairs and `\x` UTF-8 escapes.
- `match.md`: each theme's accent compared with its GTK icon theme and with the nearest Yaru and Papirus folder colors (`scripts/match.py`, CIE76 ΔE).
- `table.md`: the concept-to-glyph table, with codepoints resolved from Nerd Fonts 3.5.1 `glyphnames.json` (`scripts/table.py`).
- `crop-bar-left.png`, `crop-bar-right.png`: the two ends of the bar from the existing `minbar.png`, enlarged.

## 1. Key findings

1. **Material Design (MD) already accounts for 74% of the glyphs** (214 of 289). The rest come from six other families: Font Awesome 43, Codicons 10, Devicons 9, Seti 7, custom 3, Font Logos 2 and Weather 1. Moving to a single family is mostly cleanup of about 75 occurrences.
2. **Audio is the only Font Awesome glyph in the main bar row.** It sits beside MD Wi-Fi, microphone and monitor glyphs and is visibly heavier (`crop-bar-right.png`). The cause is `shell/plugins/panels/audio/Panel.qml:478-485`, and the OSD uses the same set (`shell/plugins/osd/OsdModel.js:7-14,31-34`). The comment at `Panel.qml:476-477` gives the reason: MD speakers looked smaller. `OpticalGlyph`/`BarIconButton` now size glyphs by their ink, so that reason no longer holds in the bar.
3. **Bug: the Omarchy icon font cannot render anywhere.** Nerd Fonts 3.5.1 Devicons occupy U+E700–E958, and all 32 Omarchy glyphs (U+E900–E91F) fall inside that range. The single karchy use is `bin/karchy-network-captive-portal:30,32,113` (U+E90F, meant as Tailscale). It renders as `dev-firebird` because `shell/plugins/notifications/Toast.qml:333` requests font family `"karchy"`, while the font's real family is `omarchy` (checked in its name table). This is most likely a `tools/rebrand` casualty: line 37 protects the path `fonts/omarchy` but not the bare family string. The comment at `shell/plugins/notifications/Delivery.js:53-56` also names a nonexistent `default/fonts/karchy`.
4. **GTK icon themes do not match the accents.**
   - Two themes name icon themes that do not exist: `themes/vantablack/icons.theme` = `Yaru-gray` and `themes/white/icons.theme` = `Yaru-grey`. yaru-icon-theme 26.10.3 ships no gray variant.
   - `themes/starship` has no `icons.theme`, so it falls back to Yaru-blue against an orange accent (`bin/karchy-theme-set-gnome:49`).
   - Ten themes are more than 40 ΔE from their accent (for example hackerman green → Yaru-blue, tokyo-night blue → Yaru-magenta, matte-black orange → Yaru-red).
   - Yaru ships only PNGs, so its folders cannot be recolored to an exact accent.
5. **Dimmed icons and text get darker on light themes, so they stand out more instead of receding.** There are about 55 `Qt.darker(foreground, …)` calls, and on the 5 light themes (catppuccin-latte, flexoki-light, lupine, rose-pine, white) they increase contrast instead of reducing it. Icon cases: `shell/Ui/Dropdown.qml:134`, `shell/Ui/MultiSelect.qml:322`, `shell/Ui/SearchableDropdown.qml:156`, `shell/plugins/panels/network/Panel.qml:1290,1764`, `shell/plugins/panels/bluetooth/Panel.qml:932`, `shell/plugins/services/media/BarWidget.qml:40`.
6. **The same concept appears in 2–3 families.** Lock, power, keyboard, info, update, chevrons, check and font are the examples (§3.1).

## 2. Inventory

### 2.1 Nerd Font glyphs, by area and family

| Area | md | fa | cod | dev | seti | custom | linux | weather |
|---|---|---|---|---|---|---|---|---|
| Bar (`shell/plugins/bar/**`, menu and media bar widgets) | 23 | 7 | | | | | 1 | |
| Panels + OSD (`shell/plugins/panels/**`, `osd/**`) | 88 | 16 | | | | | | |
| Menu (`default/karchy/karchy-menu.jsonc`, `shell/plugins/menu/**`) | 34 | 11 | 10 | | 5 | | 1 | 1 |
| Settings (`shell/plugins/settings/Settings.qml`) | 7 | | | | | | | |
| Notifications, lock, polkit, clipboard (QML) | 8 | 1 | | | | | | |
| Shared UI (`shell/Ui`) and `shell/services` | 6 | | | | | | | |
| `bin/` (mostly `karchy-notification-send -g`) | 47 | 8 | | 9 | 2 | 3 | | |
| i18n (`default/i18n/en/menu.json:1134`) | 1 | | | | | | | |

- **Sources.** QML/JS carries 157 occurrences, of which about 15 are escapes (`""`, `"\u{f012c}"`, `"󰐋"`). The menu JSONC carries 57 literals, and `bin/` 69. `karchy-menu-plugin:10` uses `$'\U000f0431'`.
- **Plugin manifests and `features.json`.** Neither has an icon field. `default/karchy/features.json` (one entry, printing) is shown as text only in Settings.
- **Font coverage.** All 154 distinct codepoints exist in Nerd Fonts 3.5.1. I checked against the installed CaskaydiaMono NF 3.5.1 cmap, which comes from the same patcher as `ttf-jetbrains-mono-nerd` 3.5.1 in `[extra]`. JetBrainsMono NF is not installed on the host, so it was not checked directly. No glyph uses the pre-3.0 MD range (U+F500), which was removed.
- **Font setup.** The shell asks for `monospace` (`shell/Commons/Style.qml:271`). `system/fontconfig/50-karchy.conf:13` maps that to JetBrainsMono Nerd Font, and `karchy-font-set` can put any font in front of it.

### 2.2 Omarchy icon font (`ttf-omarchy-icons`)

- **Contents.** `default/fonts/omarchy/omarchy.ttf` has 32 glyphs at U+E900–E91F: the Omarchy logo plus AI-agent, Tailscale and Cursor marks. The family is `omarchy`.
- **Packaging.** It is packaged in `packaging/pkgbuilds/ttf-omarchy-icons` and listed as a dependency in `packaging/pkgbuilds/karchy/PKGBUILD:24` and `karchy-desktop/PKGBUILD:13`.
- **Consumers.** There are only two. Neither works.
  - `Toast.qml:333`: wrong family, as above.
  - The menu's per-entry `iconFont` (`shell/plugins/menu/Menu.qml:1521`, `MenuModel.js:28`): no menu entry sets it.
- **Logo.** The karchy logo in the bar is the Nerd Font Arch logo (`shell/plugins/menu/BarWidget.qml:15-16`, D-47). Nothing uses U+E900.

### 2.3 GTK and freedesktop icon themes

- **Packages.** `karchy-desktop` depends on `yaru-icon-theme`, which comes from `[omarchy]` (version 26.10.3, 66 MB; on Arch it is AUR only), plus `adwaita-icon-theme` through its dependencies.
- **Shipped variants.** blue, magenta, olive, prussiangreen, purple, red, sage, wartybrown, yellow, each with a `-dark` form, plus plain `Yaru` (orange). There is no bark, viridian or gray.
- **How it is applied.** `bin/karchy-theme-set-gnome:45-50` runs `gsettings icon-theme` with the contents of `icons.theme`. Every dark theme uses the non-`-dark` variant except solitude.

| Theme | mode | accent | icons.theme | ΔE now | nearest shipped Yaru (ΔE) | nearest Papirus folder (ΔE) |
|---|---|---|---|---|---|---|
| catppuccin | dark | #89b4fa | Yaru-purple | 44 | blue (37) | blue (14) |
| catppuccin-latte | light | #1e66f5 | Yaru-blue | 20 | blue (20) | violet (28) |
| ethereal | dark | #7d82d9 | Yaru-blue | 22 | blue (22) | indigo (10) |
| everforest | dark | #7fbbb3 | Yaru-sage | 26 | prussiangreen (23) | darkcyan (15) |
| flexoki-light | light | #205EA6 | Yaru-blue | 25 | blue (25) | indigo (14) |
| gruvbox | dark | #7daea3 | Yaru-olive | 59 | prussiangreen (20) | darkcyan (17) |
| hackerman | dark | #82FB9C | Yaru-blue | 129 | olive (47) | green (34) |
| jade-horse | dark | #8bcbb1 | Yaru-sage | 31 | prussiangreen (30) | teal (23) |
| kanagawa | dark | #dcd7ba | Yaru-blue | 90 | wartybrown (28) | palebrown (11) |
| last-horizon | dark | #b59790 | Yaru-purple | 72 | wartybrown (19) | grey (14) |
| lumon | dark | #8bc9eb | Yaru-blue | 58 | prussiangreen (36) | breeze (13) |
| lupine | light | #3264eb | Yaru-purple | 16 | purple (16) | violet (24) |
| matte-black | dark | #e68e0d | Yaru-red | 62 | yellow (12) | orange (12) |
| miasma | dark | #78824b | Yaru-wartybrown | 23 | sage (22) | brown (23) |
| nord | dark | #81a1c1 | Yaru-blue | 52 | prussiangreen (30) | nordic (0) |
| nulifyer | dark | #d8a657 | Yaru-yellow | 23 | yellow (23) | paleorange (18) |
| retro-82 | dark | #faa968 | Yaru-wartybrown | 28 | yellow (27) | orange (16) |
| ristretto | dark | #f38d70 | Yaru-yellow | 41 | wartybrown (30) | deeporange (24) |
| rose-pine | light | #56949f | Yaru-blue | 63 | prussiangreen (13) | darkcyan (12) |
| solitude | dark | #798186 | Yaru-sage-dark | 15 | sage (15) | grey (7) |
| starship | dark | #ff9f0a | *(none → Yaru-blue)* | 144 | yellow (19) | orange (19) |
| tokyo-night | dark | #7aa2f7 | Yaru-magenta | 50 | blue (27) | blue (9) |
| vantablack | dark | #8d8d8d | Yaru-gray **(missing)** | n/a | sage (17) | grey (0) |
| white | light | #6e6e6e | Yaru-grey **(missing)** | n/a | sage (14) | grey (13) |

Yaru colors come from `ubuntu/yaru` `common/accent-colors.scss.in`. Papirus colors come from each `48x48/places/folder-<color>.svg` main tone.

### 2.4 App icons, cursor and images

- **App icons are full-color images and should stay that way.** They come through `Quickshell.iconPath`, which follows the GTK icon theme through the gtk3 platform theme:
  - menu app rows (`shell/services/AppLibrary.qml:59-68`, `Menu.qml:1531`)
  - notification app icons (`Toast.qml:273-295`)
  - tray (`Tray.qml:830-857`; symbolic tray icons are recolored to the bar foreground, which is good)
- **Shipped desktop entries.** `system/applications/karchy-foot*.desktop` (`Icon=foot`) and `default/alacritty/Alacritty.desktop`.
- **Web apps.** `bin/karchy-webapp-install` downloads site icons into `~/.local/share/icons/hicolor/256x256/apps`. These are brand-colored, which is correct.
- **Cursor.** No theme is set. `default/hypr/startup-cursor.lua:6-17` falls back to `default` (Adwaita cursors), and `default/hypr/cursors/karchy-startup` is the blank startup cursor. This is neutral and fine; no change proposed.
- **Images.** `docs/logo.svg`, `docs/screenshot.png`, `default/fonts/omarchy/hermes.svg` and the theme backgrounds and previews. No SVG icon assets are used by the shell.

### 2.5 Shared helpers

- **Color.** `shell/Commons/Color.qml` has the roles foreground, background, accent, urgent (from `red`) and muted, plus per-surface text and border roles. There is no warning or success role, although all 24 `colors.toml` files define `yellow` and `green`.
- **Size tokens.** `Style.font.iconSmall/icon/iconLarge` and `Style.bar.iconSlot/iconCanvas/iconFont/iconSize` exist (`shell/Commons/Style.qml:338-356`). The glyph tokens are rarely used: of the glyph `Text`s with an explicit size, only one uses an icon token (§3.4).
- **Rendering.** `shell/Ui/OpticalGlyph.qml` (ink-bounds sizing) and `BarIconButton.qml` handle bar glyphs well.
- **Gap.** There is no icon map, icon singleton or bash helper.

## 3. Inconsistencies (file:line)

### 3.1 One concept, several families

| Concept | Where and what |
|---|---|
| Volume | FA: `panels/audio/Panel.qml:478-485`, `osd/OsdModel.js:7,11-14,31-34`, `osd/Osd.qml:14`. MD: `panels/audio/Panel.qml:1286` (stream rows). Mixed in the same panel |
| Lock | FA: `karchy-menu.jsonc:18`, `polkit/PolkitAgent.qml:300`. MD: `bin/karchy-system-sleep-lock:101`, `panels/network/Panel.qml:1763` |
| Power | FA power_off: `karchy-menu.jsonc:15` (System). MD power: `karchy-menu.jsonc:23`, `OsdModel.js:22` |
| Settings / config gear | Seti config: `karchy-menu.jsonc:12,56`. MD cog: `karchy-menu.jsonc:11`. Setup and Settings show two different gears |
| Update / refresh | FA arrows_rotate: `karchy-menu.jsonc:13`. MD update: `bar/indicators/Updates.qml:16`, `bin/karchy-update-check:61`. MD refresh: `Ui/MultiSelect.qml:469` |
| Info / about | Cod info (thin outline): `karchy-menu.jsonc:14`. MD information (filled): `settings/Settings.qml:32`. In `m1.png` the About glyph is visibly lighter than its neighbors |
| Key / security | Cod key: `karchy-menu.jsonc:47,49,54,71-73`. MD key: `notifications/Toast.qml:132`. MD security: `bin/karchy-file-action:25`, `bin/karchy-secureboot:42,50` |
| Keyboard / mouse | FA: `karchy-menu.jsonc:59-60`. MD keyboard: `OsdModel.js:17`, `Settings.qml:27` |
| Chevrons | FA: `bar/widgets/Tray.qml:295,385`. MD: `panels/clock/Panel.qml:768,779`, `Ui/Dropdown.qml:133` |
| Check | FA: `Tray.qml:746`. MD: `panels/monitor/Panel.qml:922`, `network/Panel.qml:1942`, `notifications/DeedButton.qml:29` |
| Pin / eye | FA thumbtack and eye: `Tray.qml:539,554`. MD eye_off: `menu/Menu.qml:1678` |
| Font | Seti font: `karchy-menu.jsonc:35`, `menu/Menu.qml:326`, `bin/karchy-font-set:82,86` |
| Image / background | FA image: `karchy-menu.jsonc:34` |
| Arch logo | Font Logos archlinux: `menu/BarWidget.qml:16`. MD arch, a different mark: `karchy-menu.jsonc:26-28` |
| Time / timezone | Weather time_2: `karchy-menu.jsonc:75`. Cod globe: `:74`. MD calendar in the clock panel |
| Audio (menu) | Seti audio: `karchy-menu.jsonc:67`, while the audio panel uses MD speaker |
| Language / kernel | FA language and linux: `Menu.qml:346,355`, `bin/karchy-language:116` |
| Web apps | FA chrome: `karchy-menu.jsonc:29-30`, `bin/karchy-webapp-remove:59` (suggests Chrome; web apps are the generic concept) |
| Process / firmware | Cod server_process and desktop_download: `karchy-menu.jsonc:63,76` |
| Editors / terminals | `bin/karchy-default-editor:28-35` mixes dev, fa and custom, and uses fa-file_lines as a placeholder for Cursor, Zed and Helix. `bin/karchy-default-terminal:22-26` uses dev-terminal |
| Battery arrows | FA: `bin/karchy-battery-status:213,215` |

### 3.2 Wrong meaning

| Location | Problem |
|---|---|
| `menu/Menu.qml:332` | The power-profile provider shows `md-play_box_outline` (U+F040B, written as a surrogate escape), a play button |
| `bar/indicators/Minimized.qml:15-16`, `bin/karchy-hyprland-window-restore:45,51` | Minimized windows use `md-window_maximize`; `md-window_minimize` exists |
| `karchy-menu.jsonc:64` | "Shell" restart uses `md-menu` (a hamburger) |
| `karchy-menu.jsonc:44` | "Add Plugin" uses `md-web` |
| `panels/power/Model.js:44` vs `panels/network/Panel.qml:1209` | The performance profile and the speed test both use `md-speedometer` |
| `bin/karchy-battery-low:16` | Low battery uses `md-lightning_bolt`, which reads as "charging" |
| `settings/Settings.qml:28` | Network uses `md-ethernet` even on Wi-Fi-only machines |
| `notifications/Service.qml:1380` | The "Silenced" notice uses `md-bell`; `md-bell_off` exists |
| `bin/karchy-network-captive-portal:30,32,113` | Tailscale glyph renders as Firebird (§1.3) |

### 3.3 Missing icons

- `karchy-menu.jsonc:52` (`setup.security.remove`) and `:65` (`update.process.hyprland`) have `"icon":""`, while every sibling has one. The same Hyprland item under Setup has `linux-hyprland` (`:58`).
- About 15 `karchy-notification-send` calls pass no `-g`, while their peers do:
  - `bin/karchy-capture-screenrecording:89,100,238,427,454`
  - `bin/karchy-launch-config-editor:14`
  - `bin/karchy-menu-timezone:12`
  - `bin/karchy-menu-plugin:39`
  - `bin/karchy-theme-remove:38`
  - `bin/karchy-system:70`
  - `bin/karchy-theme-set:69,202`
  - `bin/karchy-theme-bg-next:20`
  - `bin/karchy-update:269`
  - `default/hypr/helpers.lua:271`
- `features.json` entries and the Settings feature rows have no icon.
- A glyph is embedded in a translation string: `default/i18n/en/menu.json:1134` `"Xbox Controllers (󰂯)"`.

### 3.4 Sizes

Of the glyph `Text`s with an explicit size, only `PolkitAgent.qml:300` uses an icon token (`iconLarge`). The others use text tokens or fixed numbers:

| Token or value | Locations |
|---|---|
| `bodySmall` | `Tray.qml:539,554,746` |
| `body` | `Dropdown.qml:133`, `MultiSelect.qml:321,469`, `SearchableDropdown.qml:155`, `media/BarWidget.qml:275` |
| `subtitle` | `network/Panel.qml:1195,1209,1763`, `monitor/Panel.qml:922` |
| `title` | `audio/Panel.qml:1286`, `monitor/Panel.qml:898` |
| `heading` | `bluetooth/Panel.qml:982` |
| `display` | `monitor/Panel.qml:547` |
| `displayLarge` | `clipboard/Clipboard.qml:592`, `Menu.qml:1678`, `media/BarWidget.qml:148` |
| `fieldFontSize * 1.1` | `lock/LockView.qml:237` |
| fixed `48` | `panels/clock/Panel.qml:323`, which also ignores `[spacing] scale` |

Outside the bar these glyphs are laid out by advance width, not ink, so MD and FA glyphs of the same pixel size look different sizes. The note at `audio/Panel.qml:476-477` is a symptom of this.

### 3.5 Filled vs outline, and rendering

- **Filled vs outline.** The bar mixes filled glyphs (ethernet in a box, solid FA speaker, filled mic) with an outline monitor. The menu mixes a thin Codicon outline (About) with filled MD and FA glyphs. MD itself is mixed in a few places: `md-palette_outline` (`karchy-menu.jsonc:33`) sits next to `md-palette` (`:10`), and `md-clipboard_outline` appears at `Clipboard.qml:592`.
- **Color fringing.** In `minbar.png`, the Arch logo and the monitor glyph show colored fringes; the other bar glyphs don't. All of them go through `BarIconButton`, so I did not establish the cause. It is worth one look with `KARCHY_DEBUG_BAR_ICONS=1`.

### 3.6 Colors

- **Good.** Icons already take surface roles (`bar.text`, `menu.text`, `notifications.text`). Active widgets use `bar.urgent` (`Ui/WidgetButton.qml:13`), and indicators turn that off (`Ui/BarIndicator.qml:46`).
- **Hardcoded colors.** None on icons. The `"white"` in `panels/wifiqr/Panel.qml:282` and `Ui/SpeedTestOverlay.qml:74` is on a black scrim and is intentional. `#ff4455`/`#4488ff` are debug outlines only.
- **Light themes.** Dimming with `Qt.darker` gets the direction wrong on light themes (§1.5). Use `Color.muted` or an alpha blend.
- **Restricted network.** It is drawn in urgent red (`network/Panel.qml:1176,1681`). This is a warning, but there is no warning role to use.

## 4. Proposal

### 4.1 One family: Material Design Icons through Nerd Fonts (`nf-md-*`)

- **Coverage.** About 7,000 glyphs at U+F0001–F1AF0 cover every concept in the shell, including ladders: Wi-Fi 0–4, battery 10–100 plus charging, and volume low, medium and high.
- **Consistency.** One designer grid (24 px, 2 px stroke) and one filled-first style. Every glyph listed in §4.5 is present in Nerd Fonts 3.5.1.
- **Already the majority** (74%).
- **Rules:**
  - Use the filled base glyph by default.
  - Use `_outline` only where it carries meaning: an empty Wi-Fi signal, or an "inactive" twin when the active form is filled.
  - No FA, Codicons, Seti or Weather glyphs in shell chrome.
  - Brand marks (Arch, Hyprland, VS Code, Vim, Neovim, Emacs, Sublime) may come from Font Logos, Devicons or custom, but only under `brand.*` keys in the map.
- **Icon font.** Draw icons in **"Symbols Nerd Font Mono"** (`ttf-nerd-fonts-symbols-mono`, `[extra]`, 3.5.1, 2.5 MB), not in `monospace`. Icons then stay the same when the user runs `karchy-font-set` with another font. Add it to `karchy`'s depends and keep JetBrainsMono for text.

### 4.2 One source of truth

- **Map file.** `default/karchy/icons.json`. Keys are concept names; values give the codepoint and, optionally, a font:

  ```json
  {
    "audio.volume.high": {"cp": "f057e", "nf": "md-volume_high"},
    "net.wifi": {"ladder": ["f092f","f091f","f0922","f0925","f0928"]},
    "brand.arch": {"cp": "f303", "nf": "linux-archlinux"},
    "brand.tailscale": {"cp": "e90f", "font": "omarchy"}
  }
  ```

  `nf` is documentation and is checked by a test; `font` defaults to the icon family.
- **QML.** A `shell/Commons/Icons.qml` singleton reads the file with `FileView` (same pattern as `Color.qml`) and exposes:
  - `Icons.glyph(name)`
  - `Icons.family(name)`
  - `Icons.level(name, fraction)` for the volume, battery, battery-charging and Wi-Fi ladders

  `OpticalGlyph`, `BarIconButton`, `Button.iconText` and `PanelHero` take an `iconName` and set the text and font together. That removes the `karchyGlyph()` U+E9xx heuristic from `Delivery.js:57` and the family check in `Toast.qml:333`.
- **Bash.**
  - `bin/karchy-icon <name> [level]` prints the glyph.
  - The packaging build also generates `/usr/share/karchy/icons.sh` (a `declare -A KARCHY_ICON=(…)`), so hot paths can source it without starting `jq`.
  - `karchy-notification-send -g` accepts either a glyph or a map name: a value matching `^[a-z][a-z0-9.-]+$` is resolved. That lets the 74 call sites read `-g security.lock`.
- **Menu.**
  - Entries take `"iconName":"system.lock"`, resolved in `MenuModel.js`.
  - A literal `"icon"` still works for user menus.
  - The providers in `Menu.qml:323-360` use names.
- **Guard.** Add a `tests/` check that fails on private-use characters outside `icons.json`, with an allowlist for `bin/karchy-notification-send:5` (an example in its docs).

### 4.3 Color rules

1. An icon takes its surface's text role.
2. Hover, cursor and selected states use the existing `Style` state tokens. The menu's `selectedText` is already the accent.
3. Inactive or disabled icons use `Color.muted` or `Util.alpha(fg, 0.55)`, never `Qt.darker`. Replace the roughly 55 `Qt.darker` calls listed in §1.5.
4. Add `Color.warning` (read from `yellow`) and `Color.success` (read from `green`). All 24 themes define both. Assign states as follows:

   | State | Role |
   |---|---|
   | Battery ≤10% | urgent |
   | Battery ≤20% | warning |
   | Restricted network or captive portal | warning |
   | Failed connection | urgent |
   | Updates available | accent |
   | Microphone in use, recording | urgent (privacy; keep as now) |

5. No hex colors on icons. App and brand images keep their own colors.

### 4.4 Size rules

| Context | Size |
|---|---|
| Bar | Unchanged (`Style.bar.iconSize` through `BarIconButton`) |
| Inline with body text (dropdown chevrons, row checks) | `Style.font.iconSmall` |
| List rows and panel row icons | `Style.font.icon` |
| Panel hero, dialogs (polkit, lock) | `Style.font.iconLarge` |
| Empty states (clipboard, menu "hidden") | `Style.font.displayLarge` |

Outside the bar, draw every glyph through `OpticalGlyph` with `paintedSize`, so MD glyphs are sized by their ink. Replace the fixed `48` at `clock/Panel.qml:323`.

### 4.5 Concept-to-glyph table

104 concepts. Ladders show their endpoints, and the same rows with full codepoints are in `table.md`.

| Concept | Proposed | Today |
|---|---|---|
| audio.volume.high / medium / low / muted | md-volume_high U+F057E / md-volume_medium U+F0580 / md-volume_low U+F057F / md-volume_mute U+F075F | fa-volume_* (bar, panel, OSD) |
| audio.headphones / speaker | md-headphones U+F02CB / md-speaker U+F04C3 | same; seti-audio in the menu |
| audio.mic / mic.muted | md-microphone U+F036C / md-microphone_off U+F036D | same |
| audio.camera | md-webcam U+F05A0 | md-camera |
| net.wifi.0…4 | md-wifi_strength_outline U+F092F … md-wifi_strength_4 U+F0928 | same |
| net.wifi.restricted / off / restart | md-wifi_strength_4_alert U+F0929 / md-wifi_strength_off_outline U+F092E / md-wifi_cog U+F16BE | same |
| net.ethernet / off | md-ethernet U+F0200 / md-ethernet_cable_off U+F0202 | same |
| net.network (category) | md-lan U+F0317 | md-ethernet (Settings) |
| net.vpn | md-vpn U+F0582 | U+E90F (renders dev-firebird) |
| net.qr / speedtest | md-qrcode U+F0432 / md-speedometer U+F04C5 | same |
| bt.on / off / connected | md-bluetooth U+F00AF / md-bluetooth_off U+F00B2 / md-bluetooth_connect U+F00B1 | same |
| power.battery.10…100 | md-battery_10 U+F007A … md-battery U+F0079 | same |
| power.battery.charging.10…100 | md-battery_charging_10 U+F089C … md-battery_charging_100 U+F0085 | same |
| power.battery.low | md-battery_alert U+F0083 | md-lightning_bolt |
| power.profile (menu) | md-gauge U+F029A | md-play_box_outline |
| power.profile.saver / balanced / performance | md-leaf U+F032A / md-gauge U+F029A / md-flash U+F0241 | leaf / gauge / speedometer |
| system.power | md-power U+F0425 | fa-power_off (menu System) |
| system.lock | md-lock U+F033E | fa-lock (menu, polkit) |
| system.suspend / hibernate | md-sleep U+F04B2 / md-snowflake U+F0717 | sleep / power_cycle |
| system.logout / reboot | md-logout U+F0343 / md-restart U+F0709 | same |
| menu.apps / packages / appearance / settings | md-apps U+F003B / md-package_variant U+F03D6 / md-palette U+F03D8 / md-cog U+F0493 | same |
| menu.setup | md-tools U+F1064 | seti-config |
| menu.update | md-refresh U+F0450 | fa-arrows_rotate |
| info / about | md-information U+F02FC | cod-info (menu) |
| pkg.updates-available | md-update U+F06B0 | same |
| pkg.install (pacman, AUR) | brand.arch, linux-archlinux U+F303 | md-arch (second Arch mark) |
| pkg.webapp / webapp.remove | md-web U+F059F / md-web_remove U+F0551 | fa-chrome |
| look.theme / background / font | md-palette_swatch U+F08B5 / md-image U+F02E9 / md-format_font U+F06D6 | palette_outline / fa-image / seti-font |
| look.layout (+ tiling, floating, scrolling) | md-dock_window U+F10AC (+ square_rounded, triangle, circle) | same; keep the shape language |
| plugin / add / remove | md-puzzle U+F0431 / md-puzzle_plus U+F14D0 / md-puzzle_remove U+F14D2 | puzzle / md-web / tab_remove |
| security | md-shield_lock U+F099D | cod-key |
| security.fingerprint / fido2 / ssh | md-fingerprint U+F0237 / md-usb_flash_drive U+F129E / md-ssh U+F08C0 | fp / cod-key / ssh |
| security.password / hash, secure boot | md-form_textbox_password U+F07F5 / md-shield_check U+F0565 | cod-key / md-security |
| config / config.git | md-file_cog U+F107B / md-git U+F02A2 | seti-config / fa-github |
| input.keyboard / mouse / trackpad | md-keyboard U+F030C / md-mouse U+F037D / md-trackpad U+F07F8 | fa-keyboard / fa-computer_mouse / same |
| restart.process / shell / hardware, firmware | md-application_cog U+F0675 / md-view_dashboard U+F056E / md-chip U+F061A | cod-server_process / md-menu / desktop_tower, cod |
| account.user | md-account U+F0004 | cod-key |
| disk / share / printer | md-harddisk U+F02CA / md-server_network U+F048D / md-printer U+F042A | same |
| time / timezone / calendar | md-clock U+F0954 / md-earth U+F01E7 / md-calendar U+F00ED | weather / cod-globe / same |
| language / kernel | md-translate U+F05CA / md-linux U+F033D | fa-language / fa-linux |
| display / multiple | md-monitor U+F0379 / md-monitor_multiple U+F037A | same |
| window.minimized / corners | md-window_minimize U+F05B0 / md-rounded_corner U+F0607 | window_maximize / same |
| notify.bell / silenced / code | md-bell U+F009A / md-bell_off U+F009B / md-key U+F0306 | bell for both / same |
| reminder / record | md-reminder U+F088C / md-record_circle U+F0EC2 | same |
| clipboard / copy | md-clipboard U+F0147 / md-content_copy U+F018F | clipboard_outline / same |
| media.music / play / pause / next / previous | md-music U+F075A / md-play U+F040A / md-pause U+F03E4 / md-skip_next U+F04AD / md-skip_previous U+F04AE | same |
| ui.chevron.down / left / right | md-chevron_down U+F0140 / md-chevron_left U+F0141 / md-chevron_right U+F0142 | fa-chevron (Tray) |
| ui.check / close / close.circle | md-check U+F012C / md-close U+F0156 / md-close_circle U+F0159 | fa-check (Tray) |
| ui.pin / show / hide | md-pin U+F0403 / md-eye U+F0208 / md-eye_off U+F0209 | fa-thumbtack / fa-eye |
| ui.refresh / loading / open-external | md-refresh U+F0450 / md-progress_clock U+F0996 / md-open_in_new U+F03CC | same |
| ui.arrow.up / down | md-arrow_up U+F005D / md-arrow_down U+F0045 | fa-arrow_* |
| app.launch / browser / editor / terminal | md-rocket_launch U+F14DE / md-web U+F059F / md-text_box_edit U+F1A7C / md-console U+F018D | same / same / fa-file_lines / dev-terminal |
| features (optional) | md-package_variant_plus U+F19D8 | md-file_cabinet |
| brand.* (keep) | linux-archlinux, linux-hyprland, dev-vscode or md-microsoft_visual_studio_code, custom-vim, custom-neovim, custom-emacs, dev-sublime, md-firefox, md-google_chrome, md-microsoft_edge | as now, routed through the map |

### 4.6 GTK icon theme strategy

| Option | Repo | Accent match across the 24 themes | Fit with MD glyphs | Cost |
|---|---|---|---|---|
| Yaru per theme (now) | `[omarchy]` (AUR on plain Arch) | Poor: 10 themes ΔE>40, 2 missing themes, no grey; PNG only, so no exact recolor | Rounded Ubuntu style; symbolic icons are fine | 66 MB |
| Yaru, files fixed to the nearest variant | same | Fair: best ΔE 12–47; no neutral grey for vantablack, white or solitude | same | Edit 3+ `icons.theme` files |
| Adwaita | `[extra]`, already installed | None: folders are always blue; few app icons since the legacy split | Good symbolics | 0 |
| Tela-circle | `[extra]`, 12 separate color packages | Fair: 12 fixed colors | Circle app icons clash with flat chrome | One package per color |
| Colloid | AUR only | Good | Good | Not in the repos |
| **Papirus plus a generated accent overlay** | `[extra]` papirus-icon-theme 20260801 | **Exact (ΔE 0)** for every theme | Flat and filled, the closest to MD; symbolics recolor with GTK | 112 MB (+45 MB over Yaru); no root |

**Recommendation: Papirus with a per-theme generated folder overlay.** It needs no `papirus-folders` (AUR, root).

1. In `bin/karchy-theme-set-gnome`, choose the base `Papirus-Dark` or `Papirus-Light` from `mode`.
2. Write a tiny theme, `~/.local/share/icons/karchy-icons-{a,b}/index.theme`, with `Inherits=<base>,hicolor`.
3. For each size, take `/usr/share/icons/Papirus/<size>/places/folder-blue*.svg` and replace its two tones: `#5294e2` becomes the accent and `#4877b1` becomes a 15% darker accent. Save each file under its unsuffixed name (`folder.svg`, `folder-documents.svg`, …).
4. Alternate the a/b name exactly as the GTK theme already does (`karchy-theme-set-gnome:31-41`), so open Thunar and Qt (gtk3) apps reload live.
5. Keep `icons.theme` as an explicit override, used only when the named theme is installed.
6. Swap `yaru-icon-theme` for `papirus-icon-theme` in `karchy-desktop/PKGBUILD:24` and drop the 23 `icons.theme` files, or keep the files as overrides.

**Fallback if the 45 MB is unacceptable.** Keep Yaru and fix the data:

- set each `icons.theme` to the nearest-variant column in §2.3
- use `-dark` variants for dark themes
- add `themes/starship/icons.theme`
- fix vantablack and white (their gray variant doesn't exist; plain `Yaru-dark` is the least-bad neutral)

## 5. Migration list (by visibility)

**Bar**

1. `shell/plugins/panels/audio/Panel.qml:478-485` fa-volume_* → `audio.volume.*` through `Icons.level`. This also feeds `:510` (OSD), `:741` and `:824` (hero).
2. `shell/plugins/bar/widgets/Tray.qml:295,385` fa-chevron → `ui.chevron.*`; `:539` fa-thumbtack → `ui.pin`; `:554` fa-eye → `ui.show`; `:746` fa-check → `ui.check`.
3. `shell/plugins/bar/indicators/Minimized.qml:15-16` md-window_maximize → `window.minimized`.
4. `shell/plugins/menu/BarWidget.qml:16` → `brand.arch` (same glyph).
5. No visual change, map only:
   - `bar/widgets/Microphone.qml:58`
   - `bar/widgets/Workspaces.qml:139-141`
   - `bar/indicators/Updates.qml:16-17`, `Reminder.qml:13-14`, `ScreenRecording.qml:12-13`
   - `services/media/BarWidget.qml:17,148,203,213,224,275`
   - `panels/bluetooth/Panel.qml:61-63`
   - `panels/network/Model.js:18,62-64`
   - `panels/monitor/Panel.qml:482`
   - `panels/power/Model.js:42-45,70-76`

**OSD and panels**

6. `shell/plugins/osd/OsdModel.js:7,11-14,31-34` and `osd/Osd.qml:14` fa-volume → md. Map lines 15-29.
7. `panels/power/Model.js:44` → `power.profile.performance` (md-flash).
8. `panels/audio/Model.js:118-141` (md-camera → md-webcam); `audio/Panel.qml:479,489-490,1286`.
9. `panels/network/Panel.qml:1195,1209,1306,1763,1942`; `bluetooth/Panel.qml:982,1025`; `clock/Panel.qml:323` (also the fixed 48 px), `:768,779`; `monitor/Panel.qml:547,898,922`.
10. Dimmed icons: change `Qt.darker` to muted or alpha at `network/Panel.qml:1290,1764`, `bluetooth/Panel.qml:932`, `media/BarWidget.qml:40`, `Ui/Dropdown.qml:134`, `Ui/MultiSelect.qml:322`, `Ui/SearchableDropdown.qml:156`. Do the rest in a second pass.

**Menu** (`default/karchy/karchy-menu.jsonc`)

11. Lines 12 → menu.setup, 13 → menu.update, 14 → info, 15 → system.power, 18 → system.lock, 20 → system.hibernate, 26-28 → brand.arch, 29-30 → pkg.webapp(.remove), 33 → look.theme, 34 → look.background, 35 → look.font, 44/46 → plugin.add/remove, 47 → security, 49/54 → security.fido2, **52 (empty) → md-delete**, 56 → config, 57 → config.git, 59 → input.keyboard, 60 → input.mouse, 63 → restart.process, 64 → restart.shell, **65 (empty) → brand.hyprland**, 66 → hardware, 67 → audio.speaker, 71-73 → security.password / disk / account.user, 74 → timezone, 75 → time, 76 → firmware.
12. `shell/plugins/menu/Menu.qml:326` (seti-font), `:332` (play_box → power.profile), `:346` (fa-linux → kernel), `:355` (fa-language → language), `:1678`.

**Settings**

13. `shell/plugins/settings/Settings.qml:28` → `net.network`, `:31` → `features`; the others go through the map. Add icons to the `features.json` rows.

**Shared controls, lock, polkit, clipboard**

14. `shell/Ui/Dropdown.qml:133`, `MultiSelect.qml:321,469`, `SearchableDropdown.qml:155`; `lock/LockView.qml:237`; `polkit/PolkitAgent.qml:283` (surrogate fingerprint) and `:300` (fa-lock); `clipboard/Clipboard.qml:592`; `services/AppLibrary.qml:260`.

**Notifications**

15. `notifications/Toast.qml:333`: family `"karchy"` → `Icons.family(...)` (the bug fix). `Delivery.js:53-60`: drop `karchyGlyph`. `Service.qml:1380` → `notify.silenced`. `Toast.qml:132`; `DeedButton.qml:29`.
16. `bin/karchy-network-captive-portal:30,32,113` → `net.vpn`.
17. `bin/karchy-battery-low:16` → `power.battery.low`; `bin/karchy-battery-status:213,215` → `ui.arrow.*`.
18. `bin/karchy-font-set:82,86`, `karchy-language:116`, `karchy-webapp-remove:59`, `karchy-file-action:17,19,25`, `karchy-secureboot:42,50`, `karchy-hyprland-window-restore:45,51`.
19. `bin/karchy-default-editor:28-35`, `-terminal:22-26`, `-browser:23-29` → `brand.*` or `app.*`.
20. Map-only call sites:
    - `karchy-hyprland-monitor-internal*` (10 calls)
    - `karchy-reminder` (5)
    - `karchy-capture-screenrecording:615`
    - `karchy-hyprland-corners:41`
    - `karchy-hyprland-workspace-layout-*`
    - `karchy-launch-browser:23`, `karchy-launch-webapp:29`
    - `karchy-plugin-clone:161`, `karchy-menu-plugin:10`
    - `karchy-mount-keep`, `karchy-disk*`, `karchy-feature-printing`, `karchy-update-check:61`, `karchy-system-sleep-lock:101`
21. Add glyphs to the ~15 calls in §3.3. Move the glyph out of `default/i18n/en/menu.json:1134`.

The containers and VMs plugins now being built should use `iconName` from the start rather than migrate later.

## 6. Risks and what stays

- **Nerd Fonts version.** Every proposed glyph exists in 3.5.1, which is in `[extra]` (`ttf-jetbrains-mono-nerd`, `ttf-nerd-fonts-symbols-mono`) and `[omarchy]` (`ttf-jetbrains-mono-nerd-basic`). MD codepoints have been stable since 3.0. The real hazard is the Devicons range, which grew into U+E9xx in 3.3+ and will keep growing. Never place custom marks in U+E000–F8FF without an explicit font family.
- **`ttf-omarchy-icons`.** It is effectively unused. Choose one:
  - **(a)** Drop it from `karchy` and `karchy-desktop` (needs approval: D-52), and use `md-vpn` for Tailscale.
  - **(b)** Keep it as the brand set for future AI-agent marks. Then put `"font":"omarchy"` on the map entries, fix `Toast.qml:333`, and add `"omarchy"` as a family string to `tools/rebrand` PROTECT so the next rebrand doesn't break it again.

  I lean (a). The karchy logo is the Arch mark (D-47), and karchy dropped the AI and Tailscale features (`docs/components.md:58`).
- **Must stay as they are:**
  - the brand marks: Arch logo in the bar, Hyprland, editor and browser logos
  - full-color app, tray and web-app icons
  - the workspace shape glyphs (square, triangle, circle), which carry layout meaning
  - the urgent color for microphone-in-use and recording
  - the Adwaita cursor
- **Papirus overlay.** The 16, 22 and 24 px `places` icons may use different tone hexes than 48 px. Check every size's two tones before relying on two `sed` replacements. Light themes should use `Papirus-Light`.
- **Icon font.** Pinning icons to "Symbols Nerd Font Mono" changes advance widths slightly. The bar is immune (it sizes by ink); text rows that put a glyph inline need a glance.
- **Not verified live.** No VM interaction was allowed. Rendering claims come from existing screenshots (`minbar.png`, `m1.png`); everything else comes from code. The light-theme dimming inversion follows from how `Qt.darker` works, but there is no screenshot of it.
