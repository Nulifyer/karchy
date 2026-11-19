import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// A switch as one compact line of a settings page: the label in the form's
// label column, the switch where the other controls start, and an optional
// (i) for what people read once.
//
//   SettingRow {
//     label: "Natural scrolling"
//     info: "Content follows the wheel, like a touchscreen."
//     checked: root.values.naturalScroll === true
//     onToggled: root.set("naturalScroll", !checked)
//   }
//
// `note` is one short line under the row for what the person must know to
// choose: a consequence, a warning (`warning: true`), why the setting has no
// effect. Show it only while it applies; never put those behind `info`.
// `Toggle` is the roomier form the bar panels use.
ColumnLayout {
  id: root

  property string label: ""
  property string info: ""
  property string note: ""
  property bool warning: false
  property bool checked: false
  property bool busy: false
  // The label column's width; a longer label takes what it needs.
  property real labelWidth: Style.spacing.formLabelWidth

  signal toggled()

  function focusSwitch() { toggle.forceActiveFocus() }

  Layout.fillWidth: true
  spacing: Style.spacing.sm

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.xxl

    Text {
      Layout.preferredWidth: Math.max(root.labelWidth, Math.ceil(implicitWidth))
      Layout.maximumWidth: Math.max(root.labelWidth, root.width - toggle.width - Style.space(60))
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.enabled ? Commons.Color.foreground : Commons.Color.disabledText(Commons.Color.foreground)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight

      // The label is part of the switch's target.
      MouseArea {
        anchors.fill: parent
        enabled: root.enabled && !root.busy
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
      }
    }

    ToggleSwitch {
      id: toggle
      Layout.alignment: Qt.AlignVCenter
      // Its focus ring's room sits outside the track; the track lines up
      // with the controls above and below.
      Layout.leftMargin: -cursorPad
      accessibleName: root.label
      checked: root.checked
      busy: root.busy
      onToggled: root.toggled()
    }

    InfoTip {
      visible: root.info !== ""
      Layout.alignment: Qt.AlignVCenter
      subject: root.label
      text: root.info
    }

    Item { Layout.fillWidth: true; implicitHeight: 1 }
  }

  Text {
    visible: root.note !== ""
    Layout.fillWidth: true
    Layout.maximumWidth: Style.space(620)
    textFormat: Text.PlainText
    text: root.note
    color: root.warning ? Commons.Color.status.warning : Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.Wrap
  }
}
