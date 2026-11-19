import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Security: how this computer is unlocked. Your password and the
// drive password, a fingerprint where there is a reader, and a FIDO2 key.
// The page shows the state (karchy-settings-security status) and starts each
// change in a terminal, since every one of them asks for the password, a touch
// or a typed secret. It reads the state again when a window closes, which is
// when the terminal is done.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property bool loaded: false
  property var fingerprint: ({})
  property var fido2: ({})
  property var password: ({})
  property var drive: ({})

  readonly property bool showFingerprint: fingerprint.reader === true || fingerprint.setUp === true || fingerprint.installed === true

  function refresh() { if (!statusProc.running) statusProc.running = true }

  function load(text) {
    try {
      var status = JSON.parse(text)
      root.fingerprint = status.fingerprint || {}
      root.fido2 = status.fido2 || {}
      root.password = status.password || {}
      root.drive = status.drive || {}
      root.loaded = true
    } catch (e) {}
  }

  function inTerminal(command) {
    Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", command])
  }

  // "2026-11-19" as "today" or "19 Nov 2026".
  function changedText(day) {
    var parts = String(day || "").split("-")
    if (parts.length !== 3) return ""
    var date = new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]))
    var today = new Date()
    if (date.toDateString() === today.toDateString()) return "changed today"
    return "changed " + Qt.formatDate(date, "d MMM yyyy")
  }

  Component.onCompleted: refresh()

  Process {
    id: statusProc
    command: ["karchy-settings-security", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  // The terminal a change ran in has closed: show what it left.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event.name) === "closewindow") root.refresh()
    }
  }

  // One thing and its state on a line, its actions at the end.
  component StateRow: RowLayout {
    id: row
    property string label: ""
    property string value: ""
    property string info: ""
    default property alias actions: actionRow.data
    Layout.fillWidth: true
    spacing: Style.spacing.xxl

    SettingsLabel { text: row.label }
    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.sm
      Text {
        Layout.maximumWidth: Math.max(0, row.width - Style.spacing.formLabelWidth - actionRow.implicitWidth - Style.space(90))
        textFormat: Text.PlainText
        text: row.value
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
      InfoTip {
        visible: row.info !== ""
        subject: row.label
        text: row.info
      }
      Item { Layout.fillWidth: true; implicitHeight: 1 }
    }
    RowLayout {
      id: actionRow
      spacing: Style.spacing.controlGap
    }
  }

  PageHeader {
    title: "Security"
    explanation: "Each change opens a terminal, which asks for your password first."
      + (root.loaded && !root.showFingerprint ? " Fingerprint appears here on a computer with a reader." : "")
  }

  Section {
    title: "Passwords"

    StateRow {
      label: "Your password"
      value: (root.password.user || "") + (root.changedText(root.password.changed) !== "" ? ", " + root.changedText(root.password.changed) : "")
      info: root.drive.encrypted === true
        ? "For the lock screen, sudo and password prompts. The drive password is a separate one."
        : "For the login screen, the lock screen, sudo and password prompts."
      Button {
        focusable: true
        bordered: true
        text: "Change…"
        accessibleName: "Change your password"
        onClicked: root.inTerminal("passwd")
      }
    }

    StateRow {
      label: "Drive password"
      value: !root.loaded ? ""
        : root.drive.encrypted !== true ? "Not encrypted"
        : "Encrypted" + (root.drive.others > 0 ? ", and " + root.drive.others + (root.drive.others === 1 ? " other drive" : " other drives") : "")
      info: root.drive.encrypted === true
        ? "Asked when the computer starts. Other encrypted drives that open with the same password are offered the new one."
        : "The system disk was installed without encryption, so there is no drive password. The login screen asks for your password instead."
      Button {
        visible: root.drive.encrypted === true
        focusable: true
        bordered: true
        text: "Change…"
        accessibleName: "Change the drive password"
        onClicked: root.inTerminal("karchy-drive-password")
      }
    }
  }

  Section {
    visible: root.showFingerprint
    title: "Fingerprint"
    info: "Unlocks the lock screen and answers password prompts from apps. sudo in a terminal and the login screen keep asking for the password."

    StateRow {
      label: "Fingerprint"
      value: root.fingerprint.setUp === true ? "Set up"
        : root.fingerprint.reader !== true ? "No reader found"
        : "Not set up"
      Button {
        visible: root.fingerprint.reader === true
        focusable: true
        bordered: true
        text: root.fingerprint.setUp === true ? "Set up again…" : "Set up…"
        accessibleName: root.fingerprint.setUp === true ? "Set up the fingerprint again" : "Set up a fingerprint"
        onClicked: root.inTerminal("karchy-setup-security-fingerprint")
      }
      Button {
        visible: root.fingerprint.setUp === true || root.fingerprint.installed === true
        focusable: true
        bordered: true
        variant: "destructive"
        text: "Remove"
        accessibleName: "Remove the fingerprint"
        onClicked: if (root.settings) root.settings.ask(
          "Remove your fingerprint? The lock screen and password prompts ask for your password again.",
          "Remove fingerprint", function() { root.inTerminal("karchy-remove-security-fingerprint") })
      }
    }
  }

  Section {
    title: "Security key"
    info: "A FIDO2 key, such as a YubiKey. A touch of it answers sudo and password prompts from apps; the password keeps working."

    StateRow {
      label: "FIDO2 key"
      value: !root.loaded ? "" : root.fido2.setUp === true ? "Set up" : "Not set up"
      Button {
        visible: root.loaded && root.fido2.setUp !== true
        focusable: true
        bordered: true
        text: "Set up…"
        accessibleName: "Set up a FIDO2 key"
        onClicked: root.inTerminal("karchy-setup-security-fido2")
      }
      Button {
        visible: root.fido2.setUp === true
        focusable: true
        bordered: true
        variant: "destructive"
        text: "Remove"
        accessibleName: "Remove the FIDO2 key"
        onClicked: if (root.settings) root.settings.ask(
          "Remove the FIDO2 key? sudo and password prompts ask for your password only.",
          "Remove key", function() { root.inTerminal("karchy-remove-security-fido2") })
      }
    }
  }
}
