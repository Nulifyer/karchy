import QtQuick
import qs.Commons
import qs.Commons as Commons

// Small (22×22 by default) icon button used at the right edge of panel rows
// for inline actions — forget network, confirm passphrase, unpair device,
// etc. Two visual modes are supported via `hoverColor`:
//   - default: hoverColor === foreground → subtle foreground-tint hover
//   - error:   hoverColor === Commons.Color.status.error → red-tint hover for
//              destructive actions like forget/unpair
//
// `enabled` gates clicks and dims the icon to the disabled text role. The component owns its own
// hover state visuals; mouse hover does NOT update any panel cursor state
// here because action buttons are not cursor targets — the row they live
// in is.
//
// `busy`: the button's own action is running (docs/architecture.md, "Busy"):
// the `Spinner` stands where the icon stood, in full color whatever `enabled`
// says, and the button takes no second press.
//
// Set `focusable: true` to make the button keyboard-tabbable with the
// shared hover-cursor/focus tokens. Use this
// in form contexts where Tab walks a list
// of controls; leave it false for the right-edge actions on panel rows
// where the row's CursorSurface owns the keyboard cursor.
//
// Set `hasCursor: true` to have the button render the same hover state as
// mouse hover — so a panel's keyboard cursor lands on it identically.
// Use this when a PanelActionButton is itself the cursor target (rather
// than living inside a CursorSurface row). Emits `hovered(bool)` on
// pointer enter/leave so the panel can update its cursor state to match.
BorderSurface {
  id: root

  property string iconText: ""
  property string tooltipText: ""
  property color foreground: Commons.Color.foreground
  property color hoverColor: foreground
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.icon
  // Whole and odd, so an icon glyph (usually an odd number of pixels wide)
  // has the same space on both sides instead of one pixel more on one side.
  property real size: Math.round(Math.max(Style.spacing.actionButtonSize, fontSize + Style.spacing.sm * 2)) | 1

  property bool focusable: false
  property bool hasCursor: false
  property bool bordered: false
  property bool busy: false

  signal clicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable && enabled

  // Icon-only, so its tooltip is its name.
  Accessible.role: Accessible.Button
  Accessible.name: root.tooltipText
  Accessible.description: root.busy ? Commons.I18n.t("common.busy") : ""
  Accessible.onPressAction: if (root._live) root.clicked()

  Keys.onReturnPressed: if (focusable && root._live) root.clicked()
  Keys.onEnterPressed: if (focusable && root._live) root.clicked()
  Keys.onSpacePressed: if (focusable && root._live) root.clicked()

  implicitWidth: size
  implicitHeight: size
  radius: Style.radius.control

  readonly property bool _live: enabled && !busy
  // Busy is never drawn as disabled; the pointer changes nothing then.
  readonly property bool _shownEnabled: enabled || busy
  // A busy button a caller disabled had the keyboard and gets it back when
  // enabled again (`focus` stays set), so its ring stays meanwhile.
  readonly property bool _showFocusRing: ((focusable && (activeFocus || (busy && !enabled && focus))) || root.hasCursor) && root._shownEnabled
  readonly property bool _hot: ((mouse.containsMouse && !busy) || root.hasCursor) && root._shownEnabled
  readonly property var _borderSpec: (_hot || _showFocusRing) && bordered
    ? Border.controlSpec("hover-cursor", hoverColor, hoverColor)
    : (bordered ? Border.controlSpec("normal", foreground, Commons.Color.accent) : Border.none())

  color: _showFocusRing
    ? Style.focusFillFor(hoverColor, hoverColor)
    : (_hot
      ? Style.hoverFillFor(hoverColor, hoverColor)
      : "transparent")

  FocusRing { shown: root._showFocusRing }
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: Style.duration(60) } }

  Text {
    textFormat: Text.PlainText
    // Snap to whole pixels so the glyph doesn't round away from the fill's center.
    x: Math.round((root.width - width) / 2)
    y: Math.round((root.height - height) / 2)
    visible: !root.busy
    text: root.iconText
    color: root._shownEnabled
      ? (root._hot ? root.hoverColor : root.foreground)
      : Commons.Color.disabledText(root.foreground)
    font.family: Icons.family
    font.pixelSize: root.fontSize
  }

  Spinner {
    visible: root.busy
    anchors.centerIn: parent
    size: root.fontSize
    color: root.foreground
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root._live ? Qt.PointingHandCursor : Qt.ArrowCursor
    enabled: root.enabled
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: {
      if (!root._live) return
      if (root.focusable) root.forceActiveFocus(Qt.MouseFocusReason)
      root.clicked()
    }
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouse.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
  }
}
