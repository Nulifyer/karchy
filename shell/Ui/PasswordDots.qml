import QtQuick
import qs.Commons
import qs.Commons as Commons

// The dots of a field that hides what is typed: one rule for every such
// field, whatever its size (D-169). It is declared inside the TextInput or
// TextField it serves, which hands it its font, cursor and selection while it
// masks:
//
//   TextInput {
//     id: input
//     echoMode: TextInput.Password
//     passwordCharacter: dots.glyph
//     font.family: dots.family
//     font.pixelSize: dots.size
//     font.letterSpacing: dots.gap
//     selectionColor: "transparent"
//     cursorDelegate: dots.cursor
//     topPadding: dots.offGrid(height - contentHeight) ? 1 : 0
//
//     PasswordDots {
//       id: dots
//       textSize: Style.font.body
//       color: input.color
//       selectionColor: Style.selectionFill
//     }
//   }
//
// A dot is the icon font's disc, a circle that fills its em, so the font's
// pixel size is the dot's diameter and its letter spacing the space between
// two dots. Both follow `textSize`, the size of the text the field shows
// otherwise (its placeholder, a revealed password): the diameter is
// `diameterRatio` of it and the distance from one dot's centre to the next
// `pitchRatio`, both in whole pixels so every dot meets the pixel grid the
// same way. A small field and a big one are then the same row at two sizes.
// The proportions live here and nowhere else: a field sets `textSize`, never
// a dot size.
//
// The icon font's line is only as high as the dot, so the cursor and the
// selection TextInput would draw are that low too. This draws both as high
// as a line of text (`lineHeight`): the cursor through `cursor`, the
// selection behind the dots.
Item {
  id: root

  // Diameter and centre distance, as parts of the text size: a dot about as
  // high as a lowercase letter, a third of a dot between two.
  readonly property real diameterRatio: 0.6
  readonly property real pitchRatio: 0.8
  // Cursor and selection height, as a part of the text size.
  readonly property real lineRatio: 1.5

  // The TextInput or TextField the dots belong to.
  property Item input: parent
  // The size of the text this field shows when it shows text.
  property real textSize: Style.font.body
  // Below 1 the row shrinks by that much (a field that keeps a long
  // password in view by making it smaller).
  property real fit: 1
  // Whether the field is masking now (false while its password is revealed
  // or its placeholder shows).
  property bool active: true
  property color color: Commons.Color.foreground
  property color selectionColor: Style.selectionFill
  property real lineHeight: Math.round(textSize * lineRatio * fit)
  property int cursorWidth: 1
  // Whether the cursor blinks, as the cursor of a text field does.
  property bool blink: true

  // TextInput.passwordCharacter takes one UTF-16 unit and the icon map's
  // Material Design glyphs take two; this name is the one the map keeps
  // outside them for that reason (tools/icon-check).
  readonly property string glyph: Icons.glyph("ui.password-dot")
  readonly property string family: Icons.family
  // At full size, and as drawn (with `fit`).
  readonly property int fullSize: Math.max(1, Math.round(textSize * diameterRatio))
  readonly property int fullGap: Math.max(1, Math.round(textSize * pitchRatio) - fullSize)
  readonly property int size: Math.max(1, Math.floor(fullSize * fit))
  readonly property real gap: fullGap * fit

  // Whether a row centred in `slack` more pixels than it needs begins on
  // half a pixel, which draws its dots soft: an odd number does. The field
  // then moves its text the other half (a pixel of padding on one side of a
  // centred row moves it half a pixel), so a dot is the same sharp disc in
  // every field. A row shrunk to fit has no whole pixels to keep.
  function offGrid(slack) {
    return root.active && root.fit === 1 && Math.abs(Math.round(slack)) % 2 === 1
  }

  // Where a position of the text is in the field, measured from the cursor:
  // cursorRectangle counts the field's padding and positionToRectangle does
  // not, and reading it makes this follow the text, its alignment and its
  // scrolling.
  function placeOf(position) {
    if (!root.input) return 0
    var cursor = root.input.cursorRectangle
    var size = root.input.contentWidth + root.input.width
    return cursor.x + root.input.positionToRectangle(position).x
      - root.input.positionToRectangle(root.input.cursorPosition).x
  }
  // Only while masking: a TextField that isn't a password field has this
  // too, and nothing to work out.
  readonly property real selectionFrom: root.active && root.input ? placeOf(root.input.selectionStart) : 0
  readonly property real selectionTo: root.active && root.input ? placeOf(root.input.selectionEnd) : 0

  readonly property Component cursor: Component {
    Item {
      id: caret

      property bool lit: true

      width: 1
      visible: root.input.cursorVisible

      Rectangle {
        // A place is where the next dot begins, a dot's space after the one
        // before. Between two dots the cursor stands in the middle of that
        // space; after the last it keeps the place, a wide cursor growing
        // back into the space so a scrolled field never cuts it.
        x: root.input.cursorPosition === 0 ? 0
          : root.input.cursorPosition < root.input.length ? -Math.round((root.gap + width) / 2)
          : 1 - width
        anchors.verticalCenter: parent.verticalCenter
        width: root.cursorWidth
        height: root.lineHeight
        color: root.color
        visible: caret.lit
      }

      Timer {
        id: flash
        interval: Math.max(1, Qt.styleHints.cursorFlashTime / 2)
        repeat: true
        running: root.blink && caret.visible && Qt.styleHints.cursorFlashTime > 0
        onRunningChanged: caret.lit = true
        onTriggered: caret.lit = !caret.lit
      }

      // A cursor that has just moved is shown, as TextInput's own is.
      Connections {
        target: root.input
        function onCursorPositionChanged() {
          caret.lit = true
          if (flash.running) flash.restart()
        }
      }
    }
  }

  anchors.fill: parent
  // Behind the field's text, in front of its background.
  z: -0.5

  // The selection, kept to where the field shows its text (a long password
  // scrolls under a TextField's padding) and half a space beyond.
  Item {
    id: textArea

    readonly property real margin: Math.ceil(root.gap / 2)

    x: (root.input ? root.input.leftPadding : 0) - margin
    width: parent.width - (root.input ? root.input.leftPadding + root.input.rightPadding : 0) + margin * 2
    height: parent.height
    clip: true

    Rectangle {
      visible: root.active && root.input && root.input.selectionStart !== root.input.selectionEnd
      // A dot's space comes after it; half of it goes before, so the
      // selection has the same margin on both sides of the dots it covers.
      x: Math.min(root.selectionFrom, root.selectionTo) - root.gap / 2 - textArea.x
      y: root.input ? root.input.cursorRectangle.y + (root.input.cursorRectangle.height - height) / 2 : 0
      width: Math.abs(root.selectionTo - root.selectionFrom)
      height: root.lineHeight
      color: root.selectionColor
    }
  }
}
