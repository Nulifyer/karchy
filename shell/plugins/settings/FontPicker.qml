import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// The monospace font picker of Settings › Fonts: SearchableDropdown with a
// row per font that shows the font itself: its name and a sample line with
// the characters people confuse, two ligature pairs and three icons.
//
// `fonts` is `karchy-font-list --json`'s list: the installed families, then
// the fonts of the Quick install list that aren't installed. A font on that
// list is drawn from its picture (default/karchy/font-specimens, made by
// tools/font-specimens, which holds the same sample and measures), so it
// looks the same before and after it is installed; any other installed font
// is drawn live. Choosing a font that isn't installed emits
// `install(id, name, family)`; an installed one `chosen(family)`.
SearchableDropdown {
  id: root

  property var fonts: []
  // The family in use.
  property string family: ""

  // Shown in place of the font while one is being installed.
  property string busyLabel: ""

  signal chosen(string family)
  signal install(string id, string name, string family)

  // The sample every row shows; tools/font-specimens draws the same line.
  readonly property string sample: "0O1lI => !=  " + Icons.glyph("ui.check") + "  " + Icons.glyph("notify.bell") + "  " + Icons.glyph("disk")
  // A picture is drawn at 28 px, 44 px tall, with the sample 16 em in.
  readonly property real nameSize: Style.font.title
  readonly property real nameColumn: nameSize * 16
  readonly property real pictureScale: nameSize / 28

  function fontFor(value) {
    for (var i = 0; i < fonts.length; i++)
      if (fonts[i].family === value) return fonts[i]
    return null
  }

  // "47 MiB" from pacman's "47.46 MiB".
  function roundedSize(size) {
    var m = String(size || "").match(/^([0-9.]+)\s*(\S+)$/)
    return m ? Math.round(Number(m[1])) + " " + m[2] : ""
  }

  value: busyLabel !== "" ? "" : family
  triggerLabel: busyLabel
  options: fonts.map(function(f) {
    return {
      value: f.family,
      label: f.name,
      // Searched, not shown: the family as fontconfig names it, and the package.
      description: f.family + " " + f.package,
      group: f.installed ? "Installed" : "From the Arch repositories",
      font: f
    }
  })
  placeholderText: "Search " + fonts.length + " fonts"
  popupWidth: Style.space(600)
  popupRowHeight: Style.space(40)
  popupRows: 7

  onChanged: function(value) {
    var f = fontFor(value)
    if (!f) return
    if (f.installed) {
      root.value = Qt.binding(function() { return root.busyLabel !== "" ? "" : root.family })
      if (f.family !== root.family) root.chosen(f.family)
    } else {
      // Not the value until it is installed and set.
      root.value = Qt.binding(function() { return root.busyLabel !== "" ? "" : root.family })
      root.install(f.id, f.name, f.family)
    }
  }

  rowDelegate: Item {
    id: row
    // The Loader that made this row holds what it shows.
    readonly property var option: parent ? parent.option : null
    readonly property bool chosen: parent ? parent.chosen === true : false
    readonly property var font: option ? option.font : null
    readonly property color ink: Commons.Color.popups.text

    implicitHeight: Math.round(44 * root.pictureScale)
    clip: true

    // A font on the Quick install list: its picture, in the text color.
    Image {
      id: picture
      // Only the mask of the rectangle below.
      visible: false
      layer.enabled: true
      source: row.font && row.font.specimen !== "" ? "file://" + row.font.specimen : ""
      height: row.implicitHeight
      width: sourceSize.height > 0 ? Math.round(sourceSize.width * height / sourceSize.height) : 0
      anchors.verticalCenter: parent.verticalCenter
      smooth: true
      mipmap: true
    }
    Rectangle {
      visible: picture.status === Image.Ready
      anchors.fill: picture
      color: row.ink
      layer.enabled: visible
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: picture
        // The picture's own soft edges, not a hard cut at any ink.
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }
    }

    // Any other installed font, drawn in itself.
    Text {
      textFormat: Text.PlainText
      visible: picture.status !== Image.Ready
      anchors.verticalCenter: parent.verticalCenter
      width: root.nameColumn - Style.spacing.lg
      text: row.font ? row.font.name : ""
      color: row.ink
      font.family: row.font ? row.font.family : root.fontFamily
      font.pixelSize: root.nameSize
      elide: Text.ElideRight
    }
    Text {
      textFormat: Text.PlainText
      visible: picture.status !== Image.Ready
      anchors.verticalCenter: parent.verticalCenter
      x: root.nameColumn
      text: root.sample
      color: row.ink
      font.family: row.font ? row.font.family : root.fontFamily
      font.pixelSize: root.nameSize
    }

    // What choosing the row does, or what it is; over the sample's end where
    // the popup is too narrow for both.
    Rectangle {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: status.implicitWidth + Style.spacing.lg
      height: parent.height
      color: "transparent"

      Row {
        id: status
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.spacing.sm

        Text {
          visible: row.chosen
          anchors.verticalCenter: parent.verticalCenter
          text: Icons.glyph("ui.check")
          color: row.ink
          font.family: Icons.family
          font.pixelSize: Style.font.iconSmall
        }
        Text {
          textFormat: Text.PlainText
          anchors.verticalCenter: parent.verticalCenter
          text: {
            if (!row.font) return ""
            if (row.chosen) return "In use"
            if (!row.font.installed) {
              var size = root.roundedSize(row.font.size)
              return "Install and use" + (size !== "" ? " · " + size : "")
            }
            return row.font.icons ? "" : "Icons from a fallback font"
          }
          color: row.chosen ? row.ink : Commons.Color.secondaryText(row.ink, Commons.Color.popups.background)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: row.chosen
        }
      }
    }
  }
}
