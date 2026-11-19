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
    // karchy's mark (Tiles, docs/logo.svg): a glyph of karchy Symbols, which
    // follows the icon font (system/fontconfig/50-karchy.conf).
    text: Icons.glyph("brand.karchy")
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("karchy-shell shell toggle karchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
