import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// What a list or page shows when it has nothing: why it is empty, and the
// next useful step when there is one.
//
//   EmptyState {
//     iconName: "bluetooth.off"
//     title: "Bluetooth is off"
//     body: "Turn it on to see your devices."
//     actionText: "Turn on Bluetooth"
//     onAction: root.toggleBluetooth()
//   }
//
// `centered` (windows, overlays) stacks a large icon over the text in the
// middle of the space; the default inline form (panels) puts a smaller icon
// beside left-aligned text, so it lines up with the rows it stands in for.
// `actionHasCursor` lets a panel's keyboard cursor land on the action.
Item {
  id: root

  property string iconName: ""
  property string title: ""
  property string body: ""
  property string actionText: ""
  property bool centered: false
  property bool actionHasCursor: false
  property bool actionFocusable: centered
  property color foreground: Commons.Color.foreground
  property color surface: Commons.Color.background
  property string fontFamily: Style.font.family

  signal action()
  signal actionHovered(bool on)

  readonly property color dim: Commons.Color.secondaryText(foreground, surface)

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight + (centered ? Style.spacing.huge * 2 : 0)

  GridLayout {
    id: layout
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: root.centered ? parent.verticalCenter : undefined
    anchors.top: root.centered ? undefined : parent.top
    columns: root.centered ? 1 : 2
    columnSpacing: Style.spacing.xxl
    rowSpacing: root.centered ? Style.spacing.lg : Style.spacing.md

    Text {
      visible: root.iconName !== ""
      Layout.alignment: root.centered ? Qt.AlignHCenter : (Qt.AlignTop | Qt.AlignLeft)
      Layout.rowSpan: root.centered ? 1 : 3
      textFormat: Text.PlainText
      text: root.iconName !== "" ? Icons.glyph(root.iconName) : ""
      color: root.dim
      font.family: Icons.family
      font.pixelSize: root.centered ? Style.font.displayLarge : Style.font.iconLarge
    }

    Text {
      visible: root.title !== ""
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: root.title
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.centered ? Style.font.title : Style.font.body
      font.bold: true
      wrapMode: Text.Wrap
    }

    Text {
      visible: root.body !== ""
      Layout.fillWidth: true
      Layout.maximumWidth: root.centered ? Style.space(420) : -1
      Layout.alignment: root.centered ? Qt.AlignHCenter : Qt.AlignLeft
      textFormat: Text.PlainText
      text: root.body
      horizontalAlignment: root.centered ? Text.AlignHCenter : Text.AlignLeft
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
    }

    Button {
      visible: root.actionText !== ""
      Layout.alignment: root.centered ? Qt.AlignHCenter : Qt.AlignLeft
      Layout.topMargin: Style.spacing.xs
      text: root.actionText
      bordered: true
      focusable: root.actionFocusable
      hasCursor: root.actionHasCursor
      foreground: root.foreground
      fontFamily: root.fontFamily
      onClicked: root.action()
      onHovered: function(on) { root.actionHovered(on) }
    }
  }
}
