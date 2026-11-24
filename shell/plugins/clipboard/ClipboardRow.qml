import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// One clipboard entry in the bar panel: a picture when it is one, a line that
// names it, and Pin and Delete at the end. A click pastes it.
//
// The row paints, the panel decides (as ContainerRow does): `hasCursor` and
// `actionCursor` (which trailing control the panel's h/l cursor is on: 0 Pin,
// 1 Delete) come from the panel, and clicks go back as signals.
CursorSurface {
  id: row

  // A row from ClipboardHistory.panelRows.
  property var entry: null
  property int actionCursor: -1
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family

  signal clicked()
  signal pinToggled()
  signal deleteRequested()
  signal pointerEntered()
  signal actionHovered(int index)

  readonly property bool pinned: !!entry && entry.pinned === true
  readonly property string picture: entry && entry.previewImage ? Util.fileUrl(entry.previewImage) : ""
  readonly property color dim: Commons.Color.secondaryText(foreground, surface)

  foreground: Commons.Color.popups.text
  implicitHeight: Math.max(Style.space(30), label.implicitHeight + Style.spacing.rowPaddingX)
  implicitWidth: Style.space(240)

  Accessible.role: Accessible.ListItem
  Accessible.name: entry ? entry.previewText : ""

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.pointerEntered()
    onPositionChanged: InputMode.pointerMoved()
    onClicked: row.clicked()
  }

  SizedImage {
    id: thumbnail
    visible: row.picture !== ""
    anchors.left: parent.left
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: visible ? height : 0
    height: parent.height - Style.space(8)
    url: row.picture
    asynchronous: true
    smooth: true
  }

  Text {
    id: label
    textFormat: Text.PlainText
    anchors.left: thumbnail.right
    anchors.leftMargin: thumbnail.visible ? Style.space(8) : 0
    anchors.right: actions.left
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: row.entry ? row.entry.previewText : ""
    color: row.entry && row.entry.entryType !== "text" ? row.dim : row.foreground
    font.family: row.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
    wrapMode: Text.NoWrap
  }

  Row {
    id: actions
    anchors.right: parent.right
    anchors.rightMargin: Style.space(6)
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(4)

    PanelActionButton {
      // A pinned entry always shows its pin; the rest show theirs under the cursor.
      opacity: row.pinned || row.hasCursor ? 1 : 0
      anchors.verticalCenter: parent.verticalCenter
      iconText: Icons.glyph("ui.pin")
      tooltipText: row.pinned ? I18n.t("clipboard.unpin") : I18n.t("clipboard.pin")
      // Faint until it is pinned, so the pin reads as off or on.
      foreground: row.pinned ? row.foreground : Util.alpha(row.foreground, 0.4)
      hoverColor: row.foreground
      fontFamily: row.fontFamily
      hasCursor: row.actionCursor === 0
      onHovered: function(h) { if (h) row.actionHovered(0) }
      onClicked: row.pinToggled()
    }

    PanelActionButton {
      opacity: row.hasCursor ? 1 : 0
      anchors.verticalCenter: parent.verticalCenter
      iconText: Icons.glyph("ui.delete")
      tooltipText: I18n.t("common.delete")
      foreground: row.dim
      hoverColor: Commons.Color.status.error
      fontFamily: row.fontFamily
      hasCursor: row.actionCursor === 1
      onHovered: function(h) { if (h) row.actionHovered(1) }
      onClicked: row.deleteRequested()
    }
  }
}
