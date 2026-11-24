import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// Single-line text input with the kit's focus + selection styling. Inherits
// from Qt Quick Controls TextField so the underlying type's API (text,
// placeholderText, accepted, editingFinished, validator, ...) is available
// to callers without re-exposing each property.
//
// Defaults bind to qs.Commons.Color so a caller with no theme overrides
// just works; foreground / accent / selectionTint can be overridden per
// instance. Mouse hover paints the hover-cursor state; activeFocus and the
// panel cursor add the FocusRing, as Button, Toggle and Dropdown do. The
// placeholder uses the secondary text role, so it reads as a hint (quieter
// than typed text) in light and dark themes alike.
//
// A `password` field masks what is typed with the dots every password field
// draws (Ui/PasswordDots), sized from the field's text size and the same in
// every text font; the field keeps the text font's height. Such a field
// leaves `font`, `selectionColor` and `cursorDelegate` to this component: a
// caller that sets one of them takes the dots out of the rule.
//
// Sizing is driven by font.pixelSize + verticalPadding. The default 30px
// implicitHeight fits dialog forms; inline callers (wifi's row-embedded
// passphrase prompt) drop verticalPadding to match a 22-26px row.
TextField {
  id: root

  property color foreground: Commons.Color.foreground
  property color accent: Commons.Color.accent
  property color selectionTint: Style.selectionFillFor(foreground, accent)
  property bool password: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.inputPaddingY

  // Panel-cursor flag. When true (and the field isn't already focused),
  // the background paints the shared hover/cursor state.
  // For mouse-enter/leave the consumer reads QQC TextField's inherited
  // `hovered` property (via onHoveredChanged) — we don't add a sibling
  // signal because the inherited property would shadow it.
  property bool hasCursor: false

  readonly property bool _focused: activeFocus
  readonly property bool _hot: hovered || hasCursor
  readonly property var _borderSpec: Border.controlSpec(_focused || _hot ? "hover-cursor" : "normal", root.foreground, root.accent)

  // Dots are drawn only while there is text, so the placeholder stays in the
  // text font.
  readonly property bool _masked: password && length > 0
  readonly property int _textSize: Style.font.body
  readonly property real _padTop: verticalPadding + Border.top(_borderSpec)
  readonly property real _padBottom: verticalPadding + Border.bottom(_borderSpec)
  // Half a pixel from the bottom padding to the top when the dots would
  // otherwise sit between two pixels (PasswordDots.offGrid); the height stays.
  readonly property real _halfPixel: dots.offGrid(height - _padTop - _padBottom - contentHeight) ? 0.5 : 0

  echoMode: password ? TextInput.Password : TextInput.Normal
  passwordCharacter: dots.glyph
  font.family: _masked ? dots.family : Style.font.family
  font.pixelSize: _masked ? dots.size : _textSize
  font.letterSpacing: _masked ? dots.gap : 0
  // The icon font's line is lower than the text font's: the height is the
  // text font's, whichever is drawn.
  implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
    Math.max(contentHeight, textLine.implicitHeight) + topPadding + bottomPadding)
  color: enabled ? foreground : Commons.Color.disabledText(foreground)
  selectionColor: _masked ? "transparent" : selectionTint
  selectedTextColor: foreground
  cursorDelegate: _masked ? dots.cursor : null
  placeholderTextColor: Commons.Color.secondaryText(foreground)

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: _padTop + _halfPixel
  bottomPadding: _padBottom - _halfPixel

  background: BorderSurface {
    color: Style.controlFill(root._focused, root._hot, root.foreground, root.accent)
    borderSpec: root._borderSpec
    radius: Style.radius.control

    FocusRing { shown: root._focused || root.hasCursor; control: root; textEntry: true }
  }

  Text {
    id: textLine
    visible: false
    textFormat: Text.PlainText
    font.family: Style.font.family
    font.pixelSize: root._masked ? root._textSize : root.font.pixelSize
  }

  // The cursor and the selection of a masked field are as high as the text
  // line, as they are while its placeholder shows.
  PasswordDots {
    id: dots
    active: root._masked
    textSize: root._textSize
    lineHeight: textLine.implicitHeight
    color: root.color
    selectionColor: root.selectionTint
  }
}
