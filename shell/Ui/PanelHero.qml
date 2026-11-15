import QtQuick
import qs.Commons
import qs.Commons as Commons

// The top of a bar panel: a large icon, the panel's title, a caps status
// line ("2 RUNNING", "CONNECTED") and an optional control on the trailing
// edge (a master switch, the battery percentage).
//
//   PanelHero {
//     iconText: Icons.glyph("bluetooth")
//     title: "Bluetooth"
//     meta: root.statusText
//     trailingControl: Component { ToggleSwitch { ... } }
//   }
//
// Text sits on the popups surface and takes its colors from it. With no icon
// the labels start at the edge (no empty slot). `iconComponent` replaces the
// glyph with an item of the panel's own (an image, an animated icon).
Item {
  id: root

  property string iconText: ""
  property Component iconComponent: null
  property color iconColor: foreground
  property real iconSize: Style.font.iconHero
  property real iconOpacity: 1.0
  property string title: ""
  property string meta: ""
  property color metaColor: dim
  property string detail: ""
  property color foreground: Commons.Color.popups.text
  property color surface: Commons.Color.popups.background
  property string fontFamily: Style.font.family
  property alias metaOpacity: metaText.opacity

  // Optional control pinned to the trailing edge of the hero — a ToggleSwitch,
  // a small button, a figure. The hero centers it against the labels and
  // reserves the space itself, so callers never do the geometry.
  property Component trailingControl: null
  readonly property Item trailingItem: trailingLoader.item

  readonly property color dim: Commons.Color.secondaryText(foreground, surface)
  readonly property bool _hasIcon: iconText !== "" || iconComponent !== null
  readonly property real trailingInset: trailingLoader.item && trailingLoader.item.visible ? trailingLoader.width + Style.space(12) : 0

  width: parent ? parent.width : implicitWidth
  implicitHeight: Math.max(iconLoader.implicitHeight, heroLabels.implicitHeight, trailingLoader.implicitHeight)

  Loader {
    id: iconLoader
    active: root._hasIcon
    sourceComponent: root.iconComponent !== null ? root.iconComponent : glyphComponent
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    opacity: root.iconOpacity
  }

  Component {
    id: glyphComponent
    Text {
      textFormat: Text.PlainText
      text: root.iconText
      color: root.iconColor
      font.family: Icons.family
      font.pixelSize: root.iconSize
      Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.base) } }
    }
  }

  Column {
    id: heroLabels
    anchors.left: root._hasIcon ? iconLoader.right : parent.left
    anchors.leftMargin: root._hasIcon ? Style.spacing.heroGap : 0
    anchors.right: parent.right
    anchors.rightMargin: root.trailingInset
    anchors.verticalCenter: parent.verticalCenter
    spacing: Style.space(2)

    Row {
      id: titleRow
      visible: root.title !== "" || detailPill.visible
      width: parent.width

      Text {
        id: titleText
        textFormat: Text.PlainText
        visible: root.title !== ""
        text: root.title
        width: Math.min(implicitWidth, Math.max(0, parent.width - (detailPill.visible ? detailPill.implicitWidth + Style.space(8) : 0)))
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Item {
        width: Math.max(0, parent.width - titleText.width - detailPill.implicitWidth)
        height: 1
      }

      BorderSurface {
        id: detailPill
        visible: root.detail !== ""
        implicitWidth: detailText.implicitWidth + Style.space(10)
        implicitHeight: detailText.implicitHeight + Style.space(4)
        anchors.verticalCenter: parent.verticalCenter
        color: "transparent"
        borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)
        radius: Style.radius.control

        Text {
          id: detailText
          textFormat: Text.PlainText
          anchors.centerIn: parent
          text: root.detail
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
        }
      }
    }

    Text {
      id: metaText
      textFormat: Text.PlainText
      width: parent.width
      text: root.meta.toUpperCase()
      visible: text !== ""
      color: root.metaColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: Style.font.labelSpacing
      elide: Text.ElideRight
    }
  }

  Loader {
    id: trailingLoader
    sourceComponent: root.trailingControl
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
  }
}
