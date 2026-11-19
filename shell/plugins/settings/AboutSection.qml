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
      "printf 'karchy\\t%s\\n' \"$(v=$(sed -n 's/^VERSION=//p' /usr/share/karchy/release 2>/dev/null); echo \"${v:-unknown version}\")\"",
      // The release channel (D-61), changed in the Updates window.
      "c=$(sed -n 's/^# channel=//p' /etc/pacman.d/karchy-server 2>/dev/null | head -n1); [ -n \"$c\" ] && printf 'Release channel\\t%s\\n' \"$c\"; true"
    ].join("; ")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.facts = text.split("\n")
        .filter(function(line) { return line.indexOf("\t") > 0 })
        .map(function(line) { var parts = line.split("\t"); return { label: parts[0], value: parts.slice(1).join(" ") } })
    }
  }


  PageHeader {
    title: "About"
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
  SettingRow {
    visible: root.renderer.software === true || root.renderer.warn === false
    label: "Warn at login when drawing on the processor"
    checked: root.renderer.warn !== false
    onToggled: {
      warnProc.command = ["karchy-hw-renderer", checked ? "stop-warning" : "warn-again"]
      warnProc.running = true
    }
  }

  Button {
    focusable: true
    variant: "primary"
    text: "Updates and Channel…"
    // The Updates window: what's waiting, Install, and the release channel.
    // Settings floats above it, so Settings steps aside.
    onClicked: {
      Quickshell.execDetached(["karchy-updates"])
      if (root.settings) root.settings.close()
    }
  }
}
