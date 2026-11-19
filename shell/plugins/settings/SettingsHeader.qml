import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A section heading inside a page, in the bar panels' style ("OUTPUT",
// "TEXT SIZE"): small caps, after a separator. `info` puts an (i) right
// after the heading for what people read once about the section.
ColumnLayout {
  property alias text: header.text
  property string info: ""
  function focusInfo() { tip.forceActiveFocus() }
  Layout.fillWidth: true
  Layout.topMargin: Style.spacing.lg
  spacing: Style.spacing.lg

  PanelSeparator { Layout.fillWidth: true }
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.md

    PanelSectionHeader {
      id: header
      Layout.alignment: Qt.AlignVCenter
      font.capitalization: Font.AllUppercase
    }
    InfoTip {
      id: tip
      visible: parent.parent.info !== ""
      Layout.alignment: Qt.AlignVCenter
      subject: header.text
      text: parent.parent.info
    }
    Item { Layout.fillWidth: true; implicitHeight: 1 }
  }
}
