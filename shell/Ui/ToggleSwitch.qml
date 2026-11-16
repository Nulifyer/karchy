import QtQuick
import qs.Commons
import qs.Commons as Commons

// Bare on/off switch: a track with a sliding knob and no label. This is the
// switch `Toggle` parks at the end of its labeled row, factored out so panel
// headers and other compact controls render the identical thing.
//
// The caller owns the value: bind `checked` to real state and flip it in
// response to `toggled()`. Services that already track a desired state
// optimistically (see the Tailscale service's `_desired`) get an instant knob
// throw for free, because `checked` is already the optimistic value.
//
// `busy` marks an operation in flight: the knob pulses (or, with reduced
// motion, dims) and further clicks are swallowed, while hover, cursor and
// tooltips stay, so the control doesn't flicker every time a background
// refresh runs.
//
// `accessibleName` is what a screen reader announces ("Bluetooth", "Wi-Fi");
// set it wherever no visible label sits in the same control.
//
// The cursor is a ring drawn outside the track rather than a state on the
// track itself, so a bordered track never goes fainter under it. Pointer
// hover draws the hover-cursor border there; Tab focus and the panel
// keyboard cursor draw the FocusRing. `cursorRing` follows `interactive` — a
// switch whose surrounding row owns the click owns the cursor and focus too.
//
// Tab reaches an interactive switch (`focusable`); Space or Enter flips it.
//
// `rounded` auto-detects from Style.cornerRadius so the switch follows the
// theme: pill shape when Hyprland corners are rounded, square on sharp.
Item {
  id: root

  property bool checked: false
  property bool busy: false
  property string accessibleName: ""
  // The knob is placed by x, so a mirrored (right-to-left) layout throws it
  // toward the left when on.
  readonly property bool mirrored: LayoutMirroring.enabled

  // Off when the surrounding row owns the click, as in `Toggle`.
  property bool interactive: true

  // Panel-cursor flag. Same role as Button.hasCursor: panels with their own
  // keyboard cursor bind this to drive the highlight separately from hover.
  property bool hasCursor: false

  property bool cursorRing: interactive
  property bool focusable: interactive
  property int cursorPad: Style.space(6)
  property bool rounded: Style.cornerRadius > 0
  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent

  signal toggled()
  signal hovered(bool isHovered)

  readonly property alias containsMouse: mouse.containsMouse
  readonly property bool hot: hasCursor || mouse.containsMouse

  activeFocusOnTab: focusable

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.accessibleName
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.onToggleAction: if (!root.busy) root.toggled()
  Accessible.onPressAction: if (!root.busy) root.toggled()

  Keys.onReturnPressed: if (focusable && !busy) root.toggled()
  Keys.onEnterPressed: if (focusable && !busy) root.toggled()
  Keys.onSpacePressed: if (focusable && !busy) root.toggled()

  // `trackHeight` is settable so a compact placement — a switch riding a panel
  // section header, say — can ask for a genuinely smaller control instead of
  // scaling a big one down, which lands the track and knob on fractional pixels
  // and blurs their edges. The derived sizes only carry floors low enough to
  // stay out of an override's way; at the default track height each one is
  // already above its floor, so nothing about the normal switch changes.
  property int trackHeight: Math.max(22, Math.round(Style.spacing.controlHeight * 0.55))
  property int trackWidth: Math.round(trackHeight * 1.9)
  property int knobSize: Math.max(6, Math.round(trackHeight * 0.72))
  property int knobInset: Math.max(1, Math.round((trackHeight - knobSize) / 2))

  readonly property int _pad: cursorRing ? cursorPad : 0

  implicitWidth: trackWidth + _pad * 2
  implicitHeight: trackHeight + _pad * 2

  BorderSurface {
    anchors.fill: parent
    visible: root.cursorRing && root.hot
    color: "transparent"
    radius: Style.radius.control
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  FocusRing {
    shown: root.cursorRing && (root.hasCursor || root.activeFocus)
    radius: Style.radius.control
  }

  BorderSurface {
    id: track
    width: root.trackWidth
    height: root.trackHeight
    anchors.centerIn: parent
    radius: root.rounded ? height / 2 : 0
    color: root.checked
      ? Style.selectedFillFor(root.foreground, root.accent)
      : Style.normalFillFor(root.foreground, root.accent)
    borderSpec: Border.controlSpec(root.checked ? "selected" : "normal", root.foreground, root.accent)

    Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

    Rectangle {
      id: knob
      width: root.knobSize
      height: root.knobSize
      radius: root.rounded ? height / 2 : 0
      x: root.checked !== root.mirrored ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      // Off, the knob is a quieter part of the control, still 4.5:1 on the
      // surface so the switch's state reads at a glance.
      // Disabled, it keeps its position but goes to the disabled text role.
      color: !root.enabled ? Commons.Color.disabledText(root.foreground)
        : root.checked ? Style.selectedStateColor(root.foreground, root.accent) : Commons.Color.secondaryText(root.foreground)

      Behavior on x { NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

      // Busy: the knob breathes while the change is under way.
      opacity: root.busy && Style.reduceMotion ? 0.5 : 1
      SequentialAnimation on opacity {
        running: root.busy && !Style.reduceMotion
        loops: Animation.Infinite
        alwaysRunToEnd: true
        NumberAnimation { from: 1; to: 0.35; duration: 600; easing.type: Easing.InOutSine }
        NumberAnimation { from: 0.35; to: 1; duration: 600; easing.type: Easing.InOutSine }
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.busy ? Qt.BusyCursor : Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: if (!root.busy) root.toggled()
  }
}
