import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// One container, as the bar panel lists it and the window's sidebar does: its
// state icon in its status color, its name, the status line, and the run
// switch (with "Open <port>" beside it while it runs and publishes a port,
// where `showOpen`).
//
// The row paints, the host decides: `hasCursor` (keyboard or pointer),
// `current` (the container the window shows) and `actionCursor` (which
// trailing control the panel's h/l cursor is on: 0 the first shown, 1 the
// next) come from the host, and clicks come back as signals.
CursorSurface {
  id: row

  property var container: null
  // The action under way ("Stopping…"), or "".
  property string busyText: ""
  property bool showOpen: true
  property int actionCursor: -1
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family

  signal clicked()
  signal powerToggled()
  signal openRequested()
  signal pointerEntered()
  signal actionHovered(int index)

  readonly property bool isRunning: Model.isRunning(container)
  readonly property bool openShown: showOpen && isRunning && !!container && container.ports && container.ports.length > 0
  readonly property string role: Model.statusRole(container)
  readonly property color statusColor: role === "success" ? Commons.Color.status.success
    : role === "warning" ? Commons.Color.status.warning
    : Commons.Color.secondaryText(foreground, surface)

  foreground: Commons.Color.popups.text
  implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX
  implicitWidth: Style.space(240)

  Accessible.role: Accessible.ListItem
  Accessible.name: container ? container.name + ", " + Model.statusLine(container, busyText) : ""

  // The pointer is over the row (a window highlights hover from this; a panel
  // moves its cursor on pointerEntered instead).
  readonly property bool pointerOver: rowMouse.containsMouse

  MouseArea {
    id: rowMouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: row.pointerEntered()
    onPositionChanged: InputMode.pointerMoved()
    onClicked: row.clicked()
  }

  Item {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(6)
    implicitHeight: Math.max(stateIcon.implicitHeight, info.implicitHeight, actions.implicitHeight)

    Text {
      id: stateIcon
      textFormat: Text.PlainText
      text: row.container ? Icons.glyph(Model.stateIcon(row.container.state)) : ""
      color: row.statusColor
      font.family: Icons.family
      font.pixelSize: Style.font.icon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Column {
      id: info
      spacing: Style.space(1)
      anchors.left: stateIcon.right
      anchors.leftMargin: Style.space(10)
      anchors.right: actions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        text: row.container ? row.container.name : ""
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        textFormat: Text.PlainText
        text: Model.statusLine(row.container, row.busyText)
        color: row.busyText !== "" ? Commons.Color.status.warning : Commons.Color.secondaryText(row.foreground, row.surface)
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
        width: parent.width
      }
    }

    Row {
      id: actions
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      PanelActionButton {
        visible: row.openShown
        anchors.verticalCenter: parent.verticalCenter
        iconText: Icons.glyph("app.browser")
        tooltipText: row.openShown ? "Open " + Model.portUrl(row.container.ports[0]) : ""
        foreground: row.foreground
        fontFamily: row.fontFamily
        hasCursor: row.actionCursor === 0
        onHovered: function(h) { if (h) row.actionHovered(0) }
        onClicked: row.openRequested()
      }

      ToggleSwitch {
        id: power
        anchors.verticalCenter: parent.verticalCenter
        checked: row.isRunning
        busy: row.busyText !== ""
        foreground: row.foreground
        cursorPad: Style.space(3)
        // The host's cursor reaches it (h/l in the panel); in the window the
        // list is one Tab stop and the page has the same action.
        focusable: false
        hasCursor: row.actionCursor === (row.openShown ? 1 : 0)
        accessibleName: row.container ? row.container.name : ""
        onHovered: function(h) { if (h) row.actionHovered(row.openShown ? 1 : 0) }
        onToggled: row.powerToggled()

        PanelToolTip {
          visible: power.containsMouse
          text: row.isRunning ? "Stop" : "Start"
          fontFamily: row.fontFamily
        }
      }
    }
  }
}
