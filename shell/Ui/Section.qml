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
//     titleTo: "0.2.0"                     // "karchy 0.1.0 → 0.2.0": what it becomes
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
  // What the titled thing becomes, after an arrow: a release and the next.
  // The arrow is an icon, so it looks the same in every text font.
  property string titleTo: ""
  property string subtitle: ""
  property string info: ""
  default property alias content: body.data
  property alias trailing: trailingRow.data
  // The gap between the section's own children: the gap between a form's
  // rows, so rows keep one pitch whether a grid or the section stacks them.
  property int contentSpacing: Style.spacing.md

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
      Layout.maximumWidth: Math.max(0, root.width - trailingRow.implicitWidth - Style.space(40)
        - (root.titleTo !== "" ? headerArrow.implicitWidth + headerTo.implicitWidth + 2 * parent.spacing : 0))
      text: root.title
      font.capitalization: Font.AllUppercase
      elide: Text.ElideRight
      Accessible.role: Accessible.Heading
      Accessible.name: root.titleTo !== "" ? root.title + " to " + root.titleTo : root.title
    }
    Text {
      id: headerArrow
      visible: root.titleTo !== ""
      Layout.alignment: Qt.AlignVCenter
      topPadding: header.topPadding
      textFormat: Text.PlainText
      text: Icons.glyph("ui.arrow.right")
      color: header.color
      font.family: Icons.family
      font.pixelSize: Style.font.iconSmall
    }
    PanelSectionHeader {
      id: headerTo
      visible: root.titleTo !== ""
      Layout.alignment: Qt.AlignVCenter
      text: root.titleTo
      Accessible.ignored: true
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
