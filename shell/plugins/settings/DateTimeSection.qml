import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../panels/clock" as ClockPanel
import "../panels/clock/Model.js" as ClockModel

// Settings › Date & Time: the timezone, automatic time and the bar clock's
// format, through karchy-settings-datetime. The system changes ask for the
// password in the shell's own dialog. The clock's format is the bar widget's
// setting in shell.json, the one a right-click on the clock walks through.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property var settings: null
  property bool loaded: false
  property string timezone: ""
  property bool ntp: false
  property double lastSync: 0
  property string clockFormat: ""
  property bool clockVertical: false
  property var timezones: []
  property string error: ""
  property string errorTitle: ""
  // Which change is running: "timezone", "ntp", "sync" or "clock".
  property string busy: ""
  property date now: new Date()

  function refresh() { if (!statusProc.running && !changeProc.running) statusProc.running = true }

  function load(text) {
    try {
      var status = JSON.parse(text)
      root.timezone = status.timezone || ""
      root.ntp = status.ntp === true
      root.lastSync = Number(status.lastSync || 0) * 1000
      root.clockFormat = status.clock ? String(status.clock.format || "") : ""
      root.clockVertical = !!(status.clock && status.clock.vertical)
      root.loaded = true
      root.now = new Date()
      // A dropdown keeps the choice it was given; one that was refused or
      // canceled goes back to what the system has.
      zoneDropdown.value = root.timezone
      clockDropdown.value = root.clockFormat
    } catch (e) {}
  }

  function change(what, args, title) {
    if (changeProc.running) return
    root.error = ""
    root.errorTitle = title
    root.busy = what
    changeProc.command = ["karchy-settings-datetime"].concat(args)
    changeProc.running = true
  }

  // A format as the clock would show this moment: "Thursday 14:32".
  function sample(format) {
    var week = ClockModel.isoWeekLiteral(root.now.getFullYear(), root.now.getMonth(), root.now.getDate())
    return root.now.toLocaleString(Qt.locale(Commons.I18n.formatLocale), String(format).replace(/ww/g, week)).replace(/\n/g, " ")
  }

  function agoText(then) {
    if (!(then > 0)) return "Not yet"
    var minutes = Math.round((root.now.getTime() - then) / 60000)
    if (minutes < 1) return "Just now"
    if (minutes < 60) return minutes + " min ago"
    if (minutes < 24 * 60) return Math.round(minutes / 60) + " h ago"
    return Qt.formatDate(new Date(then), "d MMM yyyy")
  }

  // The presets a right-click on the clock walks through, and the format in
  // use when it is a hand-written one.
  readonly property var clockOptions: {
    var presets = ClockModel.clockFormats(root.clockVertical)
    var options = presets.map(function(format) { return { value: format, label: root.sample(format) } })
    if (root.clockFormat !== "" && presets.indexOf(root.clockFormat) < 0)
      options.push({ value: root.clockFormat, label: root.sample(root.clockFormat) + " (your own format)" })
    return options
  }

  Component.onCompleted: {
    refresh()
    zonesProc.running = true
  }

  ClockPanel.WallClock {
    step: 60000
    onDateChanged: root.now = date
  }

  Process {
    id: statusProc
    command: ["karchy-settings-datetime", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: zonesProc
    command: ["karchy-settings-datetime", "timezones"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.timezones = text.split("\n").filter(function(zone) { return zone !== "" })
    }
  }

  // A change prints the new status on success and its reason on stderr.
  Process {
    id: changeProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector {
      waitForEnd: true
      // A dismissed password dialog is the person's own choice, not an error.
      onStreamFinished: root.error = text.trim() === "Canceled." ? "" : text.trim()
    }
    onExited: {
      root.busy = ""
      // A refused change leaves the controls on what the system has.
      root.refresh()
    }
  }

  PageHeader {
    title: "Date & Time"
    explanation: "Changing the timezone or automatic time asks for your password. A clock format of your own goes in shell.json, as the format of karchy.clock."
    ConfigFileLink { closes: root.settings; file: ".config/karchy/shell.json" }
  }

  InlineMessage {
    kind: "error"
    text: root.error !== "" ? root.errorTitle : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  GridLayout {
    Layout.fillWidth: true
    columns: 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.lg

    SettingsLabel { text: "Now" }
    Text {
      Layout.fillWidth: true
      textFormat: Text.PlainText
      // 12-hour when the bar's clock is, so the two never disagree.
      text: root.now.toLocaleString(Qt.locale(Commons.I18n.formatLocale),
        "dddd d MMMM yyyy, " + (/AP/i.test(root.clockFormat.replace(/'[^']*'?/g, "")) ? "h:mm AP" : "HH:mm"))
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.features: { "tnum": 1 }
      elide: Text.ElideRight
    }

    SettingsLabel { text: "Timezone" }
    SearchableDropdown {
      id: zoneDropdown
      Layout.fillWidth: true
      Layout.maximumWidth: Style.space(320)
      showLabel: false
      enabled: root.busy === ""
      value: root.timezone
      options: root.timezones.length > 0 ? root.timezones : (root.timezone !== "" ? [root.timezone] : [])
      onChanged: function(value) { root.change("timezone", ["timezone", value], "Couldn't change the timezone.") }
    }

    SettingRow {
      Layout.columnSpan: 2
      label: "Set time automatically"
      checked: root.ntp
      busy: root.busy === "ntp"
      warning: true
      note: root.loaded && !root.ntp ? "The clock drifts while this is off." : ""
      onToggled: root.change("ntp", ["ntp", checked ? "off" : "on"], "Couldn't change automatic time.")
    }

    SettingsLabel { visible: root.ntp; text: "Last synced" }
    RowLayout {
      visible: root.ntp
      Layout.fillWidth: true
      spacing: Style.spacing.xxl
      Text {
        textFormat: Text.PlainText
        text: root.agoText(root.lastSync)
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
      Button {
        focusable: true
        bordered: true
        text: "Sync now"
        busy: root.busy === "sync"
        enabled: root.busy === "" || root.busy === "sync"
        onClicked: root.change("sync", ["sync"], "Couldn't set the clock from the network.")
      }
      Item { Layout.fillWidth: true; implicitHeight: 1 }
    }
  }

  Section {
    title: "Bar clock"
    info: "A right-click on the clock walks through the same formats."

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.lg

      SettingsLabel { text: "Shows" }
      Dropdown {
        id: clockDropdown
        Layout.fillWidth: true
        Layout.maximumWidth: Style.space(320)
        showLabel: false
        value: root.clockFormat
        options: root.clockOptions
        onChanged: function(value) { root.change("clock", ["clock", value], "Couldn't change the clock's format.") }
      }
    }
  }
}
