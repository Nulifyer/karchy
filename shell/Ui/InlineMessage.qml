import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import "Failure.js" as Failure

// A condition that stays until it is resolved, shown where it applies:
// a failed change, a missing program, a warning about the current state.
// (A passing result with no other home is a toast, not this.)
//
//   InlineMessage {
//     kind: "error"
//     text: "Couldn't change the display."
//     details: stderrText          // raw output, behind "Details"
//     actionText: "Try again"; onAction: root.retry()
//     dismissible: true; onDismissed: root.error = ""
//   }
//
// `kind` is "info", "warning" or "error"; the icon and the tint follow it,
// and the text stays the readable text color. For an error, a known failure
// in `details` (a canceled password prompt, a missing program, no network)
// adds a plain sentence after `text`; the raw output stays one click away.
// With no `text`, a command's own last line stands in (karchy's commands
// write theirs for people), and Details appears only when there is more.
// Hidden while both are empty, so a page can keep one bound to its error.
BorderSurface {
  id: root

  property string kind: "info"
  property string text: ""
  property string details: ""
  property string actionText: ""
  property bool dismissible: false
  property color foreground: Commons.Color.foreground
  property string fontFamily: Style.font.family

  signal action()
  signal dismissed()

  readonly property color tone: kind === "error" ? Commons.Color.status.error
    : kind === "warning" ? Commons.Color.status.warning
    : Commons.Color.focus
  readonly property string reason: kind === "error" && text !== "" ? Failure.explain(details) : ""
  readonly property string shownText: text !== "" ? text : Failure.lastLine(details)
  readonly property bool hasMore: details.trim() !== "" && (text !== "" || details.trim().indexOf("\n") !== -1)
  property bool detailsOpen: false
  onDetailsChanged: detailsOpen = false

  visible: shownText !== ""
  Layout.fillWidth: true
  implicitWidth: Style.space(360)
  implicitHeight: column.implicitHeight + Style.spacing.lg * 2
  radius: Style.radius.control
  color: Util.alpha(tone, 0.1)
  borderSpec: Border.flat(Util.alpha(tone, 0.6), Style.border.control)

  Accessible.role: Accessible.AlertMessage
  Accessible.name: messageText.text

  ColumnLayout {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.spacing.lg
    anchors.leftMargin: Style.spacing.xxl
    spacing: Style.spacing.md

    RowLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.lg

      Text {
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Math.round((messageMetrics.height - height) / 2)
        textFormat: Text.PlainText
        text: Icons.glyph(root.kind === "error" ? "ui.error" : root.kind === "warning" ? "ui.warning" : "info")
        color: root.tone
        font.family: Icons.family
        font.pixelSize: Style.font.icon
      }

      Text {
        id: messageText
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: root.shownText + (root.reason !== "" ? " " + root.reason : "")
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap

        FontMetrics { id: messageMetrics; font: messageText.font }
      }

      Button {
        Layout.alignment: Qt.AlignTop
        visible: root.hasMore
        text: root.detailsOpen ? "Hide details" : "Details"
        focusable: true
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.xs
        foreground: root.foreground
        onClicked: root.detailsOpen = !root.detailsOpen
      }

      Button {
        Layout.alignment: Qt.AlignTop
        visible: root.actionText !== ""
        text: root.actionText
        focusable: true
        bordered: true
        fontSize: Style.font.bodySmall
        verticalPadding: Style.spacing.xs
        foreground: root.foreground
        onClicked: root.action()
      }

      PanelActionButton {
        Layout.alignment: Qt.AlignTop
        visible: root.dismissible
        focusable: true
        iconText: Icons.glyph("ui.close")
        tooltipText: "Dismiss"
        foreground: root.foreground
        onClicked: root.dismissed()
      }
    }

    // The command's own words, for a bug report or a search.
    TextEdit {
      visible: root.detailsOpen
      Layout.fillWidth: true
      readOnly: true
      selectByMouse: true
      wrapMode: TextEdit.WrapAnywhere
      textFormat: TextEdit.PlainText
      text: root.details.trim()
      color: Commons.Color.secondaryText(root.foreground)
      selectionColor: Style.selectionFill
      font.family: Style.font.family
      font.pixelSize: Style.font.bodySmall
    }
  }
}
