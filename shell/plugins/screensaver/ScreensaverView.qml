import QtQuick
import qs.Commons
import "ScreensaverModel.js" as Model

// One screen's picture of the screensaver: the service's grid, centred, on
// black. Every view of it shows the same frame, so the overlay and the lock
// screen can take over from each other without a jump.
Rectangle {
  id: view

  property var saver: null
  readonly property var grid: saver ? saver.grid : null
  readonly property int cols: grid ? grid.cols : 0
  readonly property int rows: grid ? grid.rows : 0
  readonly property int cellW: grid ? grid.cellW : 1
  readonly property int cellH: grid ? grid.cellH : 1

  color: "black"
  clip: true

  function tint(color) {
    return Qt.rgba(((color >> 16) & 255) / 255, ((color >> 8) & 255) / 255, (color & 255) / 255, 1)
  }

  function drawCell(at) {
    var item = cells.itemAt(at)
    var state = saver ? saver.cellState : null
    if (!item || !state || at >= state.chars.length) return
    item.glyph = state.chars[at]
    item.tint = tint(state.colors[at])
  }

  function draw(changed) {
    for (var i = 0; i < changed.length; i++) drawCell(changed[i])
  }

  function drawAll() {
    for (var at = 0; at < cells.count; at++) drawCell(at)
  }

  Connections {
    target: view.saver
    function onFrameDrawn(changed) { view.draw(changed) }
    function onGridReset() { Qt.callLater(view.drawAll) }
  }

  // What is left of the screen is split between the two sides.
  Item {
    width: view.cols * view.cellW
    height: view.rows * view.cellH
    x: Math.floor((view.width - width) / 2)
    y: Math.floor((view.height - height) / 2)

    Repeater {
      id: cells
      model: view.cols * view.rows
      onItemAdded: function(index, item) { view.drawCell(index) }

      delegate: Rectangle {
        id: cell
        required property int index
        property string glyph: " "
        property color tint: "white"
        // A block element is drawn as the part of its cell it fills, as a
        // terminal draws it, so rows and columns of them meet without a seam
        // in any font.
        readonly property int block: Model.block(glyph)
        readonly property int col: index % view.cols
        readonly property int row: Math.floor(index / view.cols)
        visible: glyph !== " "
        color: block !== 0 ? tint : "transparent"
        x: col * view.cellW + (block === 5 ? Math.floor(view.cellW / 2) : 0)
        y: row * view.cellH + (block === 3 ? Math.floor(view.cellH / 2) : 0)
        width: block === 4 ? Math.ceil(view.cellW / 2) : block === 5 ? view.cellW - Math.floor(view.cellW / 2) : view.cellW
        height: block === 2 ? Math.ceil(view.cellH / 2) : block === 3 ? view.cellH - Math.floor(view.cellH / 2) : view.cellH

        Text {
          visible: cell.block === 0
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: cell.glyph
          color: cell.tint
          font.family: Style.font.mono
          font.pixelSize: view.grid ? view.grid.fontPx : 24
        }
      }
    }
  }
}
