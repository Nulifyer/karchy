import QtQuick
import qs.Commons
import qs.Commons as Commons

// Labeled toggle row: title + optional description on the left, a
// `ToggleSwitch` on the right. Clicking anywhere on the row emits `clicked()`;
// consumers flip `checked` in response (the component is stateless about the
// actual value so it composes cleanly with model-driven UI).
//
// Cursor and focus styling match the rest of the kit: mouse hover paints the
// hover-cursor fill and border; activeFocus and the panel cursor add the
// FocusRing.
//
// `rounded` is forwarded to the switch, which auto-detects from
// Style.cornerRadius: pill shape when Hyprland corners are rounded, square on
// sharp. Callers can override per-instance.
BorderSurface {
  id: root

  property string label: ""
  property string description: ""
  property bool checked: false
  // The change is under way: the switch pulses and the row takes no clicks.
  property bool busy: false
  // The description reports a condition that needs attention (a trusted
  // network seen behind a different router); drawn in the warning color.
  property bool warning: false

  // A plain row, for a switch that already sits inside a bordered surface (a
  // bar panel): no box of its own, so no card inside a card. It shows its
  // fill and border only under the pointer or the cursor, as list rows do.
  property bool flat: false

  // Panel-cursor flag. Same role as Button.hasCursor:
  // panels with their own keyboard cursor bind this to drive the highlight
  // separately from activeFocus. Visuals use the same hover-cursor tokens.
  property bool hasCursor: false

  // Switch shape follows the theme by default: pill on round, square on sharp.
  // Override per-instance if a caller wants the opposite.
  property bool rounded: Style.cornerRadius > 0

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property string fontFamily: Style.font.family
  property real titleSize: Style.font.subtitle
  property real descriptionSize: Style.font.caption

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: true
  Keys.onReturnPressed: if (!root.busy) root.clicked()
  Keys.onEnterPressed: if (!root.busy) root.clicked()
  Keys.onSpacePressed: if (!root.busy) root.clicked()

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.label
  Accessible.description: root.description
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onToggleAction: if (!root.busy) root.clicked()
  Accessible.onPressAction: if (!root.busy) root.clicked()

  implicitHeight: flat ? Math.max(Style.space(36), content.implicitHeight + Style.spacing.xxl)
    : Math.max(Style.space(54), content.implicitHeight + Style.spacing.huge)
  implicitWidth: Style.space(240)
  radius: Style.radius.control

  readonly property bool _hot: enabled && (hasCursor || mouse.containsMouse)
  readonly property bool _keyboard: activeFocus || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_keyboard || _hot ? "hover-cursor" : "normal", foreground, accent)

  color: flat && !_hot && !_keyboard ? "transparent" : Style.controlFill(activeFocus, _hot, foreground, accent)
  borderSpec: flat && !_hot && !_keyboard ? Border.none() : _borderSpec

  Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

  FocusRing { shown: root._keyboard }

  Row {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: root.borderLeft + Style.spacing.rowPaddingX
    anchors.rightMargin: root.borderRight + Style.spacing.rowPaddingX
    spacing: Style.spacing.rowPaddingX

    Column {
      width: parent.width - track.width - parent.spacing
      spacing: Style.spacing.xs
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        text: root.label
        color: root.enabled ? root.foreground : Commons.Color.disabledText(root.foreground)
        font.family: root.fontFamily
        font.pixelSize: root.flat ? Style.font.body : root.titleSize
        font.bold: !root.flat
        elide: Text.ElideRight
        width: parent.width
      }

      Text {
        textFormat: Text.PlainText
        visible: root.description !== ""
        text: root.description
        color: !root.enabled ? Commons.Color.disabledText(root.foreground)
          : root.warning ? Commons.Color.status.warning
          : Commons.Color.secondaryText(root.foreground)
        font.family: root.fontFamily
        font.pixelSize: root.descriptionSize
        wrapMode: Text.WordWrap
        width: parent.width
      }
    }

    // The row owns the click, so the switch is presentation only here.
    ToggleSwitch {
      id: track
      checked: root.checked
      busy: root.busy
      rounded: root.rounded
      foreground: root.foreground
      accent: root.accent
      interactive: false
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.busy ? Qt.BusyCursor : Qt.PointingHandCursor
    onClicked: if (!root.busy) root.clicked()
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
