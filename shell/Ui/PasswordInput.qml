import QtQuick
import qs.Commons
import qs.Commons as Commons

// The masked password entry of the lock screen and the login screen (the
// greeter): what typing a password does, in one place. The surface around it
// (border, placeholder, icons) belongs to the screen that uses it.
//
//   PasswordInput {
//     anchors.fill: parent
//     checking: service.authenticating
//     onAccepted: service.submit(text)
//   }
//
// One dot per character, shrinking to fit once the password outgrows the
// field, so every keystroke stays visible. Escape or Ctrl+U clears it. A held
// key types nothing (see dropsAutoRepeat). `checking` freezes it while a
// password is being tried; `keyPressed` reports every key for a screen that
// wakes its display on input.
TextInput {
  id: root

  property bool checking: false
  // Whether the cursor may show at all (a screen hides it beside a message).
  property bool cursorShown: true
  property color textColor: Commons.Color.foreground
  property int dotFontSize: Math.round(Style.font.heading * 1.33)
  property int dotLetterSpacing: Math.round(Style.font.heading * 0.19)

  // How far the dots shrink so the whole password fits the field.
  readonly property real dotScale: dotMetrics.advanceWidth > 0
    ? Math.min(1, (width - 4) / dotMetrics.advanceWidth)
    : 1

  signal keyPressed()

  // Waking a DPMS-blanked display can stall the compositor for seconds while
  // the monitor modesets, so the wake key's release arrives late and client-side
  // key repeat floods the field with that character. A held key has no business
  // typing a password; only holding Backspace/Delete to clear stays useful.
  function dropsAutoRepeat(key) {
    return key !== Qt.Key_Backspace && key !== Qt.Key_Delete
  }

  verticalAlignment: TextInput.AlignVCenter
  activeFocusOnPress: true
  clip: true
  readOnly: checking
  echoMode: TextInput.Password
  passwordCharacter: "●"
  passwordMaskDelay: 0
  color: textColor
  selectedTextColor: textColor
  font.family: Style.font.family
  font.pixelSize: Math.max(1, Math.floor(dotFontSize * dotScale))
  font.letterSpacing: dotLetterSpacing * dotScale
  cursorVisible: activeFocus && cursorShown && !checking && text.length > 0
  cursorDelegate: Rectangle {
    width: 2
    color: root.textColor
    visible: root.cursorVisible
  }

  Accessible.role: Accessible.EditableText
  Accessible.passwordEdit: true

  Keys.onPressed: function(event) {
    root.keyPressed()
    if (event.isAutoRepeat && root.dropsAutoRepeat(event.key)) {
      event.accepted = true
      return
    }
    if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
      root.text = ""
      event.accepted = true
    }
  }

  // Measures the masked password at full size; dotScale compares this against
  // the field's width.
  TextMetrics {
    id: dotMetrics
    font.family: Style.font.family
    font.pixelSize: root.dotFontSize
    font.letterSpacing: root.dotLetterSpacing
    text: "●".repeat(root.text.length)
  }
}
