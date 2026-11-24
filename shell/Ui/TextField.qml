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
// A `password` field masks what is typed with dots from the icon font, so
// they are the same in every text font; the field keeps the text font's
// height.
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

  echoMode: password ? TextInput.Password : TextInput.Normal
  // One UTF-16 unit, as passwordCharacter takes (see Ui/PasswordInput).
  passwordCharacter: Icons.glyph("ui.password-dot")
  font.family: _masked ? Icons.family : Style.font.family
  font.pixelSize: Style.font.body
  // The icon font's line is lower than the text font's: the height is the
  // text font's, whichever is drawn.
  implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
    Math.max(contentHeight, textLine.implicitHeight) + topPadding + bottomPadding)
  color: enabled ? foreground : Commons.Color.disabledText(foreground)
  selectionColor: selectionTint
  selectedTextColor: foreground
  placeholderTextColor: Commons.Color.secondaryText(foreground)

  leftPadding: horizontalPadding + Border.left(_borderSpec)
  rightPadding: horizontalPadding + Border.right(_borderSpec)
  topPadding: verticalPadding + Border.top(_borderSpec)
  bottomPadding: verticalPadding + Border.bottom(_borderSpec)

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
    font.pixelSize: root.font.pixelSize
  }
}
