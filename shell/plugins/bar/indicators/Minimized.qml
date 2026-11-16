import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// Shows while windows are minimized (the titlebar − button, Super + Down, Super + M);
// clicking brings one back (karchy-hyprland-window-restore), as the dock did
// in Omarchy.
BarIndicator {
  id: root

  property int minimizedCount: 0

  active: minimizedCount > 0
  activeText: Icons.glyph("window.minimized")
  inactiveText: Icons.glyph("window.minimized")
  activeTooltipText: minimizedCount === 1 ? "1 minimized window" : minimizedCount + " minimized windows"
  inactiveTooltipText: "No minimized windows"

  function refresh() {
    var count = 0
    var windows = Hyprland.toplevels.values
    for (var i = 0; i < windows.length; i++) {
      var workspace = windows[i].workspace
      if (workspace && String(workspace.name) === "special:minimized") count++
    }
    root.minimizedCount = count
  }

  Component.onCompleted: refresh()

  // Hyprland reports moves and closes as events; recount after each one.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event.name)
      if (name.indexOf("movewindow") === 0 || name === "openwindow" || name === "closewindow")
        Qt.callLater(root.refresh)
    }
  }

  onPressed: function() {
    if (root.minimizedCount > 0) Quickshell.execDetached(["karchy-hyprland-window-restore"])
  }
}
