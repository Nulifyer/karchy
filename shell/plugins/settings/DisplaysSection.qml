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
      title: monitor.name
      subtitle: monitor.key || monitor.description
      trailing: ToggleSwitch {
        checked: card.monitor.enabled
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
              if (choices.length > 0) root.apply(["set", card.monitor.name, "mode", choices[0].value])
            }
          }

          SettingsLabel { text: "Refresh rate" }
          Dropdown {
            Layout.fillWidth: true
            showLabel: false
            value: card.mode
            options: root.rates(card.monitor, root.resolution(card.mode))
            onChanged: function(value) { root.apply(["set", card.monitor.name, "mode", value]) }
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
              root.apply(["set", card.monitor.name, "scale", String(scale)])
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
            onChanged: function(value) { root.apply(["set", card.monitor.name, "transform", value]) }
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
          if (root.settings) root.settings.ask("Forget what's saved for " + name + "? Its resolution, scale, position and rotation go back to automatic.",
            "Back to automatic", function() { root.apply(["forget", name]) })
        }
      }
    }
  }
}
