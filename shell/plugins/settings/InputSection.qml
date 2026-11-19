import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Input: keyboard, mouse and touchpad, through karchy-settings-input.
// Only what is changed here is saved; everything else follows karchy's defaults.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property var values: ({})
  property var saved: ({})
  property bool touchpad: false
  property string error: ""
  readonly property bool wide: width >= Style.space(560)

  function refresh() { if (!setProc.running) statusProc.running = true }

  function load(text) {
    try {
      var status = JSON.parse(text)
      root.values = status.values || {}
      root.saved = status.saved || {}
      root.touchpad = status.touchpad === true
    } catch (e) {}
  }

  function apply(args) {
    root.error = ""
    setProc.command = ["karchy-settings-input"].concat(args)
    setProc.running = true
  }

  function set(setting, value) { root.apply(["set", setting, String(value)]) }

  function resetAll() {
    if (Object.keys(root.saved).length === 0) return
    root.apply(["reset", "all"])
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["karchy-settings-input", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
  }

  PageHeader {
    title: "Input"
    explanation: "A setting in input.lua wins over the one here. Keybindings are in bindings.lua."
    ConfigFileLink { closes: root.settings; file: ".config/hypr/input.lua" }
    ConfigFileLink { closes: root.settings; file: ".config/hypr/bindings.lua" }
  }

  InlineMessage {
    kind: "error"
    text: root.error !== "" ? "Couldn't change the input setting." : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  SettingsHeader { text: "Keyboard" }

  GridLayout {
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Compose key" }
    Dropdown {
      Layout.fillWidth: true
      showLabel: false
      value: root.values.compose || "shift-caps"
      options: [
        { value: "shift-caps", label: "Shift + Caps Lock" },
        { value: "caps", label: "Caps Lock" },
        { value: "ralt", label: "Right Alt" },
        { value: "menu", label: "Menu" },
        { value: "none", label: "None" }
      ]
      onChanged: function(value) { root.set("compose", value) }
    }

    SettingsLabel { text: "Key repeat rate" }
    ButtonGroup {
      options: [{ value: "25", label: "Slow" }, { value: "40", label: "Normal" }, { value: "60", label: "Fast" }, { value: "80", label: "Fastest" }]
      value: String(root.values.repeatRate)
      onChanged: function(value) { root.set("repeatRate", value) }
    }

    SettingsLabel { text: "Delay before repeat" }
    ButtonGroup {
      options: [{ value: "200", label: "Short" }, { value: "250", label: "Normal" }, { value: "400", label: "Long" }, { value: "600", label: "Longest" }]
      value: String(root.values.repeatDelay)
      onChanged: function(value) { root.set("repeatDelay", value) }
    }

    SettingRow {
      Layout.columnSpan: root.wide ? 2 : 1
      label: "Num Lock at startup"
      checked: root.values.numlock === true
      onToggled: root.set("numlock", !checked)
    }
  }

  SettingsHeader { text: "Mouse" }

  GridLayout {
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Pointer speed" }
    ButtonGroup {
      options: [{ value: "-0.5", label: "Slowest" }, { value: "-0.25", label: "Slow" }, { value: "0", label: "Normal" }, { value: "0.25", label: "Fast" }, { value: "0.5", label: "Fastest" }]
      value: String(Number(root.values.sensitivity || 0))
      onChanged: function(value) { root.set("sensitivity", value) }
    }

    SettingRow {
      Layout.columnSpan: root.wide ? 2 : 1
      label: "Pointer acceleration"
      info: "Faster movements travel further. Off moves the pointer exactly with the mouse."
      checked: root.values.accelProfile !== "flat"
      onToggled: root.set("accelProfile", checked ? "flat" : "adaptive")
    }

    SettingRow {
      Layout.columnSpan: root.wide ? 2 : 1
      label: "Natural scrolling"
      info: "Content follows the wheel, like a touchscreen."
      checked: root.values.naturalScroll === true
      onToggled: root.set("naturalScroll", !checked)
    }
  }

  SettingsHeader { visible: root.touchpad; text: "Touchpad" }

  ColumnLayout {
    visible: root.touchpad
    Layout.fillWidth: true
    spacing: Style.spacing.md

    SettingRow {
      label: "Tap to click"
      checked: root.values.tapToClick === true
      onToggled: root.set("tapToClick", !checked)
    }
    SettingRow {
      label: "Click with fingers"
      info: "Two fingers right-click and three middle-click, anywhere on the pad."
      checked: root.values.clickfinger === true
      onToggled: root.set("clickfinger", !checked)
    }
    SettingRow {
      label: "Natural scrolling"
      checked: root.values.touchpadNaturalScroll === true
      onToggled: root.set("touchpadNaturalScroll", !checked)
    }
    SettingRow {
      label: "Off while typing"
      checked: root.values.disableWhileTyping === true
      onToggled: root.set("disableWhileTyping", !checked)
    }
  }

  Button {
    focusable: true
    visible: Object.keys(root.saved).length > 0
    Layout.topMargin: Style.spacing.lg
    text: "Back to karchy's defaults"
    bordered: true
    // Drops every input choice saved here, so it asks first.
    onClicked: if (root.settings) root.settings.ask("Go back to karchy's defaults? Every keyboard, mouse and touchpad choice made here is forgotten.",
      "Back to defaults", function() { root.resetAll() })
  }
}
