import QtQuick
import QtQuick.Shapes
import qs.Commons
import qs.Commons as Commons

// The busy indication: a ring with an arc that turns. The one way the shell
// shows "working on it", so every control that can be busy holds this and
// nothing draws its own (docs/architecture.md, "Busy"; tools/busy-check).
//
//   Spinner { size: Style.font.icon; color: label.color }
//
// It is drawn, not a glyph: the ring stands still and the arc turns about
// the ring's own centre, so it takes the same `size` square in every frame
// and at every display scale. (The icon font's loading glyph is a quarter
// arc stretched to fill its box; turned, it tumbled about a point beside its
// circle's centre.)
//
// It turns only while it is on screen. With reduced motion it stands still:
// the ring and the arc still say "working".
Item {
  id: root

  // The square it takes: an icon's size, so it can stand where one stood.
  property real size: Style.font.icon
  // The color of the text or icon it stands beside or in place of.
  property color color: Commons.Color.foreground
  property bool running: true

  readonly property real _line: Math.max(1.5, Math.round(size / 4) / 2)
  readonly property real _radius: (size - _line) / 2

  implicitWidth: size
  implicitHeight: size

  Accessible.role: Accessible.Indicator
  Accessible.name: Commons.I18n.t("common.busy")

  // The ring: where the arc travels.
  Shape {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeWidth: root._line
      strokeColor: Util.alpha(root.color, 0.25)
      fillColor: "transparent"
      PathAngleArc {
        centerX: root.size / 2
        centerY: root.size / 2
        radiusX: root._radius
        radiusY: root._radius
        startAngle: 0
        sweepAngle: 360
      }
    }
  }

  // The arc, a quarter of the ring, turned as a whole about the centre.
  Shape {
    anchors.centerIn: parent
    width: root.size
    height: root.size
    preferredRendererType: Shape.CurveRenderer
    transformOrigin: Item.Center

    ShapePath {
      strokeWidth: root._line
      strokeColor: root.color
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.size / 2
        centerY: root.size / 2
        radiusX: root._radius
        radiusY: root._radius
        startAngle: -90
        sweepAngle: 90
      }
    }

    RotationAnimation on rotation {
      from: 0
      to: 360
      duration: 900
      loops: Animation.Infinite
      running: root.running && root.visible && !Style.reduceMotion
    }
  }
}
