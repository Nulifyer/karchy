import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

// A section heading inside a page, in the bar panels' style ("OUTPUT",
// "TEXT SIZE"): small caps, after a separator.
ColumnLayout {
  property alias text: header.text
  Layout.fillWidth: true
  Layout.topMargin: Style.spacing.lg
  spacing: Style.spacing.lg

  PanelSeparator { Layout.fillWidth: true }
  PanelSectionHeader {
    id: header
    font.capitalization: Font.AllUppercase
  }
}
