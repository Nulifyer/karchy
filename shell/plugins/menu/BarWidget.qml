import QtQuick
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "karchy.menu"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The Arch logo (D-47: no Karchy logo glyph).
    text: Icons.glyph("brand.arch")
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("karchy-shell shell toggle karchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
