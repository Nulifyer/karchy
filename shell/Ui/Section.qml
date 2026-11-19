import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// A part of a window page: a rule, a small-caps heading, then its content,
// with no box around it. Every page of Settings and of the Updates, VMs and
// Containers windows is built from these (D-114); `Card` is for one item
// among like items (a disk, a key, a connection), not for a part of a page.
//
//   Section {
//     title: "Night light"
//     subtitle: "On until 07:00"          // status, or what the choice costs
//     info: "…"                            // read once, behind an (i)
//     trailing: ToggleSwitch { … }         // at the end of the heading line
//     GridLayout { … }
//   }
//
// Its children stack in a column. With no title it is a rule and its
// content: a group that needs no name (a page's closing actions).
ColumnLayout {
  id: root

  property string title: ""
  property string subtitle: ""
  property string info: ""
  default property alias content: body.data
  property alias trailing: trailingRow.data
  // The gap between the section's own children.
  property int contentSpacing: Style.spacing.lg

  Layout.fillWidth: true
  Layout.topMargin: Style.spacing.lg
  spacing: Style.spacing.lg

  PanelSeparator { Layout.fillWidth: true }

  RowLayout {
    visible: root.title !== "" || trailingRow.implicitWidth > 0
    Layout.fillWidth: true
    spacing: Style.spacing.md

    PanelSectionHeader {
      id: header
      Layout.alignment: Qt.AlignVCenter
      Layout.maximumWidth: Math.max(0, root.width - trailingRow.implicitWidth - Style.space(40))
      text: root.title
      font.capitalization: Font.AllUppercase
      elide: Text.ElideRight
      Accessible.role: Accessible.Heading
    }
    InfoTip {
      visible: root.info !== ""
      Layout.alignment: Qt.AlignVCenter
      subject: root.title
      text: root.info
    }
    Item { Layout.fillWidth: true; implicitHeight: 1 }
    RowLayout {
      id: trailingRow
      spacing: Style.spacing.controlGap
      Layout.alignment: Qt.AlignVCenter
    }
  }

  Text {
    visible: root.subtitle !== ""
    Layout.fillWidth: true
    Layout.maximumWidth: Style.space(620)
    textFormat: Text.PlainText
    text: root.subtitle
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }

  ColumnLayout {
    id: body
    Layout.fillWidth: true
    spacing: root.contentSpacing
  }
}
