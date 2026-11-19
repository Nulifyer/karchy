import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The top of a window page (Settings sections, the Containers and VMs
// windows): the page title, an optional caps status under it (two lines at
// most), an optional icon before it and trailing controls after it.
//
//   PageHeader {
//     title: "Displays"
//     explanation: "Changes apply right away and are remembered…"
//   }
//   PageHeader {
//     iconName: "vms"; title: vm.name; status: "Running · 12% CPU"
//     statusColor: Commons.Color.status.success
//     Button { variant: "primary"; text: "Start" }   // trailing
//   }
//
// Where the page is too narrow for the title and the trailing controls side
// by side, the controls move to a line of their own under the title.
//
// `explanation` is for what people read once: it sits behind an (i) button
// beside the title (click, Enter or Space), never shown by default. Errors,
// warnings and what an action will do never go there.
Item {
  id: root

  property string title: ""
  property string status: ""
  property color statusColor: Commons.Color.textSecondary
  property string iconName: ""
  property color iconColor: Commons.Color.foreground
  property string explanation: ""
  property bool explained: false
  // Trailing controls, right-aligned on the title line.
  default property alias trailing: trailingRow.data

  Layout.fillWidth: true
  implicitWidth: row.implicitWidth
  implicitHeight: column.implicitHeight

  readonly property bool _hasIcon: iconName !== ""
  readonly property bool stacked: trailingRow.implicitWidth > 0 && width < trailingRow.implicitWidth + Style.space(280)

  ColumnLayout {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    spacing: Style.spacing.lg

    GridLayout {
      id: row
      Layout.fillWidth: true
      columns: (root._hasIcon ? 1 : 0) + (root.stacked ? 1 : 2)
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.lg

      Text {
        visible: root._hasIcon
        textFormat: Text.PlainText
        text: root.iconName !== "" ? Icons.glyph(root.iconName) : ""
        color: root.iconColor
        font.family: Icons.family
        font.pixelSize: Style.font.iconHero
        Layout.alignment: Qt.AlignVCenter
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxs

        RowLayout {
          spacing: Style.spacing.sm
          Layout.fillWidth: true

          // Its own width, eliding only when the header can't hold it; the
          // spacer takes the rest, so the (i) sits right after the title.
          Text {
            // One pixel over: given exactly its implicit width, a title whose
            // advance has a fraction elides by a hair ("Netwo…").
            Layout.fillWidth: true
            Layout.maximumWidth: Math.ceil(implicitWidth) + 1
            textFormat: Text.PlainText
            text: root.title
            color: Commons.Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.heading
            font.bold: true
            elide: Text.ElideRight
            Accessible.role: Accessible.Heading
            Accessible.name: text
          }

          PanelActionButton {
            id: explainButton
            visible: root.explanation !== ""
            focusable: true
            iconText: Icons.glyph("ui.explain")
            tooltipText: root.explained ? "Hide the explanation" : "About " + root.title
            foreground: root.explained ? Commons.Color.focus : Commons.Color.textSecondary
            hoverColor: Commons.Color.foreground
            onClicked: root.explained = !root.explained
          }

          Item { Layout.fillWidth: true; implicitHeight: 1 }
        }

        // A status too long for the room beside the trailing controls takes
        // a second line before it is cut.
        Text {
          visible: root.status !== ""
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.status.toUpperCase()
          color: root.statusColor
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.bold: true
          font.letterSpacing: Style.font.labelSpacing
          wrapMode: Text.Wrap
          maximumLineCount: 2
          elide: Text.ElideRight
        }
      }

      RowLayout {
        id: trailingRow
        spacing: Style.spacing.controlGap
        Layout.alignment: Qt.AlignVCenter
        Layout.columnSpan: root.stacked ? row.columns : 1
      }
    }

    Text {
      visible: root.explained && root.explanation !== ""
      Layout.fillWidth: true
      Layout.maximumWidth: Style.space(620)
      textFormat: Text.PlainText
      text: root.explanation
      wrapMode: Text.Wrap
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      lineHeight: 1.15
    }
  }
}
