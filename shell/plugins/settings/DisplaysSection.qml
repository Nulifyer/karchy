import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../panels/monitor/Model.js" as MonitorModel

// Settings › Displays: per-monitor mode, scale, position, rotation and on/off,
// saved per physical monitor by karchy-settings-displays; and the night light
// for every monitor (karchy-settings-nightlight).
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

  // The modes the monitor offers, and the one it runs when that is a custom
  // one (set in monitors.lua, or by a virtual machine's window): the
  // dropdowns then show it instead of standing empty.
  function modesOf(monitor) {
    var res = monitor.width + "x" + monitor.height
    for (var i = 0; i < monitor.modes.length; i++)
      if (resolution(monitor.modes[i]) === res) return monitor.modes
    return monitor.modes.concat([res + "@" + Number(monitor.refreshRate).toFixed(2)])
  }

  function resolutions(monitor) {
    var seen = {}
    var out = []
    var modes = modesOf(monitor)
    for (var i = 0; i < modes.length; i++) {
      var res = resolution(modes[i])
      if (!seen[res]) { seen[res] = true; out.push(res) }
    }
    out.sort(function(a, b) {
      var pa = a.split("x"), pb = b.split("x")
      return (pb[0] * pb[1]) - (pa[0] * pa[1])
    })
    return out
  }

  function rates(monitor, res) {
    return modesOf(monitor)
      .filter(function(m) { return resolution(m) === res })
      .map(function(m) { return { value: m, label: Number(m.split("@")[1]).toFixed(2) + " Hz" } })
  }

  // The offered mode closest to what the monitor runs now.
  function currentMode(monitor) {
    var res = monitor.width + "x" + monitor.height
    var best = "", bestDistance = 1e9
    var modes = modesOf(monitor)
    for (var i = 0; i < modes.length; i++) {
      if (resolution(modes[i]) !== res) continue
      var d = Math.abs(Number(modes[i].split("@")[1]) - monitor.refreshRate)
      if (d < bestDistance) { bestDistance = d; best = modes[i] }
    }
    return best
  }

  function savedValue(monitor, key, fallback) {
    return monitor.saved && monitor.saved[key] !== undefined ? monitor.saved[key] : fallback
  }

  function refresh() {
    if (!setProc.running) statusProc.running = true
  }

  // ---- Night light: what karchy-settings-nightlight reports.
  property var night: ({ installed: true, on: false, schedule: false, from: "20:00", to: "07:00", temperature: 4000, until: "", userConfig: false })
  // Counts the answers, so the time fields take the saved (and tidied) value
  // after a change and keep what was typed after a refusal.
  property int nightRevision: 0
  property string nightError: ""
  // The warmth being dragged, in kelvin; 0 while none is.
  property int nightPreview: 0
  // A warmth to save once the preview in flight has been shown; 0 for none.
  property int nightSaveAfterPreview: 0
  // The warmth being saved, so the slider shows it at once and further steps
  // count from it; 0 once the command has answered with it.
  property int nightWarmthPending: 0
  readonly property int nightWarmth: nightWarmthPending > 0 ? nightWarmthPending : night.temperature
  // Left is barely tinted, right is warmest.
  readonly property int nightCoolest: 6000
  readonly property int nightWarmest: 2500
  readonly property int nightStep: 100

  function loadNight(text) {
    try {
      var status = JSON.parse(text)
      if (!status || typeof status !== "object") return
      root.night = status
      root.nightRevision++
      if (status.temperature === root.nightWarmthPending) root.nightWarmthPending = 0
    } catch (e) {
    }
  }

  // One change at a time; the newest one made meanwhile runs next.
  property var nightQueued: null

  function setNight(args) {
    if (nightProc.running) {
      root.nightQueued = args
      return
    }
    root.nightError = ""
    nightProc.command = ["karchy-settings-nightlight"].concat(args)
    nightProc.running = true
  }

  // Shows a warmth while the slider moves. One command at a time; a newer
  // position replaces one still waiting.
  function previewNight(kelvin) {
    root.nightPreview = kelvin
    if (nightPreviewProc.running) return
    nightPreviewProc.shown = kelvin
    nightPreviewProc.command = ["karchy-settings-nightlight", "preview", String(kelvin)]
    nightPreviewProc.running = true
  }

  // Saves the warmth, which also puts back what should be showing (nothing,
  // if the night light is off). Waits for a preview in flight, so that one
  // can't land after the save and stay on screen.
  function saveNightWarmth(kelvin) {
    root.nightPreview = 0
    root.nightWarmthPending = kelvin
    if (nightPreviewProc.running) root.nightSaveAfterPreview = kelvin
    else root.setNight(["set", "temperature", String(kelvin)])
  }

  // One step warmer (1) or cooler (-1), from the keyboard.
  function stepNightWarmth(delta) {
    var next = Math.max(root.nightWarmest, Math.min(root.nightCoolest, root.nightWarmth - delta * root.nightStep))
    if (next !== root.nightWarmth) root.saveNightWarmth(next)
  }

  // With hours set, the card also says when the night light next changes.
  function nightSummary() {
    if (root.night.until === "") return ""
    return (root.night.on ? "On until " : "Off until ") + root.night.until
  }

  // Milliseconds until the schedule next changes the night light, a moment
  // past it so the change has happened.
  function nightChangeDelay(time) {
    var parts = String(time).split(":")
    var now = new Date()
    var at = new Date(now.getFullYear(), now.getMonth(), now.getDate(), Number(parts[0]) || 0, Number(parts[1]) || 0, 3)
    if (at <= now) at.setDate(at.getDate() + 1)
    return at - now
  }

  // An open page shows the schedule's change when it happens.
  Timer {
    interval: root.nightChangeDelay(root.night.until)
    running: root.night.until !== ""
    onTriggered: nightStatusProc.running = true
  }

  Component.onCompleted: {
    refresh()
    nightStatusProc.running = true
  }

  Process {
    id: nightStatusProc
    command: ["karchy-settings-nightlight", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.loadNight(text) }
  }

  Process {
    id: nightProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.loadNight(text) }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.nightError = text.trim()
        // Refused: the slider goes back to the saved warmth.
        if (root.nightError !== "") root.nightWarmthPending = 0
      }
    }
    // The next change starts once this one has stopped, as the display
    // panel queues its brightness.
    onRunningChanged: {
      if (running) return
      var next = root.nightQueued
      root.nightQueued = null
      if (next) root.setNight(next)
    }
  }

  Process {
    id: nightPreviewProc
    property int shown: 0
    onRunningChanged: {
      if (running) return
      if (root.nightSaveAfterPreview > 0) {
        var kelvin = root.nightSaveAfterPreview
        root.nightSaveAfterPreview = 0
        root.setNight(["set", "temperature", String(kelvin)])
      } else if (root.nightPreview > 0 && root.nightPreview !== shown) {
        root.previewNight(root.nightPreview)
      }
    }
  }

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
    explanation: "Settings are remembered for each monitor. A rule for the same monitor in monitors.lua wins over these."
    ConfigFileLink { closes: root.settings; file: ".config/hypr/monitors.lua" }
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

  // Night light: the same switch as the display panel's, plus its hours and
  // warmth. Applies to every monitor.
  Section {
    id: nightCard
    title: "Night light"
    subtitle: root.nightSummary()
    trailing: ToggleSwitch {
      visible: root.night.installed
      checked: root.night.on
      busy: nightProc.running
      accessibleName: "Night light"
      onToggled: root.setNight([root.night.on ? "off" : "on"])
    }

    InlineMessage {
      Layout.fillWidth: true
      kind: "warning"
      text: root.night.installed ? "" : "Night light needs the hyprsunset package, which isn't installed."
    }

    InlineMessage {
      Layout.fillWidth: true
      kind: "info"
      text: root.night.installed && root.night.userConfig
        ? "Your ~/.config/hypr/hyprsunset.conf sets the hours and warmth, so those below have no effect. The switch still works."
        : ""
    }

    GridLayout {
      visible: root.night.installed
      Layout.fillWidth: true
      columns: root.wide ? 2 : 1
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "On a schedule" }
      ToggleSwitch {
        checked: root.night.schedule
        busy: nightProc.running
        accessibleName: "Night light on a schedule"
        onToggled: root.setNight(["set", "schedule", root.night.schedule ? "off" : "on"])
      }

      SettingsLabel { visible: root.night.schedule; text: "Turn on at" }
      NightTimeField {
        visible: root.night.schedule
        setting: "from"
        saved: root.night.from
        Accessible.name: "Turn night light on at"
      }

      SettingsLabel { visible: root.night.schedule; text: "Turn off at" }
      NightTimeField {
        visible: root.night.schedule
        setting: "to"
        saved: root.night.to
        Accessible.name: "Turn night light off at"
      }

      // The command's own sentence: a time it couldn't read, or hours that
      // start and end together. Under the fields, so they stay where they are.
      InlineMessage {
        Layout.columnSpan: root.wide ? 2 : 1
        Layout.fillWidth: true
        kind: "error"
        details: root.nightError
        dismissible: true
        onDismissed: root.nightError = ""
      }

      SettingsLabel { text: "Warmth" }
      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        // Tab reaches the slider; Left and Right move it a step and save.
        Item {
          id: warmth
          readonly property int kelvin: warmthSlider.dragging
            ? root.nightCoolest - Math.round(warmthSlider.liveValue) * root.nightStep
            : root.nightWarmth

          Layout.fillWidth: true
          Layout.maximumWidth: Style.space(320)
          implicitHeight: warmthSlider.implicitHeight + Style.spacing.md
          activeFocusOnTab: true
          Accessible.role: Accessible.Slider
          Accessible.name: "Night light warmth, " + warmth.kelvin + " kelvin"
          Keys.onLeftPressed: root.stepNightWarmth(LayoutMirroring.enabled ? 1 : -1)
          Keys.onRightPressed: root.stepNightWarmth(LayoutMirroring.enabled ? -1 : 1)

          FocusRing { shown: warmth.activeFocus; control: warmth; radius: Style.radius.control }

          PanelSlider {
            id: warmthSlider
            anchors.fill: parent
            anchors.leftMargin: Style.spacing.sm
            anchors.rightMargin: Style.spacing.sm
            // A window, not a panel: the slider takes the window's colors.
            trackColor: Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
            fillColor: Commons.Color.foreground
            knobColor: Commons.Color.foreground
            minimum: 0
            maximum: (root.nightCoolest - root.nightWarmest) / root.nightStep
            step: 1
            integer: true
            value: (root.nightCoolest - root.nightWarmth) / root.nightStep
            onMoved: function(v) { root.previewNight(root.nightCoolest - Math.round(v) * root.nightStep) }
            onReleased: function(v) { root.saveNightWarmth(root.nightCoolest - Math.round(v) * root.nightStep) }
          }
        }

        Text {
          textFormat: Text.PlainText
          text: Commons.I18n.formatNumber(warmth.kelvin) + " K"
          color: Commons.Color.textSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.features: { "tnum": 1 }
          Layout.preferredWidth: Style.space(64)
        }
      }
    }
  }

  // A time of day, typed as hours and minutes. Saved on Enter or when the
  // field is left; a time the command refuses stays in the field with the
  // reason shown above.
  component NightTimeField: TextField {
    property string setting: ""
    property string saved: ""
    readonly property int revision: root.nightRevision

    Layout.preferredWidth: Style.space(96)
    placeholderText: "20:00"
    inputMethodHints: Qt.ImhTime
    maximumLength: 5
    Component.onCompleted: text = saved
    onRevisionChanged: text = saved
    onEditingFinished: {
      if (text.trim() !== saved) root.setNight(["set", setting, text.trim()])
      else root.nightError = ""
    }
  }

  Repeater {
    model: root.monitors
    delegate: Section {
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
