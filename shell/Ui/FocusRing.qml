import QtQuick
import qs.Commons

// The keyboard focus ring: drop it into a control and bind `shown` to
// "this is where the keyboard is" — Qt activeFocus, or the panel/menu
// keyboard cursor. It's drawn inside the control's own bounds, over its
// border, so it never shifts the layout and a clipping list can't cut it
// off. Color and width come from Border.focusSpec() (Commons.Color.focus,
// kept at 3:1 against the background and the selected fill in every theme),
// which keeps focus distinct from hover (a faint foreground fill and border)
// and from selection (a stronger fill).
//
// It shows only for the keyboard. A control holding Qt focus shows it unless
// a click gave it that focus; a panel or menu cursor shows it while
// InputMode says the keyboard moved it last, so a row under the pointer gets
// the hover look alone.
//
// `control` is the item whose Qt focus counts (the parent, unless the ring
// sits in a control's background). A text field (`textEntry`) keeps its ring
// however it got focus, since that's where typing goes. `keyboardOnly: false`
// shows it whenever `shown`, for a list's current row inside an open popup.
BorderSurface {
  property bool shown: false
  property Item control: parent
  property bool textEntry: false
  property bool keyboardOnly: true

  readonly property bool _qtFocus: !!control && control.activeFocus === true
  readonly property bool _byKeyboard: !keyboardOnly
    || (_qtFocus ? (textEntry || control.focusReason !== Qt.MouseFocusReason) : InputMode.keyboard)

  anchors.fill: parent
  visible: shown && _byKeyboard
  z: 100
  color: "transparent"
  radius: parent && parent.radius !== undefined ? parent.radius : Style.radius.control
  borderSpec: Border.focusSpec()
}
