import QtQuick
import QtQuick.Shapes
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
    // karchy's mark (Tiles, docs/logo.svg), drawn from its 24-unit paths in
    // the bar's icon colour. No font carries it, so it is a Shape; the bar
    // scales it to the icon size from the path's own bounds.
    iconComponent: Component {
      Shape {
        width: 24
        height: 24
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
          strokeWidth: -1
          fillColor: button.active && button.useActiveColor ? button.activeColor : button.foreground
          PathSvg {
            path: "M2 2 L8.4 2 L8.4 22 L2 22 Z M15.3 2 L22 2 L17.5 10.8 L10.8 10.8 Z M10.8 13.2 L17.5 13.2 L22 22 L15.3 22 Z"
          }
        }
      }
    }
    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.RightButton) root.bar.run("xdg-terminal-exec")
      else root.bar.run("karchy-shell shell toggle karchy.menu '{\"menu\":\"root\"}'")
    }
  }
}
