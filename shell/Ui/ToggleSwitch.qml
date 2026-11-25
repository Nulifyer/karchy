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
// `busy`: this switch's own change is under way (docs/architecture.md,
// "Busy"). The knob goes at once to where the person put it and holds the
// `Spinner`; the track keeps the state that is confirmed and follows when the
// change is done. A change that fails puts the knob back, and the page says
// why. Busy, the switch keeps its colors and the keyboard and takes no second
// flip, whatever `enabled` says. Bind it to this switch's change only, never
// to a run another control started.
//
// `press()` is the one way it is flipped: its own click and keys use it, and
// so does a row that owns the click (`Toggle`, `SettingRow`).
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

  // Where the person put the knob, while the change they asked for runs.
  property bool _asked: false
  property bool _target: false
  readonly property bool _knobOn: busy && _asked ? _target : checked
  // Busy is never drawn as disabled.
  readonly property bool _shownEnabled: enabled || busy
  // A busy switch a caller disabled had the keyboard and gets it back when
  // enabled again (`focus` stays set), so its ring stays meanwhile.
  readonly property bool _heldFocus: busy && !enabled && focus

  onBusyChanged: if (!busy) _asked = false

  function press() {
    if (busy || !enabled) return
    _target = !checked
    _asked = true
    toggled()
    // A process reports that it runs a moment after it is started, so
    // `busy` may follow the press; the press is forgotten if it doesn't.
    if (!busy) settle.restart()
  }

  // Nothing became busy: the caller changed it at once, or refused.
  Timer {
    id: settle
    interval: 250
    onTriggered: if (!root.busy) root._asked = false
  }

  readonly property alias containsMouse: mouse.containsMouse
  // Busy, the pointer changes nothing: there is nothing to flip.
  readonly property bool hot: hasCursor || (mouse.containsMouse && !busy)

  activeFocusOnTab: focusable

  Accessible.role: Accessible.CheckBox
  Accessible.name: root.accessibleName
  Accessible.checkable: true
  Accessible.checked: root.checked
  Accessible.description: root.busy ? Commons.I18n.t("common.busy") : ""
  Accessible.onToggleAction: root.press()
  Accessible.onPressAction: root.press()

  Keys.onReturnPressed: if (focusable) root.press()
  Keys.onEnterPressed: if (focusable) root.press()
  Keys.onSpacePressed: if (focusable) root.press()

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
  // In a form's control column the track is the switch's box, so it starts
  // where the dropdowns and buttons above and below it start and makes a row
  // no taller than theirs; the ring's room lies outside the box.
  property bool flush: false
  readonly property int _room: flush ? 0 : _pad
  readonly property int _outside: flush ? -_pad : 0

  implicitWidth: trackWidth + _room * 2
  implicitHeight: trackHeight + _room * 2

  BorderSurface {
    anchors.fill: parent
    anchors.margins: root._outside
    visible: root.cursorRing && root.hot
    color: "transparent"
    radius: Style.radius.control
    borderSpec: Border.controlSpec("hover-cursor", root.foreground, root.accent)
  }

  FocusRing {
    anchors.margins: root._outside
    shown: root.cursorRing && (root.hasCursor || root.activeFocus || root._heldFocus)
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
      x: root._knobOn !== root.mirrored ? track.width - width - root.knobInset : root.knobInset
      anchors.verticalCenter: parent.verticalCenter
      // Off, the knob is a quieter part of the control, still 4.5:1 on the
      // surface so the switch's state reads at a glance.
      // Disabled, it keeps its position but goes to the disabled text role.
      color: !root._shownEnabled ? Commons.Color.disabledText(root.foreground)
        : root._knobOn ? Style.selectedStateColor(root.foreground, root.accent) : Commons.Color.secondaryText(root.foreground)

      Behavior on x { NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic } }
      Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

      // Busy: the spinner turns in the knob, in whichever of the page's two
      // colors reads on it.
      Spinner {
        visible: root.busy
        anchors.centerIn: parent
        size: Math.max(6, root.knobSize - 2 * Math.max(1, Math.round(root.knobSize / 8)))
        color: Util.contrast(knob.color, Commons.Color.background) >= Util.contrast(knob.color, Commons.Color.foreground)
          ? Commons.Color.background : Commons.Color.foreground
      }
    }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    anchors.margins: root._outside
    enabled: root.interactive
    hoverEnabled: true
    cursorShape: root.busy ? Qt.ArrowCursor : Qt.PointingHandCursor
    onContainsMouseChanged: root.hovered(containsMouse)
    onClicked: root.press()
  }
}
