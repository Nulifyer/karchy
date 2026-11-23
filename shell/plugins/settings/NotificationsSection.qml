import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Notifications (D-112): Do Not Disturb, and what each app's
// notifications do. Do Not Disturb is the notification service's, read live
// from it (the panel has the same switch). The app list and its choices go
// through karchy-settings-notifications, which keeps them in
// ~/.config/karchy/notifications.json; the service watches that file.
//
// Opened from a notification's "Settings…" (`karchy-settings notifications
// app:signal`) it starts on that app's row.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property var settings: null
  property var target: ({})
  property var apps: []
  property string filter: ""
  property string error: ""

  readonly property var service: settings && settings.shell ? settings.shell.serviceFor("karchy.notifications") : null
  readonly property bool doNotDisturb: service ? service.doNotDisturb === true : false
  // The list is searchable once it is long enough to scroll.
  readonly property bool searchable: apps.length > 8
  readonly property var shownApps: {
    var needle = filter.trim().toLowerCase()
    if (needle === "") return apps
    return apps.filter(function(app) { return app.name.toLowerCase().indexOf(needle) >= 0 })
  }

  function refresh() { if (!setProc.running) statusProc.running = true }

  function load(text) {
    try { root.apps = JSON.parse(text).apps || [] } catch (e) { return }
    Qt.callLater(root.applyTarget)
  }

  // The keyboard starts on the app the page was opened at.
  property bool targetApplied: false
  onTargetChanged: targetApplied = false
  function applyTarget() {
    var id = String((target && target.item) || "")
    if (targetApplied || id === "") return
    for (var i = 0; i < shownApps.length; i++) {
      if (shownApps[i].id !== id) continue
      targetApplied = true
      var item = appRepeater.itemAt(i)
      if (item) item.focusChoice()
      return
    }
  }

  function setMode(app, mode) {
    root.error = ""
    setProc.command = ["karchy-settings-notifications", "set", app.id, mode, app.name]
    setProc.running = true
  }

  Component.onCompleted: refresh()

  // A choice made in the panel shows here too.
  Connections {
    target: root.service
    function onAppRulesChanged() { root.refresh() }
    function onSendersChanged() { root.refresh() }
  }

  Process {
    id: statusProc
    command: ["karchy-settings-notifications", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: setProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
  }

  PageHeader {
    title: "Notifications"
    explanation: "Allow: a popup, then the notification waits in the panel until you answer it. Silent: no popup; it waits in the panel's Silent section. Off: the app's notifications are dropped. An app is listed once it has sent a notification."
  }

  InlineMessage {
    kind: "error"
    text: root.error !== "" ? "Couldn't change the setting." : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  SettingRow {
    label: "Do Not Disturb"
    enabled: root.service !== null
    checked: root.doNotDisturb
    // What the choice costs, said only while it applies.
    note: root.doNotDisturb ? "Notifications wait in the panel. Sign-in codes and system alerts still show." : ""
    onToggled: if (root.service) root.service.setDoNotDisturb(!root.doNotDisturb)
  }

  SettingsHeader { text: "Apps" }

  TextField {
    visible: root.searchable
    Layout.fillWidth: true
    placeholderText: "Search apps"
    Accessible.name: "Search apps"
    onTextChanged: root.filter = text
  }

  Text {
    visible: root.shownApps.length === 0
    Layout.fillWidth: true
    textFormat: Text.PlainText
    text: root.apps.length === 0 ? "No app has sent a notification yet."
      : "No app matches “" + root.filter.trim() + "”."
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }

  ColumnLayout {
    visible: root.shownApps.length > 0
    Layout.fillWidth: true
    spacing: Style.spacing.md

    Repeater {
      id: appRepeater
      model: root.shownApps

      RowLayout {
        id: appRow
        required property var modelData
        Layout.fillWidth: true
        spacing: Style.spacing.xxl

        function focusChoice() { choice.forceActiveFocus() }

        // In the form's label column, so the choices line up with the
        // controls above; a long site name keeps both of its ends.
        SettingsLabel {
          text: appRow.modelData.name
          elide: Text.ElideMiddle
        }

        ButtonGroup {
          id: choice
          Accessible.name: appRow.modelData.name
          options: [
            { value: "allow", label: "Allow" },
            { value: "silent", label: "Silent" },
            { value: "off", label: "Off" }
          ]
          value: appRow.modelData.mode
          onChanged: function(value) { root.setMode(appRow.modelData, value) }
        }

        Item { Layout.fillWidth: true; implicitHeight: 1 }
      }
    }
  }
}
