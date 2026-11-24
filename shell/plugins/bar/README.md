# Karchy bar

This is the Quickshell implementation of the Karchy status bar. It is
shipped as a first-party plugin of [`karchy-shell`](../../README.md), the
long-running shell host. The bar is mounted at startup and lives inside
the shell for its whole session.

- `manifest.json` declares the plugin (`id: karchy.bar`, `kind: bar`) and points at `Bar.qml` as the entry point.
- `Bar.qml` is Karchy-owned bar engine code, loaded by the karchy-shell host. Users should not edit it directly.
- `widgets/` holds simple first-party bar widgets with sibling manifests.
- Feature plugins such as `../panels/audio/`, `../panels/network/`, `../panels/power/`, and `../agents/` provide richer popup bar plugins.
- The bar receives its config from the host shell as a `barConfig` property; the host merges `~/.config/karchy/shell.json` over karchy's defaults (`karchy/shell.json`).
- `karchy bar position` updates only the user shell.json file.

## Customizing

The bar config lives under the `bar:` key of [`~/.config/karchy/shell.json`](../../../docs/karchy-shell.md#shelljson). Out of the box the shell uses [`config/karchy/shell.json`](../../../config/karchy/shell.json). Your file holds only what you changed: objects merge key by key over the defaults, and a list or value you set replaces the default one. The bar gestures, `karchy bar ...` and Settings save only the differences.

The bar is configured directly on the bar itself: drag empty bar space (or click-and-hold) to move the bar to another screen edge, double-left-click empty center-bar space to cycle the bar background from clear to glassy to opaque, and drag widgets to reorder them. The `karchy bar position`, `karchy bar background`, `karchy bar move`, and `karchy bar set` commands do the same from scripts. `karchy bar style auto|floating|docked` (or Settings › Appearance) picks whether the bar floats inset from the screen edge, stays docked, or, in auto (the default), floats and docks on a monitor while a window there is maximized; see `docs/architecture.md`, "The bar: floating and docked". Enable or disable widgets with `karchy plugin enable` and `karchy plugin disable` (widget ids come from `karchy plugin list`).

Example `shell.json` (bar subtree only shown):

```json
{
  "version": 1,
  "bar": {
    "position": "top",
    "background": "opaque",
    "style": "auto",
    "layout": {
      "left": [
        { "id": "karchy.menu" },
        { "id": "karchy.spacer", "size": 12 },
        { "id": "karchy.workspaces" }
      ],
      "centerBegin": [
        { "id": "karchy.media" }
      ],
      "center": [
        { "id": "karchy.clock", "format": "HH:mm" }
      ],
      "centerEnd": [],
      "right": [
        { "id": "karchy.audio" },
        { "id": "karchy.power" }
      ]
    }
  }
}
```

`center` is a box in the middle of the bar whose modules are centered as one group on the exact horizontal/vertical center. `centerBegin` and `centerEnd` hang off the box's two edges and move out as it grows; with the box empty they meet in the middle of the bar.

## Module catalogue

### First-party interactive widgets

| Name | What it does | Interactions |
|---|---|---|
| `karchy.menu` | Karchy menu launcher | left = menu · right = terminal |
| `karchy.workspaces` | Hyprland workspace switcher; the focused workspace shows its layout, and one holding a window that asked for focus and was not given it takes the urgent color | left = focus workspace, or cycle the focused one's layout |
| `karchy.clock` | Date/time label + popup with a month grid, ISO week numbers, and month stepping (clock and calendar only) | left = popup · right = cycle label format · middle = timezone selector |
| `karchy.notifications` | Bell with a dot while notifications wait unseen (the Do Not Disturb glyph while that is on) + popup listing the notifications nobody answered: ongoing, then the rest, then Silent; grouped by app; each with its buttons, dismiss and a ⋯ menu for its app (Allow, Silent, Off, Settings); Clear all, History (last 24 hours) and the Do Not Disturb switch | left = popup · right = Do Not Disturb |
| `karchy.media` | MPRIS now-playing — scrolling track + artist, cover-art popup | left = play/pause · middle = next · scroll = prev/next · right = popup |
| `karchy.indicators` | Manual state indicators | left = indicator action |
| `karchy.system-update` | Available update indicator | left = update |
| `karchy.tray` | System tray | hover = reveal drawer · right on chevron = manage |
| `karchy.microphone` | Mic icon + scroll volume | left = mute toggle · middle = audio panel · scroll = source volume |

| `karchy.audio` | Volume icon + popup with master slider, output-device picker, per-app mixer | left = popup · right = mute · middle = popup · scroll = volume |
| `karchy.network` | Wi-Fi/Ethernet icon + popup with Wi-Fi scan, signal, connect, DNS provider selection | left = popup |
| `karchy.power` | Battery/AC icon + popup with battery stats, power profiles, and system info | left = popup · right = toggle percentage |
| `karchy.bluetooth` | Bluetooth icon + popup with device list, connect/disconnect, battery | left = popup · right = toggle radio |
| `karchy.monitor` | Brightness and laptop display controls | left = popup |
| `karchy.clipboard` | Clipboard history (D-167), by default in the tray's drawer: popup with the pinned entries and the newest others; a click pastes one, each has Pin and Delete, with Clear all and the "Keep a history" switch under them | left = popup · right = the full history with search |
| `karchy.vms` | Shown only while a QEMU/KVM VM runs: count + popup to show, shut down, force off or start VMs | left = popup · right = Virtual machines window |

The `karchy.indicators` widget loads individual bar indicators from `indicators/`. With no settings it shows all indicators in the default order. Set `hidden` to leave some out, such as `["Reminder"]`; indicators karchy adds later still show. The older `items` setting lists the indicators to show, in order; an indicator karchy added after the list was written is put in at its default place unless `hidden` names it (`known` names the indicators a list was written knowing about; without it, the four that existed before 2026-11-17). Set `alwaysShow` to `true` to keep inactive indicators visible instead of revealing them only on hover. Multiple `karchy.indicators` instances are allowed, so different sections can show different subsets.

## Orientation

All widgets work in `top`, `bottom`, `left`, and `right` positions. Popups anchor on the side opposite the bar edge, sliding into the workspace. Vertical bars use 28px width; widgets that show text fall back to compact icon-only forms (e.g. `media` hides its scrolling label).

## Icon geometry

Use `BarIconButton` from `qs.Ui` for bar icons. It fits the visible glyph bounds to `Style.bar.iconSize` and centers them on both axes. It preserves each glyph's aspect ratio. Set `labelText` for an adjacent text label, such as the battery percentage.

The `[bar]` section of a theme's `shell.toml` supplies the shared dimensions. `icon-size` sets the visual target, with a default of 12 logical pixels. `icon-canvas` sets the canvas, with a default of 16 logical pixels. `icon-slot` and `status-slot` set the button extent. These dimensions follow the font scale unless `scale-with-font` is false.

Custom `iconComponent` content also fits the shared target. Its source dimensions can be 15px or another size. The bar measures its glyph, image, or vector bounds and applies one scale without changing its aspect ratio. A source `iconSize` override does not change the rendered target. Image padding remains part of an application's tray asset.

Custom text bounds include text alignment and padding. The bar applies each shape's fill mode and alignment to `Shape.boundingRect`. Canvas and shader icons use their item bounds. Set their item size to match their artwork.

`WidgetButton` also uses the shared renderer for a single icon glyph. This covers custom command widgets and existing plugins that use `WidgetButton` with a different `fontSize`. Text labels retain their text size. Custom widgets must use `WidgetButton` or `BarIconButton` for this icon contract.

## Custom user modules

The schema accepts arbitrary module ids that you provide. Set `type` to `command` for shell-driven output or `qml` for a custom QML widget. Both still go under `bar.layout.<section>` in `shell.json`.

Command module:

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        { "id": "karchy.tray" },
        { "id": "vpn", "type": "command", "exec": "~/.config/karchy/bar/scripts/vpn-status", "interval": 5, "tooltip": "VPN", "onClick": "nm-connection-editor" },
        { "id": "karchy.audio" }
      ]
    }
  }
}
```

The command may print plain text or Waybar-style JSON. Take icons from karchy's icon map (`karchy-icon --list`) rather than pasting glyphs, for example:

```bash
printf '{"text":"%s","tooltip":"Work VPN","class":"active"}\n' "$(karchy-icon net.vpn)"
```

QML module:

```json
{
  "version": 1,
  "bar": {
    "layout": {
      "right": [
        { "id": "gpu", "type": "qml" },
        { "id": "karchy.audio" }
      ]
    }
  }
}
```

Then create `~/.config/karchy/bar/modules/gpu.qml`. If you want to store it elsewhere, add a `source` path.

Custom QML modules should be an `Item` with `implicitWidth` and `implicitHeight`. They may optionally define these properties, which the bar fills after loading:

```qml
import QtQuick

