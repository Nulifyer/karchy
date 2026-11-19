import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Default apps (D-37), through karchy-settings-default-apps. Writes
// ~/.config/mimeapps.list, the same file Thunar's "Set Default Application"
// uses, so both always agree.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window (set by its Loader), which a config file link closes.
  property var settings: null
  property var roles: ({})
  property string error: ""
  readonly property bool wide: width >= Style.space(560)
  readonly property var order: [
    { id: "browser", label: "Web browser" },
    { id: "files", label: "File manager" },
    { id: "terminal", label: "Terminal" },
    { id: "editor", label: "Text editor" },
    { id: "image", label: "Images" },
    { id: "video", label: "Video" },
    { id: "music", label: "Music" },
    { id: "pdf", label: "PDF documents" },
    { id: "archive", label: "Archives" }
  ]

  function refresh() { if (!setProc.running) statusProc.running = true }

  function load(text) {
    try { root.roles = JSON.parse(text).roles || {} } catch (e) {}
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["karchy-settings-default-apps", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
  }

  PageHeader {
    title: "Default apps"
    explanation: "What opens links and files. Thunar's \"Set Default Application\" changes the same list, mimeapps.list."
    ConfigFileLink { closes: root.settings; file: ".config/mimeapps.list" }
  }

  InlineMessage {
    kind: "error"
    text: root.error !== "" ? "Couldn't change the default app." : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  GridLayout {
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    Repeater {
      model: root.order
      delegate: SettingsLabel {
        required property var modelData
        required property int index
        Layout.row: root.wide ? index : index * 2
        Layout.column: 0
        text: modelData.label
      }
    }

    Repeater {
      model: root.order
      delegate: Dropdown {
        required property var modelData
        required property int index
        readonly property var role: root.roles[modelData.id] || { current: "", choices: [] }
        Layout.row: root.wide ? index : index * 2 + 1
        Layout.column: root.wide ? 1 : 0
        Layout.fillWidth: true
        showLabel: false
        value: role.current
        options: role.choices.length > 0
          ? role.choices.map(function(c) { return { value: c.id, label: c.name } })
          : [{ value: "", label: "No app installed for this" }]
        onChanged: function(value) {
          if (value === "" || value === role.current) return
          root.error = ""
          setProc.command = ["karchy-settings-default-apps", "set", modelData.id, value]
          setProc.running = true
        }
      }
    }
  }
}
