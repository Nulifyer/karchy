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
// field, so every keystroke stays visible. The dots are the ones every
// password field draws (Ui/PasswordDots): their size and spacing follow
// `textSize`, the size of the text the screen shows for this field (its
// placeholder or caption), and are the same in every text font. Escape or
// Ctrl+U clears it. A held key types nothing (see dropsAutoRepeat).
// `checking` freezes it while a password is being tried; `keyPressed` reports
// every key for a screen that wakes its display on input.
TextInput {
  id: root

  property bool checking: false
  // Whether the cursor may show at all (a screen hides it beside a message).
  property bool cursorShown: true
  property color textColor: Commons.Color.foreground
  property real textSize: Style.font.heading
  // The selection's colour (PasswordDots draws it; `selectionColor` is the
  // low band TextInput would draw).
  property color selectionTint: Style.selectionFill

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
  passwordCharacter: dots.glyph
  passwordMaskDelay: 0
  color: textColor
  selectedTextColor: textColor
  selectionColor: "transparent"
  font.family: dots.family
  font.pixelSize: dots.size
  font.letterSpacing: dots.gap
  cursorVisible: activeFocus && cursorShown && !checking && text.length > 0
  cursorDelegate: dots.cursor
  // Keeps the row on whole pixels, up and down and where a screen centres it.
  topPadding: dots.offGrid(height - contentHeight) ? 1 : 0
  leftPadding: effectiveHorizontalAlignment === TextInput.AlignHCenter && dots.offGrid(width - contentWidth) ? 1 : 0

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

  PasswordDots {
    id: dots
    textSize: root.textSize
    fit: root.dotScale
    color: root.textColor
    selectionColor: root.selectionTint
    cursorWidth: 2
    blink: false
  }

  // Measures the masked password at full size; dotScale compares this against
  // the field's width.
  TextMetrics {
    id: dotMetrics
    font.family: dots.family
    font.pixelSize: dots.fullSize
    font.letterSpacing: dots.fullGap
    text: dots.glyph.repeat(root.text.length)
  }
}
