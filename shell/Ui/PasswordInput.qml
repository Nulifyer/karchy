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
// field, so every keystroke stays visible. The dots are a glyph of the icon
// font, a disc that fills its em, so they are the same size and shape in
// every text font: `dotSize` is the disc's diameter and `dotGap` the space
// between two. Escape or Ctrl+U clears it. A held
// key types nothing (see dropsAutoRepeat). `checking` freezes it while a
// password is being tried; `keyPressed` reports every key for a screen that
// wakes its display on input.
TextInput {
  id: root

  property bool checking: false
  // Whether the cursor may show at all (a screen hides it beside a message).
  property bool cursorShown: true
  property color textColor: Commons.Color.foreground
  property int dotSize: Math.round(Style.font.heading * 1.19)
  property int dotGap: Math.round(Style.font.heading * 0.31)
  // TextInput.passwordCharacter takes one UTF-16 unit, and the icon map's
  // Material Design glyphs take two; this name is one of the two the map
  // keeps outside them for that reason (tools/icon-check).
  readonly property string dot: Icons.glyph("ui.password-dot.large")

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
  passwordCharacter: dot
  passwordMaskDelay: 0
  color: textColor
  selectedTextColor: textColor
  font.family: Icons.family
  font.pixelSize: Math.max(1, Math.floor(dotSize * dotScale))
  font.letterSpacing: dotGap * dotScale
  cursorVisible: activeFocus && cursorShown && !checking && text.length > 0
  // The icon font's line is as high as a dot; the cursor stands taller, as
  // it does beside text.
  cursorDelegate: Item {
    width: 2
    visible: root.cursorVisible
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: Math.round(root.font.pixelSize * 1.7)
      color: root.textColor
    }
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
    font.family: Icons.family
    font.pixelSize: root.dotSize
    font.letterSpacing: root.dotGap
    text: root.dot.repeat(root.text.length)
  }
}