Item {
  property var bar
  property string moduleName
  property var settings

  implicitWidth: 28
  implicitHeight: bar ? bar.barSize : 26

  Text {
    anchors.centerIn: parent
    text: "GPU"
    color: bar ? bar.foreground : "white"
    font.family: bar ? bar.fontFamily : "monospace"
    font.pixelSize: 12
  }

  MouseArea {
    anchors.fill: parent
    onClicked: if (bar) bar.run("karchy-launch-or-focus-tui btop")
  }
}
```

## Bar properties available to widgets

Widgets receive `bar` (the shell root), `moduleName` (string), and `settings` (object) injected at load time. A widget that declares `fixedEdge` also gets the edge of it that stays put when it grows: `"start"` (left, or top on a vertical bar), `"end"`, or `"center"` when it grows both ways, following the section it sits in. When the center box holds more than one widget, its first gets `"end"` and its last `"start"`, like `centerBegin`'s and `centerEnd`'s. A widget that grows, like the tray's drawer or the indicator peek, can lay its content out against that edge so it doesn't shift. A widget moved to another section keeps running, and its `fixedEdge` and `settings` change in place, so bind to them rather than reading them once. The bar exposes:

- `bar.foreground`, `bar.background`, `bar.urgent` — theme colors (live-updated)
- `bar.fontFamily` — current monospace family
- `bar.position` — `"top" | "bottom" | "left" | "right"`
- `bar.vertical` — boolean shortcut
- `bar.barSize` — 26 horizontal / 28 vertical
- `bar.run(command)` — fire-and-forget bash exec (quote arguments with `Util.shellQuote` from `qs.Commons`)
- `bar.showTooltip(target, text)` / `bar.hideTooltip(target)` — shared tooltip popup
- `bar.requestPopout(owner)` / `bar.releasePopout(owner)` — one-popup-at-a-time coordinator

Every bar widget is manifest-backed.
Simple widgets carry sibling manifests such as `widgets/Workspaces.manifest.json`;
richer popup plugins live in feature directories such as `../panels/audio/`,
`../panels/network/`, and `../agents/`; and feature plugins such as
`karchy.menu` and `karchy.media` declare their bar-widget entry points in their own
`manifest.json`. Bar layout ids are namespaced, e.g. `karchy.audio`,
`karchy.network`, and `karchy.clock`.

Add-on widgets ship in karchy's add-on packages (`addons/`, D-106) under `/usr/share/karchy/plugins/<plugin-id>/` with their own `manifest.json` declaring `kinds: ["bar-widget"]` and a `barWidget` entry point, and are hosted exactly like the built-in ones. Place them with `karchy plugin enable` and `karchy bar move`.
