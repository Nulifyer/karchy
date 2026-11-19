import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › SSH: the server and who can sign in to it, your own keys, and the
// agent, through karchy-settings-ssh. The server is set up and removed in a
// terminal (a key to authorize, the password), and new keys are made there
// (a passphrase), so the page follows the system rather than the click.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property var settings: null
  property var server: ({})
  property var agent: ({})
  property var authorized: []
  property var keys: []
  property string lastStatus: ""
  property string error: ""
  property string errorTitle: ""
  property string copied: ""
  // What went wrong adding a key, shown under the field it's about.
  property string addError: ""

  readonly property string addValue: addField.text.trim()
  readonly property bool addIsGithub: /^[A-Za-z0-9][A-Za-z0-9-]{0,38}$/.test(addValue)

  function refresh() { if (!statusProc.running && !changeProc.running) statusProc.running = true }

  // The page looks again every few seconds; rebuilding the rows only when
  // something changed keeps the keyboard where it is.
  function load(text) {
    if (text.trim() === "" || text === root.lastStatus) return
    try {
      var status = JSON.parse(text)
      root.lastStatus = text
      root.server = status.server || {}
      root.agent = status.agent || {}
      root.authorized = status.authorized || []
      root.keys = status.keys || []
    } catch (e) {}
  }

  function inTerminal(command) {
    terminalProc.command = ["karchy-launch-floating-terminal-with-presentation", command]
    terminalProc.running = true
  }

  function change(args, title, onDone) {
    root.error = ""
    root.addError = ""
    root.errorTitle = title
    changeProc.onDone = onDone || null
    changeProc.command = ["karchy-settings-ssh"].concat(args)
    changeProc.running = true
  }

  function keyName(key) {
    return key.comment !== "" ? key.comment : (key.name || "Key without a name")
  }

  function shortPrint(key) {
    return key.type + " key, " + key.fingerprint.slice(0, 19) + "…"
  }

  function removeAuthorized(key) {
    var last = root.authorized.length === 1 && root.server.enabled === true
    root.settings.ask(
      "Stop " + root.keyName(key) + " signing in to this computer over SSH?"
        + (last ? " It's the only key, so nobody can sign in until you add one." : ""),
      "Remove key",
      function() { root.change(["authorized", "remove", key.fingerprint], "Couldn't remove the key.") })
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 2000
    repeat: true
    running: root.visible
    onTriggered: root.refresh()
  }

  Timer {
    id: copiedTimer
    interval: 2000
    onTriggered: root.copied = ""
  }

  Process {
    id: statusProc
    command: ["karchy-settings-ssh", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  // A change prints the new status on success and its reason on stderr.
  Process {
    id: changeProc
    property var onDone: null
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() === "") return
        if (root.errorTitle === "Couldn't add the key.") root.addError = text.trim()
        else root.error = text.trim()
      }
    }
    onExited: function(exitCode) {
      if (exitCode === 0 && typeof changeProc.onDone === "function") changeProc.onDone()
    }
  }

  Process { id: terminalProc }

  PageHeader {
    title: "SSH"
    explanation: "The server lets other computers sign in here with a key. Your keys sign you in to servers and GitHub; the agent remembers their passphrases."
  }

  InlineMessage {
    Layout.fillWidth: true
    kind: "error"
    text: root.error !== "" ? root.errorTitle + " " + root.error : ""
    dismissible: true
    onDismissed: root.error = ""
  }

  SettingsHeader { text: "Server" }

  SettingRow {
    label: "SSH server"
    checked: root.server.enabled === true
    warning: root.server.enabled === true && root.server.running !== true
    // What switching it on does, why it isn't working, or how to reach it.
    note: {
      if (root.server.enabled !== true)
        return "Turning it on opens a terminal to authorize a key. Passwords stay off."
      if (root.server.running !== true)
        return "Turned on but not running. Turn it off and on again, or check: systemctl status sshd"
      return "Connect with: " + root.server.connect
        + (root.server.keysOnly === true ? "" : "\nPasswords can sign in too.")
    }
    onToggled: root.inTerminal(checked ? "karchy-remove-security-sshd" : "karchy-setup-security-sshd")
  }

  SettingsHeader {
    visible: root.server.enabled === true || root.authorized.length > 0
    text: "Who can sign in"
  }

  Text {
    visible: root.server.enabled === true && root.authorized.length === 0
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "No keys yet, so nobody can sign in. Add one below."
    color: Commons.Color.status.warning
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.authorized
    delegate: Card {
      required property var modelData
      Layout.fillWidth: true
      title: root.keyName(modelData)
      subtitle: root.shortPrint(modelData)
      trailing: Button {
        focusable: true
        bordered: true
        variant: "destructive"
        text: "Remove"
        accessibleName: "Remove " + root.keyName(modelData)
        onClicked: root.removeAuthorized(modelData)
      }
    }
  }

  RowLayout {
    visible: root.server.enabled === true || root.authorized.length > 0
    Layout.fillWidth: true
    spacing: Style.spacing.md

    TextField {
      id: addField
      Layout.fillWidth: true
      placeholderText: "Paste a public key, or type a GitHub username"
      onTextEdited: root.addError = ""
      onAccepted: addButton.clicked()
    }

    Button {
      id: addButton
      focusable: true
      bordered: true
      enabled: root.addValue !== "" && !changeProc.running
      busy: changeProc.running && root.errorTitle === "Couldn't add the key."
      text: root.addIsGithub ? "Add their GitHub keys" : "Add key"
      onClicked: if (enabled) root.change(["authorized", "add", root.addValue], "Couldn't add the key.",
        function() { addField.text = "" })
    }
  }

  Text {
    visible: root.addError !== ""
    Layout.fillWidth: true
    Layout.topMargin: -Style.spacing.lg
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: root.addError
    color: Commons.Color.status.error
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  SettingsHeader { text: "Your keys" }

  Text {
    visible: root.keys.length === 0
    Layout.fillWidth: true
    wrapMode: Text.WordWrap
    textFormat: Text.PlainText
    text: "No SSH key yet."
    color: Commons.Color.secondaryText(Commons.Color.foreground, Commons.Color.background)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  Repeater {
    model: root.keys
    delegate: Card {
      required property var modelData
      Layout.fillWidth: true
      title: root.keyName(modelData)
      subtitle: "~/.ssh/" + modelData.name + ", " + root.shortPrint(modelData)
        + (modelData.private ? "" : "\nOnly the public half is here.")
      trailing: Button {
        focusable: true
        bordered: true
        text: root.copied === modelData.name ? "Copied" : "Copy public key"
        accessibleName: "Copy the public key of " + root.keyName(modelData)
        onClicked: root.change(["key", "copy", modelData.name], "Couldn't copy the key.", function() {
          root.copied = modelData.name
          copiedTimer.restart()
        })
      }
    }
  }

  Button {
    focusable: true
    bordered: true
    text: "Create a key…"
    onClicked: root.inTerminal("karchy-settings-ssh key new")
  }

  SettingsHeader { text: "Agent" }

  SettingRow {
    label: "SSH agent"
    checked: root.agent.enabled === true
    busy: changeProc.running && root.errorTitle === "Couldn't change the SSH agent."
    // The agent reaches apps through the session's environment, which is set
    // at sign-in.
    warning: root.agent.enabled !== root.agent.inSession
    info: "Asks for a key's passphrase once, with the option to remember it in the keyring."
    note: {
      if (root.agent.enabled === true && root.agent.inSession !== true)
        return "Sign out and back in so every app uses it."
      if (root.agent.enabled !== true && root.agent.inSession === true)
        return "Sign out and back in so apps stop looking for it."
      return ""
    }
    onToggled: root.change(["agent", checked ? "off" : "on"], "Couldn't change the SSH agent.")
  }
}
