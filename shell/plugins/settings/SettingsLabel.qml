import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The label beside a control. One width for every page, so controls line up
// as you move between sections.
Text {
  Layout.preferredWidth: Style.spacing.formLabelWidth
  Layout.alignment: Qt.AlignVCenter
  color: Commons.Color.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
}
