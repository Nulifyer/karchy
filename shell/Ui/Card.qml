import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// A bordered group on a window page: one feature, one monitor, one container.
// Its children stack in a column with the card's padding around them.
//
//   Card {
//     title: "Docker"; subtitle: "Rootless Podman with the docker command"
//     RowLayout { ... }
//   }
//
// `title`/`subtitle` make the header line; `trailing` items (a switch, a
// button) sit at its end, or on a line under the title where the card is too
// narrow for both. `selected` marks the item the window was opened at.
BorderSurface {
  id: root

  property string title: ""
  property string subtitle: ""
  property string iconName: ""
  property color iconColor: Commons.Color.foreground
  property bool selected: false
  default property alias content: body.data
  property alias trailing: trailingRow.data
  property int spacing: Style.spacing.lg

  Layout.fillWidth: true
  implicitWidth: Style.space(360)
  implicitHeight: body.implicitHeight + Style.spacing.panelPadding * 2
  radius: Style.radius.surface
  color: selected ? Style.selectedFill : "transparent"
  borderSpec: Border.flat(selected ? Commons.Color.focus : Style.normalBorderColor, Style.border.control)

  ColumnLayout {
    id: body
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.panelPadding
    spacing: root.spacing

    GridLayout {
      id: header
      readonly property bool hasIcon: root.iconName !== ""
      readonly property bool stacked: trailingRow.implicitWidth > 0 && body.width < trailingRow.implicitWidth + Style.space(220)
      visible: root.title !== "" || trailingRow.implicitWidth > 0
      Layout.fillWidth: true
      columns: (hasIcon ? 1 : 0) + (stacked ? 1 : 2)
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      Text {
        visible: root.iconName !== ""
        textFormat: Text.PlainText
        text: root.iconName !== "" ? Icons.glyph(root.iconName) : ""
        color: root.iconColor
        font.family: Icons.family
        font.pixelSize: Style.font.iconLarge
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxs
        Text {
          visible: root.title !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.title
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          visible: root.subtitle !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.subtitle
          color: Commons.Color.textSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      RowLayout {
        id: trailingRow
        spacing: Style.spacing.controlGap
        Layout.alignment: Qt.AlignVCenter
        Layout.columnSpan: header.stacked ? header.columns : 1
      }
    }
  }
}
