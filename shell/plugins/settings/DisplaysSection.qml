import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../panels/monitor/Model.js" as MonitorModel

// Settings › Displays: per-monitor mode, scale, position, rotation and on/off,
// saved per physical monitor by karchy-settings-displays.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property var monitors: []
  property string error: ""
  readonly property var scalePresets: MonitorModel.SCALE_PRESETS
  // Labels beside the controls when there is room, above them when not.
  readonly property bool wide: width >= Style.space(560)

  function apply(args) {
    root.error = ""
    setProc.command = ["karchy-settings-displays"].concat(args)
    setProc.running = true
  }

  // What undoes the change in flight, asked about once it has applied.
  property var undoArgs: null
  // Monitors whose color and mirroring settings are shown, by key.
  property var advancedOpen: ({})

  // Resolution, refresh rate, scale and rotation can leave a screen unusable,
  // so each is undone after 15 seconds unless kept. The undo puts back what
  // was saved for the monitor, or forgets it if nothing was.
  function applyAndAsk(monitor, setting, value, fallback) {
    root.undoArgs = monitor.saved === null
      ? ["forget", monitor.name]
      : ["set", monitor.name, setting, String(root.savedValue(monitor, setting, fallback))]
    root.apply(["set", monitor.name, setting, String(value)])
  }

  function askToKeep() {
    var undo = root.undoArgs
    root.undoArgs = null
    if (!undo || !root.settings) return
    root.settings.askToKeep(function(n) {
      return "Keep these display settings? They go back in " + n + (n === 1 ? " second." : " seconds.")
    }, "Keep", "Go back", 15, function() {
      // Detached: closing Settings also undoes, and unloads this page with
      // its processes; the page reloads from Hyprland's monitor event.
      Quickshell.execDetached(["karchy-settings-displays"].concat(undo))
    })
  }

  function load(text) {
    try {
      root.monitors = JSON.parse(text).monitors || []
    } catch (e) {
      root.monitors = []
    }
  }

  function resolution(mode) { return String(mode).split("@")[0] }

  function resolutions(monitor) {
    var seen = {}
    var out = []
    for (var i = 0; i < monitor.modes.length; i++) {
      var res = resolution(monitor.modes[i])
      if (!seen[res]) { seen[res] = true; out.push(res) }
    }
    out.sort(function(a, b) {
      var pa = a.split("x"), pb = b.split("x")
      return (pb[0] * pb[1]) - (pa[0] * pa[1])
    })
    return out
  }

  function rates(monitor, res) {
    return monitor.modes
      .filter(function(m) { return resolution(m) === res })
      .map(function(m) { return { value: m, label: Number(m.split("@")[1]).toFixed(2) + " Hz" } })
  }

  // The offered mode closest to what the monitor runs now.
  function currentMode(monitor) {
    var res = monitor.width + "x" + monitor.height
    var best = "", bestDistance = 1e9
    for (var i = 0; i < monitor.modes.length; i++) {
      if (resolution(monitor.modes[i]) !== res) continue
      var d = Math.abs(Number(monitor.modes[i].split("@")[1]) - monitor.refreshRate)
      if (d < bestDistance) { bestDistance = d; best = monitor.modes[i] }
    }
    return best
  }

  function savedValue(monitor, key, fallback) {
    return monitor.saved && monitor.saved[key] !== undefined ? monitor.saved[key] : fallback
  }

  function refresh() {
    if (!setProc.running) statusProc.running = true
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["karchy-settings-displays", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
    onExited: function(exitCode) {
      if (exitCode === 0) root.askToKeep()
      else root.undoArgs = null
    }
  }

  PageHeader {
    title: "Displays"
    explanation: "Changes apply right away and are remembered for each monitor, so a laptop finds its desk monitor's settings again after docking. A rule for the same monitor in ~/.config/hypr/monitors.lua wins over these."
  }

  InlineMessage {
    kind: "error"
    text: root.error !== "" ? "Couldn't change the display." : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  // Arrangement: each monitor at its logical size and position.
  Rectangle {
    id: arrangement
    Layout.fillWidth: true
    Layout.preferredHeight: Style.space(180)
    color: "transparent"
    border.color: Style.normalBorderColor
    border.width: Style.normalBorderWidth
    radius: Style.cornerRadius
    visible: root.monitors.length > 0

    readonly property var enabled: root.monitors.filter(function(m) { return m.enabled })
    readonly property var bounds: {
      var minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9
      for (var i = 0; i < enabled.length; i++) {
        var m = enabled[i]
        minX = Math.min(minX, m.x); minY = Math.min(minY, m.y)
        maxX = Math.max(maxX, m.x + m.width / m.scale); maxY = Math.max(maxY, m.y + m.height / m.scale)
      }
      return { x: minX, y: minY, w: Math.max(1, maxX - minX), h: Math.max(1, maxY - minY) }
    }
    readonly property real ratio: Math.min((width - Style.space(40)) / bounds.w, (height - Style.space(40)) / bounds.h)

    Repeater {
      model: arrangement.enabled
      delegate: Rectangle {
        required property var modelData
        x: (arrangement.width - arrangement.bounds.w * arrangement.ratio) / 2 + (modelData.x - arrangement.bounds.x) * arrangement.ratio
        y: (arrangement.height - arrangement.bounds.h * arrangement.ratio) / 2 + (modelData.y - arrangement.bounds.y) * arrangement.ratio
        width: modelData.width / modelData.scale * arrangement.ratio - 2
        height: modelData.height / modelData.scale * arrangement.ratio - 2
        radius: Style.cornerRadius
        color: Style.selectedAccentFill
        border.color: Commons.Color.accent
        border.width: Style.spacing.hairline

        Text {
          anchors.centerIn: parent
          horizontalAlignment: Text.AlignHCenter
          text: modelData.name + "\n" + modelData.width + "×" + modelData.height + " · " + MonitorModel.normalizeScale(modelData.scale) + "×"
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
      }
    }
  }

  Repeater {
    model: root.monitors
    delegate: Card {
      id: card
      required property var modelData
      readonly property var monitor: modelData
      readonly property string mode: root.currentMode(monitor)
      // The only monitor that is on can't be turned off; the subtitle says so.
      // With one monitor there is nothing to switch, so no switch.
      readonly property bool lastOn: card.monitor.enabled && arrangement.enabled.length === 1
      // Color depth, color mode and mirroring, shown on request; remembered
      // per monitor, since the cards are rebuilt after every change.
      readonly property bool advanced: !!root.advancedOpen[card.monitor.key]
      readonly property string colorMode: String(root.savedValue(card.monitor, "cm", "auto"))
      readonly property bool hdr: colorMode === "hdr" || colorMode === "hdredid"
      title: monitor.name
      subtitle: (monitor.key || monitor.description) + (lastOn && root.monitors.length > 1 ? ", the only monitor on" : "")
      trailing: ToggleSwitch {
        visible: root.monitors.length > 1
        checked: card.monitor.enabled
        enabled: !card.lastOn
        busy: setProc.running
        accessibleName: card.monitor.name
        onToggled: root.apply(["set", card.monitor.name, "enabled", card.monitor.enabled ? "false" : "true"])
      }

        GridLayout {
          visible: card.monitor.enabled
          Layout.fillWidth: true
          columns: root.wide ? 2 : 1
          columnSpacing: Style.spacing.xxl
          rowSpacing: Style.spacing.md

          SettingsLabel { text: "Resolution" }
          Dropdown {
            Layout.fillWidth: true
            showLabel: false
            value: root.resolution(card.mode)
            options: root.resolutions(card.monitor)
            onChanged: function(value) {
              var choices = root.rates(card.monitor, value)
              if (choices.length > 0) root.applyAndAsk(card.monitor, "mode", choices[0].value, "preferred")
            }
          }

          SettingsLabel { text: "Refresh rate" }
          Dropdown {
            Layout.fillWidth: true
            showLabel: false
            value: card.mode
            options: root.rates(card.monitor, root.resolution(card.mode))
            onChanged: function(value) { root.applyAndAsk(card.monitor, "mode", value, "preferred") }
          }

          SettingsLabel { text: "Scale" }
          ButtonGroup {
            readonly property var presets: MonitorModel.availableScales(root.scalePresets, card.monitor.width, card.monitor.height)
            // Labelled with the scale Hyprland will really use, as the display
            // panel does (3 on a 1280×800 screen is 3.2x).
            options: [{ value: "auto", label: "Auto" }].concat(presets.map(function(p) {
              return { value: p, label: Commons.I18n.formatNumber(MonitorModel.cleanScale(Number(p), card.monitor.width, card.monitor.height)) + "x" }
            }))
            value: root.savedValue(card.monitor, "scale", "auto") === "auto"
              ? "auto"
              : presets[MonitorModel.matchingScaleIndex(presets, card.monitor.scale, card.monitor.width, card.monitor.height)] || ""
            onChanged: function(value) {
              var scale = value === "auto" ? "auto" : MonitorModel.cleanScale(Number(value), card.monitor.width, card.monitor.height)
              root.applyAndAsk(card.monitor, "scale", scale, "auto")
            }
          }

          SettingsLabel { visible: root.monitors.length > 1; text: "Position" }
          Dropdown {
            visible: root.monitors.length > 1
            showLabel: false
            value: root.savedValue(card.monitor, "position", "auto")
            options: [
              { value: "auto", label: "Automatic" },
              { value: "auto-left", label: "Left of the others" },
              { value: "auto-right", label: "Right of the others" },
              { value: "auto-up", label: "Above the others" },
              { value: "auto-down", label: "Below the others" }
            ]
            onChanged: function(value) { root.apply(["set", card.monitor.name, "position", value]) }
          }

          SettingsLabel { text: "Rotation" }
          Dropdown {
            Layout.fillWidth: true
            showLabel: false
            value: String(card.monitor.transform % 4)
            options: [
              { value: "0", label: "Normal" },
              { value: "1", label: "90°" },
              { value: "2", label: "180°" },
              { value: "3", label: "270°" }
            ]
            onChanged: function(value) { root.applyAndAsk(card.monitor, "transform", value, "0") }
          }

          // FreeSync / G-Sync / Adaptive-Sync. Some monitors flicker or go
          // dark with it, so a change asks to be kept like the others.
          SettingsLabel { text: "Variable refresh" }
          Dropdown {
            Layout.fillWidth: true
            showLabel: false
            value: String(root.savedValue(card.monitor, "vrr", 0))
            options: [
              { value: "0", label: "Off" },
              { value: "2", label: "In fullscreen apps and games" },
              { value: "1", label: "Always" }
            ]
            onChanged: function(value) { root.applyAndAsk(card.monitor, "vrr", value, "0") }
          }

          Button {
            Layout.columnSpan: root.wide ? 2 : 1
            focusable: true
            bordered: true
            text: card.advanced ? "Hide color and mirroring" : "Color and mirroring…"
            onClicked: {
              var open = Object.assign({}, root.advancedOpen)
              open[card.monitor.key] = !card.advanced
              root.advancedOpen = open
            }
          }

          // 10-bit color: smoother gradients, if the monitor, its cable and the
          // GPU all take it. A change can blank the screen, so it asks to be kept.
          SettingsLabel { visible: card.advanced; text: "Color depth"; Layout.alignment: Qt.AlignTop; Layout.topMargin: Style.space(8) }
          ColumnLayout {
            visible: card.advanced
            spacing: Style.spacing.sm
            ButtonGroup {
              options: [{ value: "8", label: "8-bit" }, { value: "10", label: "10-bit" }]
              value: String(root.savedValue(card.monitor, "bitdepth", 8))
              onChanged: function(value) { root.applyAndAsk(card.monitor, "bitdepth", value, "8") }
            }
            InlineMessage {
              Layout.fillWidth: true
              kind: "warning"
              text: String(root.savedValue(card.monitor, "bitdepth", 8)) === "10" && String(card.monitor.format || "").indexOf("2101010") < 0
                ? "Still 8-bit: this monitor, its cable or the graphics card doesn't take 10-bit here." : ""
            }
          }

          SettingsLabel { visible: card.advanced; text: "Color mode"; Layout.alignment: Qt.AlignTop; Layout.topMargin: Style.space(8) }
          ColumnLayout {
            visible: card.advanced
            spacing: Style.spacing.sm
            Dropdown {
              Layout.fillWidth: true
              showLabel: false
              value: card.colorMode
              options: [
                { value: "auto", label: "Automatic" },
                { value: "srgb", label: "Standard (sRGB)" },
                { value: "wide", label: "Wide color (BT.2020)" },
                { value: "edid", label: "The monitor's own colors" },
                { value: "hdr", label: "HDR" },
                { value: "hdredid", label: "HDR, with the monitor's brightness range" }
              ]
              onChanged: function(value) { root.applyAndAsk(card.monitor, "cm", value, "auto") }
            }
            InlineMessage {
              Layout.fillWidth: true
              kind: "warning"
              text: card.hdr && String(card.monitor.colorMode || "").indexOf("hdr") < 0
                ? "HDR isn't on: this monitor doesn't report HDR support, or the graphics card can't drive it." : ""
            }
          }

          // How SDR windows (most apps) look while the screen is in HDR.
          SettingsLabel { visible: card.advanced && card.hdr; text: "SDR brightness" }
          Dropdown {
            visible: card.advanced && card.hdr
            Layout.fillWidth: true
            showLabel: false
            value: String(root.savedValue(card.monitor, "sdrbrightness", 1))
            options: ["0.8", "1", "1.2", "1.4", "1.6", "1.8", "2"].map(function(v) {
              return { value: v, label: Math.round(Number(v) * 100) + "%" + (v === "1" ? " (standard)" : "") }
            })
            onChanged: function(value) { root.apply(["set", card.monitor.name, "sdrbrightness", value]) }
          }

          SettingsLabel { visible: card.advanced && card.hdr; text: "SDR saturation" }
          Dropdown {
            visible: card.advanced && card.hdr
            Layout.fillWidth: true
            showLabel: false
            value: String(root.savedValue(card.monitor, "sdrsaturation", 1))
            options: ["0.8", "0.9", "1", "1.1", "1.2", "1.3"].map(function(v) {
              return { value: v, label: Math.round(Number(v) * 100) + "%" + (v === "1" ? " (standard)" : "") }
            })
            onChanged: function(value) { root.apply(["set", card.monitor.name, "sdrsaturation", value]) }
          }

          // Show another monitor's picture here, as for a projector.
          SettingsLabel { visible: card.advanced && root.monitors.length > 1; text: "Mirror" }
          Dropdown {
            visible: card.advanced && root.monitors.length > 1
            Layout.fillWidth: true
            showLabel: false
            value: String(root.savedValue(card.monitor, "mirror", "none"))
            options: [{ value: "none", label: "Off: its own picture" }].concat(
              root.monitors.filter(function(m) { return m.name !== card.monitor.name && m.enabled })
                .map(function(m) { return { value: m.name, label: "Show " + m.name + "'s picture" } }))
            onChanged: function(value) { root.applyAndAsk(card.monitor, "mirror", value, "none") }
          }
        }

      Button {
        focusable: true
        visible: card.monitor.saved !== null
        text: "Back to automatic"
        bordered: true
        // Forgets every choice saved for this monitor, so it asks first.
        onClicked: {
          var name = card.monitor.name
          if (root.settings) root.settings.ask("Forget what's saved for " + name + "? Its resolution, scale, position, rotation, variable refresh, color and mirroring go back to automatic.",
            "Back to automatic", function() { root.apply(["forget", name]) })
        }
      }
    }
  }
}
