import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// One VM, as the bar panel lists it and the window's sidebar does: its system
// icon, its name, the status line in its status color, and the run switch
// (with "Show its screen" beside it while it runs, where `showOpen`).
//
// The row paints, the host decides: `hasCursor` (keyboard or pointer),
// `current` (the VM the window shows) and `actionCursor` (which trailing
// control the panel's h/l cursor is on: 0 the first shown, 1 the next) come
// from the host, and clicks come back as signals.
CursorSurface {
  id: row

  property var vm: null
  property var cpuPercent: undefined
  // What the host asked for and is waiting on ("Starting…"), or "".
  property string pending: ""
  property bool showOpen: true
  property int actionCursor: -1
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family

  signal clicked()
  signal powerToggled()
  signal openRequested()
  signal pointerEntered()
  signal actionHovered(int index)

  readonly property bool isRunning: Model.isRunning(vm)
  readonly property bool openShown: showOpen && !!vm && vm.state === "running"
  readonly property string role: Model.statusRole(vm)
  readonly property color statusColor: role === "success" ? Commons.Color.status.success
    : role === "warning" ? Commons.Color.status.warning
    : Commons.Color.secondaryText(foreground, surface)

  foreground: Commons.Color.popups.text
  implicitHeight: content.implicitHeight + Style.spacing.rowPaddingX
  implicitWidth: Style.space(240)

  Accessible.role: Accessible.ListItem
  Accessible.name: vm ? vm.name + ", " + Model.statusLine(vm, cpuPercent, pending) : ""

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
    implicitHeight: Math.max(osIcon.implicitHeight, info.implicitHeight, actions.implicitHeight)

    Text {
      id: osIcon
      textFormat: Text.PlainText
      text: row.vm ? Icons.glyph(Model.osIcon(row.vm.os)) : ""
      color: row.isRunning ? row.foreground : Commons.Color.secondaryText(row.foreground, row.surface)
      font.family: Icons.family
      font.pixelSize: Style.font.icon
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Column {
      id: info
      spacing: Style.space(1)
      anchors.left: osIcon.right
      anchors.leftMargin: Style.space(10)
      anchors.right: actions.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        text: row.vm ? row.vm.name : ""
        color: row.foreground
        font.family: row.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width
      }
      Text {
        textFormat: Text.PlainText
        text: Model.statusLine(row.vm, row.cpuPercent, row.pending)
        color: row.pending !== "" ? Commons.Color.status.warning : row.statusColor
        font.family: row.fontFamily
        font.pixelSize: Style.font.caption
        font.features: { "tnum": 1 }
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
        iconText: Icons.glyph("ui.open-external")
        tooltipText: "Show its screen"
        foreground: row.foreground
        fontFamily: row.fontFamily
        hasCursor: row.actionCursor === 0
        onHovered: function(h) { if (h) row.actionHovered(0) }
        onClicked: row.openRequested()
      }

      ToggleSwitch {
        id: power
        anchors.verticalCenter: parent.verticalCenter
        checked: Model.switchOn(row.vm)
        busy: row.pending !== "" || (!!row.vm && row.vm.state !== "running" && row.vm.state !== "stopped")
        foreground: row.foreground
        cursorPad: Style.space(3)
        // The host's cursor reaches it (h/l in the panel); in the window the
        // list is one Tab stop and the page has the same action.
        focusable: false
        hasCursor: row.actionCursor === (row.openShown ? 1 : 0)
        accessibleName: row.vm ? row.vm.name : ""
        onHovered: function(h) { if (h) row.actionHovered(row.openShown ? 1 : 0) }
        onToggled: row.powerToggled()

        PanelToolTip {
          visible: power.containsMouse
          text: row.isRunning ? "Shut down" : "Start"
          fontFamily: row.fontFamily
        }
      }
    }
  }
}
