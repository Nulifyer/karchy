import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// One horizontal bar on Settings › Storage: how much of something there is,
// as a share (0 to 1) of the row's width.
//
//   StorageMeter { value: 0.35 }                       used space in its track
//   StorageMeter { value: 1; track: false; fillColor: … }   a bare length
//   StorageMeter { value: 0.77; mark: true }           a dashed line with a
//                                                      tick: where the disk ends
//
// Rows that are compared sit under each other with the same width, so their
// lengths can be read against one another.
Item {
  id: root

  property real value: 0
  property color fillColor: Commons.Color.accent
  // Draw the outline the fill sits in.
  property bool track: true
  // Draw a measuring line with a tick at `value` instead of a bar.
  property bool mark: false

  readonly property real share: Math.max(0, Math.min(1, isFinite(value) ? value : 0))

  Layout.fillWidth: true
  implicitWidth: Style.space(160)
  implicitHeight: Style.space(12)

  Rectangle {
    visible: !root.mark
    anchors.fill: parent
    color: "transparent"
    border.width: root.track ? Style.border.control : 0
    border.color: Style.normalBorderColor

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      // A hair of fill for anything above nothing, so "a little" shows.
      width: root.share <= 0 ? 0 : Math.max(Style.space(2), Math.round(parent.width * root.share))
      color: root.fillColor
    }
  }

  Row {
    visible: root.mark
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width
    spacing: Style.space(3)
    clip: true
    Repeater {
      model: root.mark ? Math.ceil(root.width / Style.space(6)) : 0
      Rectangle {
        width: Style.space(3)
        height: Math.max(1, Style.space(1))
        color: Style.normalBorderColor
      }
    }
  }

  Rectangle {
    visible: root.mark
    x: Math.min(parent.width - width, Math.round(parent.width * root.share))
    width: Math.max(1, Style.space(1))
    height: parent.height
    color: Commons.Color.textSecondary
  }
}
