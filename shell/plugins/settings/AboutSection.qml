import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › About: what this machine is and which karchy it runs.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property var facts: []

  Component.onCompleted: {
    factsProc.running = true
    channelProc.running = true
    rendererProc.running = true
  }

  // What draws the desktop (karchy-hw-renderer): the GPU, or the processor
  // when no driver could be used.
  property var renderer: ({})
  Process {
    id: rendererProc
    command: ["karchy-hw-renderer", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.renderer = JSON.parse(text) } catch (e) { root.renderer = {} }
      }
    }
  }
  Process {
    id: warnProc
    onRunningChanged: if (!running) rendererProc.running = true
  }

  // One "label<TAB>value" line per fact.
  Process {
    id: factsProc
    command: ["bash", "-c", [
      "printf 'Computer\\t%s\\n' \"$(cat /etc/hostname)\"",
      "printf 'Kernel\\t%s\\n' \"$(uname -r)\"",
      "printf 'Processor\\t%s\\n' \"$(sed -n 's/^model name[[:space:]]*: //p' /proc/cpuinfo | head -n1)\"",
      "printf 'Memory\\t%s\\n' \"$(free -h --si | awk '/^Mem:/ { print $2 }')\"",
      "printf 'Graphics\\t%s\\n' \"$(lspci 2>/dev/null | sed -n 's/.*\\(VGA\\|3D\\)[^:]*: //p' | head -n1)\"",
      "printf 'karchy\\t%s\\n' \"$(v=$(sed -n 's/^VERSION=//p' /usr/share/karchy/release 2>/dev/null); echo \"${v:-unknown version}\")\""
    ].join("; ")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.facts = text.split("\n")
        .filter(function(line) { return line.indexOf("\t") > 0 })
        .map(function(line) { var parts = line.split("\t"); return { label: parts[0], value: parts.slice(1).join(" ") } })
    }
  }


  // The release channel (D-61), from the [karchy] server file.
  property string channel: ""
  Process {
    id: channelProc
    command: ["bash", "-c", "sed -n 's/^# channel=//p' /etc/pacman.d/karchy-server 2>/dev/null | head -n 1"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.channel = text.trim() }
  }

  PageHeader {
    title: "About"
    explanation: "Release channels: stable gets releases; rc gets release candidates as well, a few days ahead; nightly gets every change to karchy's main branch, for testing. Only karchy's own parts follow the channel; Arch and AUR packages update as usual."
  }

  KeyValueGrid {
    Layout.fillWidth: true
    rows: root.facts.concat(root.renderer.renderer
      ? [{ label: "Drawing with", value: root.renderer.software ? "The processor (" + root.renderer.renderer.split(" (")[0] + ")" : root.renderer.renderer }]
      : [])
  }

  // Drawing on the processor: what it means, the likely cause and the fix.
  InlineMessage {
    Layout.fillWidth: true
    kind: "warning"
    text: root.renderer.software
      ? "The desktop is drawing on the processor, so it will feel slow. " + root.renderer.reason + " " + root.renderer.fix
      : ""
  }

  // The login warning can be turned back on after "Don't show again".
  Toggle {
    Layout.fillWidth: true
    visible: root.renderer.software === true || root.renderer.warn === false
    label: "Warn at login when drawing on the processor"
    checked: root.renderer.warn !== false
    onClicked: {
      warnProc.command = ["karchy-hw-renderer", checked ? "stop-warning" : "warn-again"]
      warnProc.running = true
    }
  }

  RowLayout {
    spacing: Style.spacing.xxl
    SettingsLabel { text: "Release channel" }
    ButtonGroup {
      options: ["stable", "rc", "nightly"]
      value: root.channel
      // Switching installs that channel's karchy packages (older ones too, when
      // leaving nightly), in a terminal so the password prompt and progress
      // show. It changes what is installed, so it asks first; until then the
      // group keeps showing the channel in use.
      onChanged: function(value) {
        if (value === root.channel || !root.settings) return
        var leavingNightly = root.channel === "nightly"
        root.settings.ask("Switch karchy to the " + value + " channel? Its packages are installed now"
          + (leavingNightly ? ", replacing newer nightly ones with older releases." : ".")
          + " The shell restarts when it's done.", "Switch to " + value, function() {
            // Detached: the switch restarts the shell, which ends its own child processes.
            Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", "karchy-channel", "set", value])
          }, false)
        // The group keeps showing the channel in use: it changes once the
        // switch succeeds, and the shell restarts then.
      }
    }
  }

  Button {
    focusable: true
    variant: "primary"
    text: "Update System…"
    onClicked: {
      // Detached: the update restarts the shell, which ends its own child processes.
      Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", "karchy-update"])
    }
  }
}
