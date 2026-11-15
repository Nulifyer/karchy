# karchy shell: design-system audit and proposal

Scope: `/home/nulifyer/Projects/karchy/shell` (Commons, Ui, plugins). Audit and proposal only; no repo files were edited. Icons are covered by the separate iconography audit and appear here only where they affect layout or states.

Method: the frontend-design audit procedure (inherit project decisions; separate established conventions from isolated drift; foundations before screen decisions; cite evidence). Evidence comes from reading the code, from grep counts over `*.qml`, from a contrast script run against all 24 `themes/*/colors.toml` (`scratchpad/da/contrast.py`, WCAG 2 formula, Qt's `darker()` reproduced as HSV value / factor), and from existing screenshots in the scratchpad (`about.png`, `cons/sheet-panels.png`, `cons/sheet-crops.png`, `cons/sheet-set.png`, `cons/s16-*.png`, `cons/pk.png`, `cons/key-ctrl-meta_l-v.png`, `sb/notif.png`, `m1.png`, `minbar.png`, `idle.png`, `upd1.png`, `apps/terminals-flexoki-light-live.png`). The VMs were not touched.

Severity scale: **blocker** (task can't be done or work is lost), **major** (mistakes or heavy friction likely), **minor** (slows or confuses), **polish**.

---

## 1. Strengths to preserve

These are established conventions. Keep them, and build the rest of the system on them.

| Strength | Evidence |
|---|---|
| Type sizes are almost fully tokenized | 176 `font.pixelSize` bindings use `Style.font.*`. The only pixel literals are `clock/Panel.qml:331` (48) and `:343` (52), plus a metrics fallback in `IconContentBounds.qml:112`. |
| Everything scales with text size | 401 `Style.space(N)` calls and about 200 `Style.spacing.*` reads. Only 4 unscaled literal dimensions exist in the whole tree (`PanelSeparator.qml:15`, `Tray.qml:497,516,517`) and one unscaled margin (`LockView.qml:253`). The 1.6 screenshots (`cons/s16-*.png`) show no clipping, and Settings › Displays restacks its label above the control. |
| Reduced motion is honored everywhere | Every animation duration goes through `Style.duration(ms)` (`Style.qml:365`), which returns 0 when Hyprland animations are off. The one exception is `Osd.qml:20`, and that value is a display time, not an animation. |
| Colors are centralized | Only 8 hex literals live outside `Color.qml`. Four are debug outlines (`BarIconButton.qml:97,107`, `OpticalGlyph.qml:68,77`), and one is the QR code's ink (`wifiqr/Panel.qml:303`), which is intentional. |
| One state vocabulary for controls | `Style.qml:36-201` defines normal / hover-cursor / selected / pressed / focus / selection, each with color, fill alpha, border alpha and border width, and themes can override them through `[controls]` in shell.toml. `Border.controlSpec()` applies it in Button, TextField, Dropdown, Toggle, CursorSurface and MultiSelect. |
| Mouse hover and keyboard cursor are one state | Panels (`KeyboardPanel` + `CursorSurface` + `hasCursor`) move the cursor on hover, so only one row is ever highlighted. |
| Panel anatomy is consistent | Audio, network, bluetooth, monitor and power all use the same hero (icon at `display` size; title at `title` bold; caps `caption` status with `letterSpacing: 1.2`), then a separator, a caps section header and rows, all 380 wide (`fittedContentWidth(Style.space(380))` in 5 panels; clock is 560). Screenshot: `cons/sheet-crops.png`. |
| Surface chrome follows Hyprland | Corner radius comes from `decoration:rounding`, edge distance from `gaps_out / 2`, and popup borders from the Hyprland active-border gradient (`shell.toml.tpl [hyprland]`). Window borders and shell cards therefore match (`about.png`: Settings window border = panel border). |

---

## 2. Foundations inventory

### 2.1 Typography (`Style.qml:271-341`)
- **Families:** `monospace` fontconfig alias (`Style.font.family`, 66 uses), `menuFamily` (`KARCHY_MENU_FONT` env, 4 uses). Outside the system: **"Liberation Sans" hard-coded 3× in `notifications/Toast.qml:399,492,510`**, so notifications are the only proportional-font surface (see `sb/notif.png`). Their action buttons (`DeedButton.qml:58-77`) use monospace, so one card mixes both families.
- **Sizes**, derived from base 12: caption 10, bodySmall 11, body 12, subtitle 13, title 14, heading 16, display 24, displayLarge 28; icons iconSmall 11, icon 14, iconLarge 18.
  - Use counts: body 61, bodySmall 39, **caption 38**, title 27, heading 19, display 8, displayLarge 7, subtitle 6, icon 3, iconLarge 7.
- **Weights:** bold only (48× `font.bold: true`). There are 4 stray weights: `Font.DemiBold` ×2, `Medium`, `Normal`.
- **Letter spacing:** 20 literal `letterSpacing` values (e.g. `1.2` in every hero), and none of them scale.

### 2.2 Spacing and sizes (`Style.qml:210-263`)
- **Scale:** hairline 1, xxs 2, xs 3, sm 4, md 6, lg 8, xl 10, xxl 12, xxxl 14, huge 18.
- **Semantic tokens:** controlGap 8, controlPaddingX 10, controlPaddingY 6, inputPaddingY 7, controlHeight 28, popupRowHeight 28, rowGap 8, rowPaddingX 12, labelGap 4, panelGap 14, panelPadding 18, popupPadding 14, dropdownWidth 240, searchableDropdownWidth 260, numberFieldWidth 120, searchablePopupMinHeight 220.
- **Not tokenized, but de-facto conventions:** panel width 380 (×5), wide panel 560, Settings sidebar 200 (`Settings.qml:93`), Settings label column 170 (`SettingsLabel.qml:9`), action button 22 (`PanelActionButton.qml:39`), OSD bottom offset 67 (`Osd.qml:142`).

### 2.3 Shape
- **Radius:** a single token, `Style.cornerRadius`, mirrored from Hyprland rounding (0 by default; 6 with the `corners-rounded` toggle or the solitude theme). It is used directly 33×, plus about 10× through local aliases.
  - Nested surfaces use the same radius as their container (`CursorSurface.qml:28`, `Button.qml:78`, `Dropdown.qml:88`, `KeyboardPanel.qml:517`). The one exception is `Menu.qml:1508`, which uses `min(cornerRadius, space(4))`.
  - **Hard square overrides:** `ConfirmDialog.qml:107` (`radius: 0`) and `Button.qml:159`.
  - Rounded square themes get forced rounding from `Math.max(2, cornerRadius)` (`Tray.qml:617,735`).
- **Border widths:**
  - Cards (popups, menu, polkit, notifications, OSD): `max(1, space(2))`.
  - Controls: `normalBorderWidth` (1).
  - Tooltips: `normalBorderWidth` in PanelToolTip, `max(1, normalBorderWidth)` in Button, and a literal `1` in `Bar.qml` (one role, three expressions).

### 2.4 Motion
- **Durations:** about 30 distinct values (35, 50, 55, 60, 70, 120, 140, 150, 160, 180, 200, 220, 240, 250, 320, 400, 420, 550, 560, 600, 650, 800, 840, 900, 950…).
- **Easing:** `Easing.OutCubic` 36×, the `Style.easeOut` bezier 6× (Button, KeyboardPanel, PopupCard, WidgetButton, notifications Service), plus InOutQuad, InOutSine and InOutCubic for the screensaver and toasts.
- **What's missing:** no named duration tokens.

### 2.5 Color (`Color.qml`, `default/themed/shell.toml.tpl`)
- **Palette roles:** foreground, background, accent, urgent (= the theme's `red`, or `color1`), muted (defined at `Color.qml:23`, read from colors.toml, and **used nowhere**).
- **Surface roles:**
  - `bar`: background, text, active
  - `popups`: background, text, border
  - `tooltip`, `notifications` (+countdown)
  - `menu`: +scrim, selected bg/text/border
  - `polkit`, `lock`, `imagePicker`
- **Dead tokens:** the template's `[launcher]` section has 12 keys and no reader in `Color.qml`.
- **State alphas:** normal fill 0.04, hover 0.08, selected 0.18, pressed 0.22, selection 0.35; borders normal 0.4, hover 0.25, selected 1.0 (width 0).
- **Missing roles:** success, warning, info, disabled, secondary text, placeholder, focus ring, on-scrim text. There is no light/dark awareness: `mode = "light"` in colors.toml is never read by the shell.

### 2.6 Opacity / "dim" (no token; four competing mechanisms)

| Mechanism | Count | Where | Light-theme behaviour |
|---|---|---|---|
| `Qt.darker(fg, 1.15–2.2)` | **53 in 15 files** | Omarchy-origin: PanelSectionHeader, PanelHero, Toggle, TextField placeholder, Dropdown, SearchableDropdown, MultiSelect, NumberField, ToggleSwitch off, PanelActionButton disabled, clock panel (10), monitor panel (4), Tray, media, notifications | **Inverted** (section 4.1) |
| `Util.alpha(fg, 0.7)` | 11 | karchy-added Settings sections | Correct direction |
| `opacity: 0.45–0.9` | ~20 | hero icons, workspaces, misc | Correct direction |
| `Color.muted` | 0 | — | — |

---

## 3. Drift measurements

### 3.1 Hard-coded values
- **Spacing:** 401 raw `Style.space(N)` calls versus about 200 token reads, across about 45 distinct N, many of them off the scale (3, 5, 7, 11, 22, 34, 58, 74, 88…). This drift scales correctly, so it's a consistency problem, not a scaling bug.
  - Worst files: audio/Panel 35, clock/Panel 30, network/Panel 28, Menu 26, Tray 25, monitor/Panel 23, Bar 21, media/BarWidget 19, Toast 17.
  - For contrast, the karchy-added Settings sections are mostly token-based (DisplaysSection reads 8 tokens and makes 0 raw calls).
- **Colors:** `Qt.rgba(1,1,1,…)` and `Qt.rgba(0,0,0,0.78)` on-scrim colors are duplicated between `SpeedTestOverlay.qml:75-101,225-227` and `wifiqr/Panel.qml:47-48,221` (the same `onScrimDim`/`onScrimUrgent "#ff6b6b"` pair defined twice).
- **Fonts:** Liberation Sans ×3 (Toast); clock literals 48/52.
- **Backgrounds bypassing surface tokens:**
  - `Osd.qml:143` uses `Util.alpha(Color.background, 0.97)` instead of `Color.popups.background`, so a theme's `[popups] background` doesn't reach the OSD.
  - `ConfirmDialog.qml:13-17` builds its own background, scrim and selection from palette roles instead of `menu.*`.
- **Fallback hex:** `PanelSlider.qml:14` (`"#333"`) and `:97` (`"#101315"`) are used when `bar` is null.

### 3.2 Local components that re-implement shared ones

| Shared owner | Re-implementations | Evidence |
|---|---|---|
| `Ui/PanelHero.qml` (exists, **0 uses**) | 5 inline heroes | audio `Panel.qml:820-890`, bluetooth `:696-765`, network `:1170-1300`, monitor `:545-590`, power `:340-380` |
| — (none) | InfoLabel / InfoValue key-value grid, twice | `power/Panel.qml:522-548`, `network/Panel.qml:1952-1990` |
| `Ui/Button.qml` | ConfirmDialog's own buttons (fixed 88×34, caption text, radius 0) | `ConfirmDialog.qml:95-130` |
| `Ui/PanelToolTip.qml` | Button's built-in tooltip; the bar's own tooltip window | `Button.qml:55-60`, `Bar.qml:1848+` |
| `Ui/PanelHero` / page header | Each Settings section repeats title + intro + error `Text` (7 copies) | e.g. `FeaturesSection.qml:60-77`, `DisplaysSection.qml:100-117`, `NetworkSection.qml:52-75` |
| card / row surface | FeaturesSection card (local bordered `Rectangle`, `:86-95`), DisplaysSection monitor card, the `Toggle` row card, `CursorSurface` | three card looks for "an item with a title, description and action" |
| `KeyboardPanel` vs `PopupCard` | two popup-chrome implementations with the same API subset | `KeyboardPanel.qml:22-24` says so itself |
| `Ui/MultiSelect`, `Ui/NumberField` | **unused** anywhere | grep shows 0 consumers |

### 3.3 One role, different treatments

| Role | Treatments found | Verdict |
|---|---|---|
| Section header | PanelSectionHeader (caps caption, `Qt.darker 1.4`) in panels and Settings via `SettingsHeader` | **Consistent.** Keep. |
| Page or panel title | Panel hero (title 14 bold + caps status); Settings page title (heading 16 bold); window sidebar "Settings" (heading 16 bold) | Fine by context, but Settings shows two equal-weight 16px bold titles side by side (`about.png`). |
| Secondary text | `Qt.darker` (Omarchy) vs `alpha 0.7` (Settings) vs `opacity` | **Drift.** One is broken in light themes. |
| Keyboard cursor in a list | Panels: 8% fill + 0.25 border, foreground text. Menu/clipboard: 8% fill + **accent text**, border width 0 (`Menu.qml` `selectedBorderSpec` width 0). Settings nav: 18% "selected" fill. | Two looks for the same role. |
| Selected item | `CursorSurface` selected 18% fill (audio device row); ButtonGroup chip 18% fill + border (network DNS, Settings) | Consistent enough. |
| Switch | `ToggleSwitch` everywhere, labelled `Toggle` rows in Settings | **Consistent.** |
| Slider / level | PanelSlider fill = foreground (audio, monitor); OSD bar fill = **accent** (`Osd.qml:180`) | Same quantity (volume), two colors. |
| Primary button | **None exists.** Every Button is neutral; About's "Update karchy and the system…" looks like any other bordered button. | Gap. |
| Destructive action | ConfirmDialog (urgent border/fill); PanelActionButton `hoverColor: urgent` (forget, unpair); FeaturesSection "Remove" is a plain bordered Button identical to "Add" | Three treatments. |
| Empty state | Clipboard: icon + text, centered (`cons/key-ctrl-meta_l-v.png`); Bluetooth: plain caption text that repeats the hero ("NO ADAPTER" + "No Bluetooth adapter", `cons/sheet-crops.png`); Settings Network: dim text "No saved networks yet." | No shared component. None offers a next action. |
| Loading | `common.loading` string; ToggleSwitch `busy` has **no visual** (`ToggleSwitch.qml:32,113`); Button has no busy state | Gap. |
| Error | Settings: raw `stderr` in urgent color (`DisplaysSection.qml:89,110-116`); polkit/lock: urgent border + text; notifications: urgency 2 swaps the accent color only (`Toast.qml:76`) | No shared inline-error component. |
| Disabled | Only PanelActionButton dims (`Qt.darker 2.0`, which gets *darker* in light themes); Button and Dropdown show no disabled state | Gap. |
| Tooltip | 3 implementations with 3 border-width expressions | Drift. |
| Card chrome | popups/notifications/polkit/lock: accent (`active-border`) border; menu/clipboard/reminders/tooltip: **foreground** (`active-border-foreground`) border (`shell.toml.tpl`) | Deliberate in the template, but undocumented. Keep it and name it (summoned overlays vs attached cards). |

---

## 4. Findings across all surfaces

### 4.1 [major] Secondary text, placeholders and "off" states invert in light themes
`Qt.darker()` lowers HSV value. On a dark theme's light foreground that dims toward the background. On a light theme's dark foreground it makes text *darker*, so it gains contrast.

| Theme (mode) | Primary fg/bg | `darker 1.4` (section headers, hero status, descriptions) | `darker 1.6` (placeholders) | `alpha 0.7` (Settings) |
|---|---|---|---|---|
| catppuccin-latte (light) | 7.1 | **10.1** | **11.3** | 3.5 |
| rose-pine (light) | 6.7 | **9.8** | **11.0** | 3.3 |
| lupine (light) | 15.4 | **17.1** | **17.6** | 5.8 |
| flexoki-light (light) | 18.6 | 19.2 | 19.3 | 7.1 |
| white (light) | 21.0 | 21.0 | 21.0 | 8.5 |
| everforest (dark) | 7.4 | 3.8 | **3.0** | 4.5 |
| gruvbox (dark) | 8.2 | 4.2 | 3.4 | 4.8 |

- **In all 5 light themes**, section headers, hero status lines, Toggle descriptions, notification metadata (`Toast.qml:74-75`) and **TextField/Dropdown placeholders** (`TextField.qml:46`, `SearchableDropdown.qml:144`) render as dark as the primary text or darker.
  - Impact: a placeholder can't be told apart from a typed value, and the hierarchy goes flat or inverts.
  - Fix: one `textSecondary` / `textPlaceholder` role built from an alpha mix (as Settings already does) and adopted by those 53 sites.
- On the dark side, `darker 1.6` placeholders fall to 3.0–3.4:1 in everforest and gruvbox, and `alpha 0.7` falls to 3.3–3.5:1 in rose-pine and catppuccin-latte. The secondary role needs a floor of about 4.5:1 for anything people must read.
- Not visually checked: no screenshot exists of a panel, Settings, menu or polkit under a light theme. The table is computed, and the code paths are cited.

### 4.2 [major] Focus is indistinguishable from hover, and the cue itself is faint
- **Focus has no look of its own.** `shell.toml.tpl [controls]` copies hover-cursor into focus (fill 0.08, border 0.25). With the pointer resting on one control and Tab focus on another, two controls look identically "hot". The keyboard user can't tell which one Enter will act on.
- **The cue barely shows.** Hover/cursor fill composites to **1.12–1.24:1** against the background in every theme, and selected to 1.30–1.73:1 (contrast script). WCAG's 3:1 non-text guideline isn't met by either. The 0.25 hover border is *fainter* than the 0.4 normal border, which `ToggleSwitch.qml:18-24` already works around with a ring.
- **Panels are the exception, and they're fine** (hover and cursor are unified).

### 4.3 [major] Settings is only partly keyboard-operable
`Button` defaults to `focusable: false` (`Button.qml:66`), and nothing in `plugins/settings` sets it. As a result:
- The section nav (`Settings.qml:107-117`), "Update karchy and the system…", and Features Add/Remove can't be reached with Tab.
- `ToggleSwitch` has no `activeFocusOnTab`, so the monitor enable switch (`DisplaysSection.qml:207`) can't be reached either.
- There are no `Keys` handlers in `plugins/settings`; panels have hjkl and arrows.

What does work: Dropdown, SearchableDropdown, ButtonGroup and Toggle are tabbable. Not verified live: initial focus when the window opens.

### 4.4 [major] Confirm dialogs preselect the destructive choice
- `ConfirmDialog.qml:12` defaults `selectedIndex: 1`, which is the confirm button, styled destructive (`:96`).
- Clipboard sets it explicitly (`Clipboard.qml:95`).
- The callers are Delete clipboard history, Delete theme (image picker) and **Uninstall app** (menu). Enter twice is enough to uninstall a package.
- Correction: default to Cancel (index 0) for destructive confirms. Keep Enter-to-confirm for non-destructive ones.

### 4.5 [major] "urgent" isn't a stable meaning across themes
`urgent` is the theme's `red` (`Color.qml:163`).
- **Hue:** in lumon it's blue (#4d86b0), hackerman green (#50f872), lupine magenta (#c900c4), and solitude, vantablack and white grey.
- **Contrast against the background:** miasma 2.3, solitude 2.8, nord 3.1, kanagawa 3.2.

Error text, ConfirmDialog destructive styling, `bar.active` (recording, updates) and polkit/lock error borders all depend on it. Errors also carry text, so meaning isn't lost outright, but destructive buttons and the bar "active" mark rely on hue alone. There are no `success` or `warning` roles at all.

Proposal: add `[status] danger / warning / success` roles to the template with a contrast floor. Keep `urgent` as an alias.

### 4.6 [minor] Caption text is 10px
`caption` = 10px at base 12, used 38× for:
- section headers, hero status lines and Toggle descriptions (`Toggle.qml:36`)
- ConfirmDialog button labels (`ConfirmDialog.qml:117`)
- Feature descriptions

These are read, not decorative, and they're below the 12px floor. Uppercase plus letter-spacing helps the headers, but not the descriptions or button labels. Proposal: caption → 11 (bodySmall) for headers only, and move descriptions and button labels to bodySmall or body.

### 4.7 [minor] Missing component states
- Button has no `primary`, `destructive`, `disabled` or `busy` look.
- ToggleSwitch `busy` changes no visual.
- Dropdown has no disabled look.
- Features "Remove" looks the same as "Add" and starts a removal in a terminal.

### 4.8 [minor] Settings drifts from the shell conventions
- 0 `I18n.t` calls, against 150 in panels.
- Errors show raw `stderr`.
- Seven sections each hand-roll title + intro + error.
- Explanatory paragraphs sit at the top of every page (`cons/sheet-set.png`: Displays and Input). The skill's guidance is to move one-time explanations behind (i).
- Two 16px bold titles compete ("Settings" in the sidebar, the page title).

The Displays card plus label/control grid and the Input flat rows plus Toggle cards use different grouping for similar content.

### 4.9 [minor] Panel content takes `bar.foreground` on `popups.background`
114 references in panels (e.g. `network/Panel.qml` 32, `audio/Panel.qml` 28). Today the generated template keeps `bar.text == popups.text`, so nothing breaks yet. A theme that ships its own shell.toml with a light bar and dark popups would get unreadable panels. Content should use `popups.text`.

---

## 5. Per-surface findings

| Surface | Hierarchy / grouping / density | States, focus, light theme, scale | Severity |
|---|---|---|---|
| **Bar** (`Bar.qml`, widgets, indicators) | Clear left / center / right zones. Workspaces dim inactive numbers with opacity, which works in light themes (`apps/terminals-flexoki-light-live.png`). The karchy-added Minimized and Updates indicators (`minbar.png`) match the WidgetButton metrics. | Fades and drops input under real fullscreen (`Bar.qml:1803-1816`). The tooltip border is a literal `1` (`:1848+`). There's no floating mode (section 8). Light theme checked: bar OK. | polish |
| **Audio panel** | Hero toggle is unlabeled. It mutes everything (`audio/Panel.qml:836-848`) and only a tooltip says so. The slider track is inset from the content edge (x=68 vs 55 in `cons/sheet-crops.png`), so it doesn't line up with the header and rows. The input level meter under the input slider has no label. | Keyboard: full (KeyboardPanel). 1.6 checked (`cons/s16-audio.png`). | minor |
| **Network panel** | Good key-value grid with tabular alignment and equal-width DNS chips. InfoLabel/InfoValue are duplicated with power. The speedtest action icon sits top-right with no label (iconography audit). | Forget uses urgent hover. Light theme: InfoLabel uses `Qt.darker`, so it inverts (4.1). | minor |
| **Bluetooth panel** | No-adapter state: the hero icon slot renders empty while the title stays indented (x=497 vs 468 border), and the body repeats the status ("NO ADAPTER" / "No Bluetooth adapter"). It offers no next step. | Couldn't check paired/scanning states visually. | minor |
| **Monitor (Display) panel** | Stepped text-size slider (segments) correctly differs from continuous sliders. Scale chips duplicate Settings › Displays scale (same model, `monitor/Model.js:2`), which is the right kind of consistency. | — | polish |
| **Power panel** | Same hero. InfoPair grid. | Not visually checked (no battery in VM). | — |
| **Clock panel** | 560 wide, its own hero (48/52px literals), 10 `Qt.darker` uses, `Qt.rgba(...,0.12)` rules (`:474,533`) that should use PanelSeparator. | Not visually checked. | minor |
| **Speedtest / disk-speedtest / wifiqr** | Full-screen scrim overlays with hard-coded white-on-black (`SpeedTestOverlay.qml:75-101`, `wifiqr/Panel.qml:47-48,221,282`). Theme-independent by design, which is acceptable, but the tokens are duplicated. | Light theme: unaffected by design. | polish |
| **Menu / launcher** | Strong single column, selected row in accent text + fill, chevrons for submenus (`m1.png`). At 1.6 the list scrolls and the last row fades (`cons/s16-menu.png`). | The cursor look differs from panels (accent text, 4.2/3.3). The uninstall confirm defaults to Uninstall (4.4). | major (via 4.4) |
| **Settings** (FloatingWindow) | Sidebar + page, 900×640 capped at 85% of screen (`Settings.qml:76-79`). Uses `Color.background`, not a surface role. Window border from Hyprland. | 4.3, 4.8. At 1.6 the Displays rows stack correctly (`cons/s16-settings.png`). | major (via 4.3) |
| **Notifications** (`Toast.qml`) | Clear title / body / time. Actions are segmented text buttons ("Enroll keys" in `sb/notif.png`) that read as dim text, not controls. The proportional font is the only one in the shell. | Critical urgency changes only the accent color (`:76`). An error notification looks the same as an info one (`mc1.png`, "Screen recording couldn't start"). `Qt.darker` metadata inverts in light themes. Light theme: not visually checked for toasts. | minor |
| **OSD** | Compact icon + bar + value. The background bypasses the popups token (`Osd.qml:143`). The level fill is accent, while panel sliders are foreground. | Not visually checked. | polish |
| **Lock** (`LockView.qml`) | Single centered field (`idle.png`). Error replaces the placeholder in urgent color + text (`:213-215`). Fingerprint icon supported. | No Caps Lock indicator, and no user or keyboard-layout cue (grep: none). Placeholder uses `lock.placeholder` (a mix, fine in light themes). | minor |
| **Polkit** (`PolkitAgent.qml`) | Password card centered, justification in a separate bubble (`cons/pk.png`). The message shows the raw command line with a connection UUID: "Authorize running '/usr/bin/karchy-trusted-networks set 9370cec8-… true'". That's system language: the action should carry a polkit message ("Change trusted networks"). | Error flash: border + text. | minor |
| **Clipboard** | Search + list on `[menu]` chrome. The empty state is icon + text (`cons/key-ctrl-meta_l-v.png`), and the search field doesn't show the count. | Delete-history confirm preselects Delete (4.4). | major (via 4.4) |
| **Reminders** (`ReminderFlow.qml`) | `[menu]` chrome, token-based. | Not visually checked. | — |
| **Image picker** | Carousel without a card. Theme delete confirm preselects Delete (4.4). | Not visually checked. | major (via 4.4) |

**Couldn't check visually:** any shell surface under a light theme except the bar; focus rings in Settings; the panels' error, scanning and busy states; OSD, reminders, image picker, lock error and polkit error flash; scale 1.0 vs 1.6 for notifications and the OSD. Keyboard behavior is inferred from code only.

---

## 6. Proposed design system

Grounding rule: every value below already exists in the codebase. The proposal names, consolidates and fills gaps; it doesn't restyle.

### 6.1 Foundation tokens (owner: `Commons/Style.qml` and `Commons/Color.qml`)

**Type roles.** Map roles to the existing sizes and stop picking sizes per call site.

| Role | Size token | Weight | Use |
|---|---|---|---|
| `display` | display 24 | regular | hero icons, OSD value |
| `pageTitle` | heading 16 | bold | Settings / window page title; one per view |
| `title` | title 14 | bold | hero title, card title, notification summary |
| `body` | body 12 | regular | rows, controls, values |
| `secondary` | bodySmall 11 | regular | descriptions, metadata |
| `label` | caption → **11** | bold, caps, letterSpacing `space(1)` | section headers, hero status |

Keep monospace as the shell family. Move "Liberation Sans" into `Style.font.notificationFamily`, defaulting to the shell family unless a theme sets it. That keeps the Omarchy look reachable but makes it a deliberate token.

**Spacing.** Keep the scale and add the de-facto sizes as named tokens.
- `panelWidth 380`, `panelWidthWide 560`
- `sidebarWidth 200`, `formLabelWidth 170`
- `actionButtonSize 22`, `heroGap 14`

Then a lint rule: `Style.space(N)` only for N on the scale or inside a component owner.

**Radius.**
- `radius.surface = cornerRadius` (cards, windows, bar when floating)
- `radius.control = min(cornerRadius, space(4))` (from `Menu.qml:1508`, for nested controls and rows)
- `radius.pill = height/2` (switch knob, slider, only when `cornerRadius > 0`)

Remove the `radius: 0` overrides and the `max(2, …)` forcing.

**Borders.** `border.surface = max(1, space(2))` and `border.control = normalBorderWidth`. The tooltip uses `border.control`.

**Motion.**
- `duration.fast 120` (hover, color)
- `duration.base 200` (popup open, morph, bar float/dock)
- `duration.slow 320` (toast slide)
- Easing: `Style.easeOut` for anything pointer-caused, `OutCubic` → alias to it.

Keep `Style.duration()` as the only entry point.

**Color roles.** Add these to `Color.qml`, derived in code so all 24 themes work without edits:
- `text.secondary = mix(fg, bg, 0.72)`, then clamp toward fg until it reaches ≥ 4.5:1. The existing `alpha 0.7` is close: 4.5–10:1 on dark themes, 3.3–8.5 on light.
- `text.placeholder = mix(fg, bg, 0.55)`, a floor of about 3:1, and visibly lighter than `secondary`.
- `text.disabled = mix(fg, bg, 0.45)`.
- `status.danger / warning / success` from colors.toml `red` / `yellow` / `green`, with a contrast floor. Fall back to a fixed hue when the theme's "red" isn't red, or label the theme as such.
- `focus.ring = accent` at 1.0 alpha, 2px, drawn outside the control (the ToggleSwitch ring technique, `ToggleSwitch.qml:18-24`). Default `[controls] focus-*` to it instead of mirroring hover.
- Hover/cursor fill 0.08 → **0.12**, plus a 1px border at 0.4 (not 0.25), so the cue reaches about 1.3:1 and doesn't fade below normal.
- `scrim.text` / `scrim.dim` / `scrim.danger` for the speedtest and wifiqr overlays.
- Read `mode` (light/dark) from colors.toml so components can choose a mix direction when needed.
- Delete `[launcher]` from the template (dead), or wire it.

### 6.2 Shared component set

| Component | Variants | States | Owner / action |
|---|---|---|---|
| **Button** | `neutral` (default), `bordered`, **`primary`** (accent fill, `background` text), **`destructive`** (danger border/text; danger fill when focused) | idle, hover-cursor, pressed, **focus ring**, selected, **disabled**, **busy** (spinner via `iconSpinning`, already present) | `Ui/Button.qml`. Default `focusable: true` in windows. ConfirmDialog buttons become Button. |
| **IconButton** | default, destructive | idem + tooltip required | `Ui/PanelActionButton.qml` (rename later); fix the disabled look to `text.disabled` |
| **BarButton** | — | active, dimmed, concealed | `Ui/WidgetButton.qml` / `BarIconButton.qml` (unchanged) |
| **Segmented choice** | equal-width, content-width | selected, cursor, focus | `Ui/ButtonGroup.qml` |
| **Switch** / **SwitchRow** | — | on, off, **busy (knob pulse or 50% track)**, disabled, focus | `Ui/ToggleSwitch.qml` (add `activeFocusOnTab`, an accessible name), `Ui/Toggle.qml` |
| **Slider** | continuous, stepped | idle, drag, cursor, disabled | `Ui/PanelSlider.qml`. One fill color (choose foreground; the OSD follows). |
| **Dropdown / SearchableDropdown / MultiSelect / NumberField / TextField / FilterInput** | — | + disabled, + error | existing owners. Placeholder → `text.placeholder`. Delete MultiSelect and NumberField if they stay unused after Containers/VMs land. |
| **Row** | plain, selectable, with trailing action/switch | cursor, selected, busy, error | `Ui/CursorSurface.qml` (+ a `ListRow` composition: icon, title, secondary, trailing slot) |
| **Card** | flat (border.control), surface | — | **extract** from FeaturesSection/DisplaysSection into `Ui/Card.qml` |
| **Hero** | with trailing control | on/off/dim | `Ui/PanelHero.qml`. **Adopt it in the 5 panels**, replace `Qt.darker`, fix the empty-icon gap. |
| **SectionHeader** | — | — | `Ui/PanelSectionHeader.qml` (+ `SettingsHeader` composition) |
| **KeyValueGrid** | 1 or 2 columns, tabular numerals | — | **extract** InfoLabel/InfoValue/InfoPair from power + network |
| **EmptyState** | inline (panel), centered (overlay/window) | — | **extract** from Clipboard's icon + text. Adds an optional action ("Turn on Bluetooth", "Open Settings"). |
| **InlineMessage** | info, warning, error | — | **new**. Replaces 7 Settings error Texts; translates known failures, raw stderr behind "Details". |
| **PageHeader** | — | — | **extract** from the Settings sections: title + optional (i) explanation. |
| **Tooltip** | — | — | `Ui/PanelToolTip.qml`; Button and Bar use it |
| **Popup chrome** | attached (`KeyboardPanel`), hover (`PopupCard`) | open/close morph | keep both, share one chrome item (`Ui/SurfaceCard`) for background, border, radius |
| **Overlay chrome** | menu-style (`[menu]`), scrim overlay | — | `Ui/OverlayWindow.qml` |
| **ConfirmDialog** | neutral, destructive | **default focus = Cancel when destructive** | `Ui/ConfirmDialog.qml`, built from Button |
| **Toast** | info, critical (danger border + icon tint) | — | `notifications/Toast.qml` |

### 6.3 Panels vs full windows (applies to Containers and VMs, D-63; later to network, monitor and Settings)

A **panel** answers "what's running, and is it OK?" and allows one-step actions. A **window** answers "show me everything and let me change it".

**Panel** (attached `KeyboardPanel`, 380 wide):
1. Hero: icon, title, caps status ("2 RUNNING"), and an optional trailing master switch.
2. Separator.
3. Section header ("RUNNING").
4. Up to about 6 `ListRow`s: name, secondary status ("Up 3 h · 2 ports"), trailing IconButtons for the 1–2 commonest actions (Stop, Open). Destructive actions are absent or in the window only.
5. Empty state: "No containers running", with action "Manage…".
6. Footer: one full-width neutral `Button` "Manage containers…" (`iconText` arrow-out) that opens the window **at the item under the panel cursor**.

The panel never shows forms, logs or creation flows.

**Window** (FloatingWindow, Settings geometry: `implicitWidth min(space(900), 85% screen)`):
- Sidebar (`sidebarWidth 200`) listing items or groups, with the same icon, name and status text as the panel rows.
- Page: `PageHeader` (item name as `pageTitle`, status as a `label`), then Cards for Overview / Ports / Volumes / Logs, then `KeyValueGrid` for facts.
- Actions: one `primary` Button per page ("Start" / "Stop"), secondary actions neutral, destructive (Delete VM, Remove container) separated at the bottom of the page and confirmed with Cancel focused.

**Shared vocabulary** (the visual link between the two):
- identical item names, icons and status strings (one model file feeds both, as `monitor/Model.js` does for the monitor panel and Settings › Displays)
- the same Row component
- the same Switch for run state
- the same `status.*` colors
- in the window, the selected item highlighted with the same `selected` fill as the panel row

**Chrome:**
- Panels: `[popups]` border (accent gradient), `radius.surface`, `border.surface`.
- Windows: `Color.background` page + `foreground 0.04` sidebar tint (as in `Settings.qml:94`), with Hyprland's window border.
- Neither gets shadows.
- Window keyboard: Tab order sidebar → page, j/k in the sidebar, Esc closes, Ctrl+F filters.

---

## 7. Floating / docked bar (requested addition)

### 7.1 What exists today
`BarPanel` (`Bar.qml:1710-1840`) is a layer-shell window that spans the whole screen, transparent past a painted `barStrip`.
- `exclusiveZone: thickness` (`:1727`), `exclusionMode` Ignore when hidden.
- Hiding parks the surface with negative margins (`:1749-1755`).
- The input `mask` is the strip (`:1816`).
- Looks: opaque / glassy / clear (`bar.background` in `karchy/shell.json`).
- Under a real fullscreen (`fullscreen & 2`, `BarModel.fullscreenOn`, `BarModel.js:678`) the bar drops input.

Every consumer clears the bar through one seam: `bar.barSizeFor(screenName)` / `screenBarSizes`, used by `KeyboardPanel.qml:235`, `PopupCard.qml:36`, `notifications/Delivery.js:81` and the plugin API (`shell.qml:472`).

This architecture suits floating well. Floating only changes **where the strip is painted inside an already full-screen surface**. No surface resize is needed, so the change animates cheaply.

### 7.2 Geometry (derived from existing tokens)
- **Edge inset E and side inset S = `Style.gapsOut`** (half of Hyprland `general:gaps_out`; 5 at karchy's default `gaps_out = 10`, `default/hypr/looknfeel.lua:9`).
  - That's the distance every shell surface already keeps from the screen edge (panels: `KeyboardPanel.qml:44,72`; popups: `PopupCard.qml:13`; polkit; notifications).
  - Bar ends therefore line up with the right edge of attached panels and toasts.
  - With `karchy toggle window-gaps` (gaps 0, `default/hypr/toggles/window-no-gaps.lua`), E = S = 0 and floating degenerates to docked automatically.
- **Radius = `Style.cornerRadius`** (Hyprland rounding, 0 by default; 6 with `corners-rounded`). The floating bar matches windows: square card on square themes, rounded on rounded ones.
- **Card:** the bar's own background (opaque or glassy). No border by default. A new `[bar] border` / `border-alpha` in shell.toml (default `transparent`) lets a theme outline it. No shadow (Hyprland shadows are off in `looknfeel.lua`).
- **Theme overrides** in shell.toml `[bar]`: `float-margin` (px, default = gapsOut) and `float-radius` (default = cornerRadius). Geometry belongs to themes; behavior belongs to shell.json.
- **Docked:** E = S = 0, radius 0. Same as today.

### 7.3 Exclusive zone: avoid window reflow
**Recommended (A): constant reservation.** `exclusiveZone = E + T` in both states, with T = `thicknessFor(screen)`.
- Floating: the strip is painted at offset E, length screen − 2S.
- Docked: the strip is painted from the edge with thickness **E + T**, widgets centered across that extent (they move E/2, animated).
- Result: tiled and maximized windows never resize when the bar docks or floats, including during workspace-switch animations.
- Cost: the docked bar is E px thicker than today (31 vs 26 at defaults).

**Alternative (B): reservation follows state** (floating E + T, docked T).
- The docked bar is exactly today's bar, and maximized windows gain E px.
- But every transition reflows that monitor's tiled windows, including the workspace arriving during a switch animation. That's the awkward jump to avoid.
- Choose B only if the extra docked thickness is unacceptable; even then change the zone only once the animation ends.

Hidden bar (`bar-off`): unchanged (Ignore + park).

### 7.4 Deciding the state, per monitor
Add a pure function to `BarModel.js`, beside `fullscreenOn`: `dockedOn(toplevels, workspaceIds, opts)`. It's testable the same way.

Each `BarPanel` evaluates its own `screen`:
1. Workspaces considered: `Hyprland.monitorFor(screen).activeWorkspace`, plus the monitor's shown special workspace (from `lastIpcObject.specialWorkspace`, when its id isn't 0). Hidden special workspaces, such as minimized windows, don't count.
2. **Docked** if any mapped, non-hidden toplevel on those workspaces has `lastIpcObject.fullscreen & 1` (maximized). The existing code reads `& 2` for fullscreen, the same bitfield.
3. Real fullscreen (`& 2`): keep today's behavior (bar under the window, no input). The float state is irrelevant there. Leaving fullscreen into maximized lands docked.
4. Notched top bar (`thicknessFor > barSize`, a notch floor): always docked. The bar has to cover the cutout.
5. `style: "floating"` and `"docked"` skip the rules.

**Deliberately not docking (v1):**
- dwindle with one tiled window: gaps are still present, so a floating bar matches the gapped window
- scrolling layout: windows are always full-height, so a touch rule would dock permanently
- karchy's floating-workspace mode: only maximize counts

A later opt-in rule could cover "a tiled window touches the bar edge across ≥ 90% of its length". Add it only if the user asks after living with v1.

**Events** (react, don't poll, per `AGENTS.md`):
- Hyprland `rawEvent` names: `fullscreen`, `activewindowv2`, `openwindow`, `closewindow`, `movewindowv2`, `changefloatingmode`, `workspacev2`, `focusedmonv2`, `activespecialv2`, `moveworkspacev2`, `monitoraddedv2` / `monitorremovedv2`, `configreloaded` (gaps and rounding, which `Style` already refreshes).
- On any of them: `Hyprland.refreshToplevels()`, as `Bar.qml:1663-1670` does for `fullscreen`, then coalesce with `Qt.callLater` so one burst changes the state once.
- To verify in the VM: whether Hyprland 0.57 emits `fullscreen` for maximize (mode 1). If it doesn't, the other events plus the refresh still cover it.

**Workspace switch:** compute the destination's state on `workspacev2` and start the bar animation together with Hyprland's slide.

### 7.5 Transition
- Animate `barStrip` x / y / width / height, radius and the widget-row offset with `Style.duration(200)` and `Style.easeOut` (the same pair `KeyboardPanel.qml:54-58` uses for its morph). `reduceMotion` makes it instant.
- No `exclusiveZone` change under A, so the compositor does nothing during the animation.
- **Input mask** in floating mode: the strip *plus the E band to the screen edge* (one `Region` over the footprint), so throwing the pointer to the edge still hits the bar.
- Under fullscreen: `noInputRegion` as today.
- Glassy blur: Hyprland's `ignore_alpha` already leaves transparent pixels unblurred (`Bar.qml:1790-1797`), so rounded corners and the E band stay clear.

### 7.6 Panels, popups and toasts follow
- Have `screenBarSizes` / `barSizeFor()` publish the **footprint** E + T, not T. Its doc comment already says "Toasts and plugins clear the bar by it".
  - Every consumer (KeyboardPanel, PopupCard, notification Delivery, plugin API) then offsets correctly with no change of its own.
- Under A the footprint is constant, so open panels and toasts **don't move** when the bar docks or floats.
- Along the bar, panels already sit `gapsOut` from the side edge, which equals S, so an attached panel's outer edge stays flush with the floating bar's end.
- KeyboardPanel's comment that `barThickness` is "the strip's inner edge" stays true.

### 7.7 Config
`karchy/shell.json`:
```json
"bar": {
  "position": "top",
  "background": "opaque",
  "style": "auto"
}
```
- `style`: `"auto"` (default; floats, docks for a maximized window on that monitor) | `"floating"` | `"docked"`.
- A missing key reads as `"auto"`.
- Settings › Appearance gets a ButtonGroup "Bar: Auto · Floating · Docked", with the (i) text "Auto docks the bar while a window is maximized."
- `karchy-bar style <auto|floating|docked>` mirrors the background cycle.
- `background: "none"` combined with floating is allowed. It just shows no card.

Placement: `BarModel.dockedOn` (pure); `BarPanel` gains `readonly property bool docked`, `stripInset`, `stripRadius`. `thicknessFor` → `footprintFor` for publication; `thickness` stays the painted size.

---

## 8. Prioritized migration plan

Order: user-visible severity × reach first, then drift that blocks Containers/VMs, then consolidation.

| # | Item | Why (evidence) | Effort |
|---|---|---|---|
| 1 | **Destructive confirms default to Cancel**: `ConfirmDialog.selectedIndex` 0 for destructive, drop `Clipboard.qml:95` | 4.4. Enter-Enter uninstalls or deletes. | XS (≤1 h) |
| 2 | **Secondary/placeholder/disabled text roles** in Color, replace 53 `Qt.darker` sites (Ui first: PanelSectionHeader, PanelHero, Toggle, TextField, Dropdown, SearchableDropdown, MultiSelect, NumberField, ToggleSwitch, PanelActionButton; then clock, monitor, Tray, media, Toast) | 4.1. Every light theme inverts hierarchy; placeholders are unreadable as such. | S (½ day) + light-theme screenshots |
| 3 | **Focus ring + stronger hover/cursor** tokens (template `[controls] focus-*` → accent ring; hover 0.12 / border 0.4) | 4.2. Contrast 1.12–1.24:1; focus = hover. | S |
| 4 | **Settings keyboard**: `focusable: true` on Settings Buttons, `activeFocusOnTab` on ToggleSwitch, j/k + Esc in the window | 4.3. Needed by the VMs/Containers windows too. | S |
| 5 | **Button variants** `primary` / `destructive` / disabled / busy, ToggleSwitch busy visual | 3.3, 4.7. Containers/VMs need Start/Stop/Delete. | S–M |
| 6 | **Extract** `PageHeader`, `InlineMessage`, `Card`, `EmptyState`, `KeyValueGrid`; adopt in Settings (7 sections) and power/network | 3.2. Lets the new windows start on shared parts instead of an 8th copy. | M (1–2 days) |
| 7 | **Status color roles** (danger, warning, success) with contrast floor; critical toast styling | 4.5, `Toast.qml:76`. | S–M |
| 8 | **Floating/docked bar** (section 7) | User request. | M–L (2–4 days incl. VM checks across dwindle, scrolling, floating, special and multi-monitor) |
| 9 | **Adopt `PanelHero`** in 5 panels (fix bluetooth empty icon, duplicate copy) | 3.2, bluetooth crop. | M |
| 10 | **Type roles + caption 11**, Liberation Sans → token, scale `letterSpacing` | 2.1, 4.6. | S |
| 11 | **Radius/border/motion tokens**; tooltip → one component; OSD → `popups.background`; panels → `popups.text`; delete `[launcher]`, decide on MultiSelect/NumberField | 2.3–2.5, 3.1, 4.9. | M, but low risk and can trickle in |
| 12 | **Spacing tokens for de-facto sizes**, then gradually move raw `Style.space(N)` in the worst files (audio 35, clock 30, network 28, Menu 26, Tray 25) | 3.1. | L, but opportunistic: do it when a file is touched for other reasons |
| 13 | Copy: polkit action messages for karchy helpers; Settings i18n; Settings explanations behind (i) | 4.8, `cons/pk.png`. | S–M |

Items 1–4 are each self-contained and could ship as separate small PRs. Item 6 should land before or with the Containers/VMs windows. Item 8 is independent of the others except that it benefits from item 11's radius token.

---

## 9. Not verified

- **Light theme:** no light-theme screenshots of any panel, Settings, menu, notifications, polkit, lock or OSD. Section 4.1 is computed from code and palette values.
- **Keyboard:** focus behavior in Settings and the panels was read from code only, not exercised.
- **Unseen states:** the power panel, clock panel, reminders, image picker, lock error, polkit error flash, toast critical styling, and the panel scanning / busy / error states have no screenshots.
- **Floating bar:** the proposal is a design, not a prototype. Two things need checking in a VM:
  - which Hyprland events fire on maximize
  - whether a 200 ms strip animation stays smooth on the virtio GPU
