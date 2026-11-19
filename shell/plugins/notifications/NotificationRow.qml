import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Store.js" as Store
import "Markup.js" as Markup

// One notification in the notifications panel: who sent it and when, the
// summary, the body (two lines until unfolded), its buttons when it has any,
// and behind the ⋯ button what its app's notifications do.
//
// The row paints, the panel decides (as VmRow does): `hasCursor` and
// `actionCursor` (the control the keyboard is on, from `controls`) come from
// the panel, and clicks go back as signals. `readOnly` is the history view:
// text only.
CursorSurface {
  id: row

  property var entry: null
  property string label: ""
  property bool system: false
  property var deeds: []
  property bool opens: false
  property bool isNew: false
  property bool unfolded: false
  property bool menuOpen: false
  property bool confirmingOff: false
  property string mode: "allow"
  property string ageText: ""
  property bool readOnly: false
  property string actionCursor: ""
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family

  signal pointerEntered()
  signal controlHovered(string control)
  signal triggered(string control)

  readonly property bool redacted: Store.redacted(entry)
  readonly property string summary: redacted ? I18n.t("notifications.redactedSummary") : String((entry && entry.summary) || "")
  readonly property string body: redacted ? I18n.t("notifications.redactedBody") : Markup.oneLine(entry ? entry.body : "")
  readonly property string appName: system ? I18n.t("notifications.system") : label
  // There is more text than the row shows, or it is all out.
  readonly property bool unfolds: summaryText.truncated || bodyText.truncated || unfolded
  readonly property bool hasMenu: !readOnly && !system
  readonly property color dim: Commons.Color.secondaryText(foreground, surface)

  // What Left and Right walk through, in the order they are drawn. "main" is
  // the row itself.
  readonly property var controls: {
    var list = ["main"]
    if (unfolds) list.push("unfold")
    if (hasMenu) list.push("menu")
    if (!readOnly) list.push("dismiss")
    for (var i = 0; i < deeds.length; i++) list.push("deed:" + i)
    if (menuOpen && !confirmingOff) list.push("mode:allow", "mode:silent", "mode:off", "settings")
    if (confirmingOff) list.push("off:cancel", "off:confirm")
    return list
  }

  foreground: Commons.Color.popups.text
  implicitHeight: content.implicitHeight + Style.spacing.lg * 2
  implicitWidth: Style.space(240)

  Accessible.role: Accessible.ListItem
  Accessible.name: appName + ", " + summary + (body !== "" ? ", " + body : "") + ", " + ageText

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    cursorShape: row.opens || row.unfolds ? Qt.PointingHandCursor : Qt.ArrowCursor
    onEntered: row.pointerEntered()
    onPositionChanged: InputMode.pointerMoved()
    onClicked: function(mouse) {
      if (mouse.button === Qt.RightButton) { if (row.hasMenu) row.triggered("menu") }
      else row.triggered("main")
    }
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(6)
    spacing: Style.space(2)

    Item {
      width: parent.width
      height: Math.max(appText.implicitHeight, buttons.implicitHeight)

      // New since the panel was last opened.
      Rectangle {
        id: newMark
        visible: row.isNew
        width: Style.space(6)
        height: width
        radius: Style.cornerRadius > 0 ? width / 2 : 0
        color: Commons.Color.accent
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      // The `label` type role, as the panels' section headers.
      Text {
        id: appText
        textFormat: Text.PlainText
        text: row.appName
        color: row.dim
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.font.labelSpacing
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.leftMargin: row.isNew ? newMark.width + Style.spacing.md : 0
        anchors.right: buttons.left
        anchors.rightMargin: Style.spacing.lg
        anchors.verticalCenter: parent.verticalCenter
      }

      Row {
        id: buttons
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          rightPadding: Style.spacing.md
          text: row.ageText
          color: row.dim
          font.family: row.fontFamily
          font.pixelSize: Style.font.caption
          font.features: { "tnum": 1 }
        }

        PanelActionButton {
          visible: row.unfolds
          anchors.verticalCenter: parent.verticalCenter
          iconText: Icons.glyph(row.unfolded ? "ui.chevron.up" : "ui.chevron.down")
          tooltipText: I18n.t(row.unfolded ? "notifications.showLess" : "notifications.showAll")
          foreground: row.foreground
          fontFamily: row.fontFamily
          hasCursor: row.actionCursor === "unfold"
          onHovered: function(h) { if (h) row.controlHovered("unfold") }
          onClicked: row.triggered("unfold")
        }

        PanelActionButton {
          visible: row.hasMenu
          anchors.verticalCenter: parent.verticalCenter
          iconText: Icons.glyph("ui.more")
          tooltipText: I18n.t("notifications.appMenu").arg(row.appName)
          foreground: row.menuOpen ? Commons.Color.accent : row.foreground
          fontFamily: row.fontFamily
          hasCursor: row.actionCursor === "menu"
          onHovered: function(h) { if (h) row.controlHovered("menu") }
          onClicked: row.triggered("menu")
        }

        PanelActionButton {
          visible: !row.readOnly
          anchors.verticalCenter: parent.verticalCenter
          iconText: Icons.glyph("ui.close")
          tooltipText: I18n.t("notifications.dismiss")
          foreground: row.foreground
          fontFamily: row.fontFamily
          hasCursor: row.actionCursor === "dismiss"
          onHovered: function(h) { if (h) row.controlHovered("dismiss") }
          onClicked: row.triggered("dismiss")
        }
      }
    }

    Text {
      id: summaryText
      visible: text !== ""
      width: parent.width - Style.space(4)
      textFormat: Text.PlainText
      text: row.summary
      color: row.foreground
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      font.bold: row.isNew
      elide: Text.ElideRight
      wrapMode: row.unfolded ? Text.Wrap : Text.NoWrap
      maximumLineCount: row.unfolded ? 6 : 1
    }

    Text {
      id: bodyText
      visible: text !== ""
      width: parent.width - Style.space(4)
      textFormat: Text.PlainText
      text: row.body
      color: row.dim
      font.family: row.fontFamily
      font.pixelSize: Style.font.bodySmall
      wrapMode: Text.Wrap
      elide: Text.ElideRight
      maximumLineCount: row.unfolded ? 40 : 2
    }

    // The notification's own buttons.
    Flow {
      visible: row.deeds.length > 0
      width: parent.width - Style.space(4)
      topPadding: Style.spacing.md
      spacing: Style.spacing.md

      Repeater {
        model: row.deeds
        Button {
          required property var modelData
          required property int index
          text: modelData.label
          bordered: true
          foreground: row.foreground
          fontFamily: row.fontFamily
          hasCursor: row.actionCursor === "deed:" + index
          onHovered: function(h) { if (h) row.controlHovered("deed:" + index) }
          onClicked: row.triggered("deed:" + index)
        }
      }
    }

    // What this app's notifications do: the same three choices as Settings.
    Text {
      visible: row.menuOpen && !row.confirmingOff
      width: parent.width - Style.space(4)
      topPadding: Style.spacing.lg
      textFormat: Text.PlainText
      text: I18n.t("notifications.appMenu").arg(row.label)
      color: row.dim
      font.family: row.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }

    Flow {
      visible: row.menuOpen && !row.confirmingOff
      width: parent.width - Style.space(4)
      topPadding: Style.spacing.sm
      spacing: Style.spacing.md

      ButtonGroup {
        id: modes
        readonly property var names: ["allow", "silent", "off"]
        focusable: false
        options: [
          { value: "allow", label: I18n.t("notifications.modeAllow"), tooltip: I18n.t("notifications.modeAllowHint") },
          { value: "silent", label: I18n.t("notifications.modeSilent"), tooltip: I18n.t("notifications.modeSilentHint") },
          { value: "off", label: I18n.t("notifications.modeOff"), tooltip: I18n.t("notifications.modeOffHint") }
        ]
        value: row.mode
        cursorIndex: row.actionCursor.indexOf("mode:") === 0 ? names.indexOf(row.actionCursor.slice(5)) : -1
        foreground: row.foreground
        fontFamily: row.fontFamily
        onChanged: function(value) { row.triggered("mode:" + value) }
        onHovered: function(index, h) { if (h) row.controlHovered("mode:" + names[index]) }
      }

      Button {
        text: I18n.t("notifications.settings")
        foreground: row.foreground
        fontFamily: row.fontFamily
        hasCursor: row.actionCursor === "settings"
        onHovered: function(h) { if (h) row.controlHovered("settings") }
        onClicked: row.triggered("settings")
      }
    }

    // Turning an app off drops what it sends, so it is asked first.
    Column {
      visible: row.confirmingOff
      width: parent.width - Style.space(4)
      topPadding: Style.spacing.lg
      spacing: Style.spacing.md

      Text {
        width: parent.width
        textFormat: Text.PlainText
        text: I18n.t("notifications.turnOffAsk").arg(row.appName)
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        wrapMode: Text.Wrap
      }

      Row {
        spacing: Style.spacing.md

        Button {
          text: I18n.t("common.cancel")
          bordered: true
          foreground: row.foreground
          fontFamily: row.fontFamily
          hasCursor: row.actionCursor === "off:cancel"
          onHovered: function(h) { if (h) row.controlHovered("off:cancel") }
          onClicked: row.triggered("off:cancel")
        }

        Button {
          text: I18n.t("notifications.turnOff")
          variant: "destructive"
          bordered: true
          foreground: row.foreground
          fontFamily: row.fontFamily
          hasCursor: row.actionCursor === "off:confirm"
          onHovered: function(h) { if (h) row.controlHovered("off:confirm") }
          onClicked: row.triggered("off:confirm")
        }
      }
    }
  }
}
