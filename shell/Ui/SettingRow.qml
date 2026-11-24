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
// `command` is a command or an address the note leads to, on its own line in
// the mono font.
// `Toggle` is the roomier form the bar panels use.
ColumnLayout {
  id: root

  property string label: ""
  property string info: ""
  property string note: ""
  property string command: ""
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
    // As tall as a row with a dropdown or a button, so rows keep one pitch.
    Layout.minimumHeight: Style.spacing.controlHeight
    spacing: Style.spacing.xxl

    Text {
      // The label column, or the label's own width when that is longer; where
      // the row is narrower than both, the label gives way and wraps.
      Layout.fillWidth: true
      Layout.preferredWidth: Math.max(root.labelWidth, Math.ceil(implicitWidth))
      Layout.maximumWidth: Math.max(root.labelWidth, Math.ceil(implicitWidth))
      Layout.minimumWidth: Style.space(60)
      Layout.alignment: Qt.AlignVCenter
      textFormat: Text.PlainText
      text: root.label
      color: root.enabled ? Commons.Color.foreground : Commons.Color.disabledText(Commons.Color.foreground)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      // A label longer than a narrow page takes a second line before it is cut.
      wrapMode: Text.Wrap
      maximumLineCount: 2
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
      flush: true
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

  Text {
    visible: root.command !== ""
    Layout.fillWidth: true
    Layout.maximumWidth: Style.space(620)
    textFormat: Text.PlainText
    text: root.command
    color: Commons.Color.foreground
    font.family: Style.font.mono
    font.pixelSize: Style.font.body
    wrapMode: Text.WrapAnywhere
  }
}
