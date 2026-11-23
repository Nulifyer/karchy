import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// A slider on a window page (Settings › Sound's volumes, Displays' night
// light warmth): PanelSlider in the window's colors, as one Tab stop with a
// focus ring. Left and Right move it a step.
//
//   PageSlider {
//     accessibleName: "Output volume, 40%"
//     value: 0.4
//     onMoved: function(v) { … }       // while dragging
//     onReleased: function(v) { … }    // the drag's end, and each key step
//   }
//
// `liveValue` is the value under the pointer while `dragging`.
Item {
  id: root

  property real value: 0
  property real minimum: 0
  property real maximum: 1
  property real step: 0.05
  property bool integer: false
  property string accessibleName: ""
  readonly property bool dragging: slider.dragging
  readonly property real liveValue: slider.liveValue

  signal moved(real value)
  signal released(real value)
  // The secondary action on the track, as in the panels: sound mutes with it.
  signal rightClicked()

  function stepBy(direction) {
    var next = Math.max(minimum, Math.min(maximum, value + direction * step))
    if (integer) next = Math.round(next)
    if (next !== value) root.released(next)
  }

  Layout.fillWidth: true
  implicitWidth: Style.space(200)
  implicitHeight: slider.implicitHeight + Style.spacing.md
  activeFocusOnTab: true
  Accessible.role: Accessible.Slider
  Accessible.name: root.accessibleName
  Keys.onLeftPressed: root.stepBy(LayoutMirroring.enabled ? 1 : -1)
  Keys.onRightPressed: root.stepBy(LayoutMirroring.enabled ? -1 : 1)

  // The track runs from edge to edge of this item, so it starts where the
  // dropdowns and buttons above and below it start. The knob's half at each
  // end, and the focus ring, lie outside.
  readonly property real overhang: slider.knobSize / 2

  FocusRing {
    anchors.leftMargin: -(root.overhang + Style.spacing.sm)
    anchors.rightMargin: -(root.overhang + Style.spacing.sm)
    shown: root.activeFocus
    control: root
    radius: Style.radius.control
  }

  PanelSlider {
    id: slider
    anchors.fill: parent
    anchors.leftMargin: -root.overhang
    anchors.rightMargin: -root.overhang
    // A window, not a panel: the slider takes the window's colors.
    trackColor: Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
    fillColor: Commons.Color.foreground
    knobColor: Commons.Color.foreground
    minimum: root.minimum
    maximum: root.maximum
    step: root.step
    integer: root.integer
    value: root.value
    onMoved: function(v) { root.moved(v) }
    onReleased: function(v) { root.released(v) }
    onRightClicked: root.rightClicked()
  }
}
