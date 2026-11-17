import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Shows while updates are waiting (karchy-update-check writes the state every
// few hours); clicking opens the Updates window.
BarIndicator {
  id: root

  property int packages: 0
  property int aur: 0
  property string release: ""

  active: packages + aur > 0
  activeText: Icons.glyph("update")
  inactiveText: Icons.glyph("update")
  activeTooltipText: {
    var parts = []
    if (release !== "") parts.push("karchy " + release + " is available")
    var total = packages + aur
    parts.push(total + (total === 1 ? " update" : " updates") + " waiting")
    return parts.join("\n")
  }
  inactiveTooltipText: "Up to date"

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/karchy/updates.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var data = JSON.parse(text())
        root.packages = Number(data.packages || 0)
        root.aur = Number(data.aur || 0)
        root.release = String(data.release && data.release.available ? data.release.available : "")
      } catch (e) {
        root.packages = 0
        root.aur = 0
        root.release = ""
      }
    }
  }

  onPressed: function() {
    Quickshell.execDetached(["karchy-updates"])
  }
}
