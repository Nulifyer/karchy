import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

BarIndicator {
  id: root

  property bool recording: false

  active: recording
  activeText: Icons.glyph("record")
  inactiveText: Icons.glyph("record")
  activeTooltipText: I18n.t("bar.stopRecording")
  inactiveTooltipText: I18n.t("bar.screenRecording")

  function refresh() {
    if (!root.bar || statusProc.running) return
    statusProc.command = ["karchy-capture-screenrecording", "--status"]
    statusProc.running = true
  }

  onBarChanged: refresh()
  Component.onCompleted: refresh()

  Connections {
    target: root.indicatorHost
    ignoreUnknownSignals: true
    function onRefreshRequested() { root.refresh() }
  }

  Process {
    id: statusProc
    onExited: function(exitCode) {
      root.recording = exitCode === 0
    }
  }

  onPressed: function() {
    if (root.bar) {
      // Idle, it starts a recording as Alt+Print does (the Capture submenu it
      // used to open was dropped with the menu, D-18).
      root.bar.run(root.recording ? "karchy-capture-screenrecording --stop-recording" : "karchy-capture-screenrecording")
    }
  }
}
