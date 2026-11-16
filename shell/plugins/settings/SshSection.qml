import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › SSH: the SSH server and the SSH agent, through karchy-settings-ssh.
// The server is set up and removed in a terminal (a key to authorize, the
// password), so its switch follows the system rather than the click: it turns
// on once the server really is on.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property var settings: null
  property var server: ({})
  property var agent: ({})
  property string error: ""

  function refresh() { if (!statusProc.running && !agentProc.running) statusProc.running = true }

  function load(text) {
    try {
      var status = JSON.parse(text)
      root.server = status.server || {}
      root.agent = status.agent || {}
    } catch (e) {}
  }

  function inTerminal(command) {
    terminalProc.command = ["karchy-launch-floating-terminal-with-presentation", command]
    terminalProc.running = true
  }

  function setAgent(on) {
    root.error = ""
    agentProc.command = ["karchy-settings-ssh", "agent", on ? "on" : "off"]
    agentProc.running = true
  }

  Component.onCompleted: refresh()

  // The terminal reports back only through the system itself, so the page
  // looks again every few seconds while it is shown.
  Timer {
    interval: 2000
    repeat: true
    running: root.visible
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    command: ["karchy-settings-ssh", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  Process {
    id: agentProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
  }

  Process { id: terminalProc }

  PageHeader {
    title: "SSH"
    explanation: "The server lets other computers sign in here with an SSH key. The agent remembers your own keys' passphrases, so ssh and git don't ask every time."
  }

  InlineMessage {
    Layout.fillWidth: true
    kind: "error"
    text: root.error !== "" ? "Couldn't change the SSH agent." : ""
    details: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  SettingsHeader { text: "Server" }

  Toggle {
    Layout.fillWidth: true
    label: "SSH server"
    checked: root.server.enabled === true
    warning: root.server.enabled === true && root.server.running !== true
    description: {
      if (root.server.enabled !== true)
        return "Opens a terminal to authorize your key and turn the server on. Passwords stay off."
      if (root.server.running !== true)
        return "Turned on but not running. Turn it off and on again, or check: systemctl status sshd"
      var who = root.server.keysOnly === true
        ? (root.server.keys === 1 ? "1 authorized key can sign in; passwords are off." : root.server.keys + " authorized keys can sign in; passwords are off.")
        : "Passwords can sign in too."
      return "Connect from another computer with: " + root.server.connect + "\n" + who
    }
    onClicked: root.inTerminal(checked ? "karchy-remove-security-sshd" : "karchy-setup-security-sshd")
  }

  Button {
    visible: root.server.enabled === true
    focusable: true
    bordered: true
    text: "Authorize another key…"
    onClicked: root.inTerminal("karchy-setup-security-sshd")
  }

  SettingsHeader { text: "Agent" }

  Toggle {
    Layout.fillWidth: true
    label: "SSH agent"
    checked: root.agent.enabled === true
    busy: agentProc.running
    // The agent reaches apps through the session's environment, which is set
    // at sign-in.
    warning: root.agent.enabled !== root.agent.inSession
    description: {
      if (root.agent.enabled === true && root.agent.inSession !== true)
        return "Sign out and back in so every app uses it."
      if (root.agent.enabled !== true && root.agent.inSession === true)
        return "Sign out and back in so apps stop looking for it."
      return "Asks for a key's passphrase once, with the option to remember it in the keyring."
    }
    onClicked: root.setAgent(!checked)
  }
}
