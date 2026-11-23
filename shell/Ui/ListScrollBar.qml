import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// The scrollbar of a list or page that can be longer than its view:
//   ScrollBar.vertical: ListScrollBar {}
// It shows whenever there is more than fits, in the theme's text color.
// Qt's own takes the palette's mid gray, which a dark theme hides, and only
// appears while scrolling, so a list gave no sign that it went on.
ScrollBar {
  id: root

  policy: ScrollBar.AsNeeded
  visible: size < 1.0
  background: null
  contentItem: Rectangle {
    implicitWidth: Style.space(4)
    implicitHeight: Style.space(4)
    radius: width / 2
    color: Util.alpha(Commons.Color.foreground, root.pressed || root.hovered ? 0.55 : 0.28)
  }
}
