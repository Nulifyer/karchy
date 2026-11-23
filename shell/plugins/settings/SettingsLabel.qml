import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// The label beside a control. One width for every page, so controls line up
// as you move between sections, and a control's height, so a row that shows
// only text keeps the pitch of the rows around it.
Text {
  Layout.preferredWidth: Style.spacing.formLabelWidth
  Layout.minimumHeight: Style.spacing.controlHeight
  Layout.alignment: Qt.AlignVCenter
  verticalAlignment: Text.AlignVCenter
  color: Commons.Color.foreground
  font.family: Style.font.family
  font.pixelSize: Style.font.body
  elide: Text.ElideRight
}
