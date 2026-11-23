import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons

// Facts as label and value pairs: a battery's size and cycles, a
// connection's address and rates, a VM's CPU and memory.
//
//   KeyValueGrid {
//     columns: 2
//     rows: [
//       { label: "Ping", value: "12 ms" },
//       { label: "IP address", value: ip, copyable: true, tooltip: "Copy IP address" },
//       { label: "Packet loss", value: "2%", color: Commons.Color.status.warning }
//     ]
//     onCopyRequested: function(value) { root.copy(value) }
//   }
//
// Values use tabular figures, so numbers that update in place don't jiggle.
// `columns` pairs sit side by side. `justify` (the panels' narrow form) pushes
// each value to the end of its pair; otherwise labels share one width and the
// values start in a column after them (a window page's form). A row whose
// value is "" still holds its line, so the grid doesn't jump when data lands.
GridLayout {
  id: root

  property var rows: []
  property bool justify: false
  property real fontSize: Style.font.body
  property color foreground: Commons.Color.foreground
  property color surface: Commons.Color.background
  property string fontFamily: Style.font.family
  property string placeholder: "—"

  signal copyRequested(string value)

  readonly property color labelColor: Commons.Color.secondaryText(foreground, surface)
  // Where the values start, from the grid's left edge. 0 puts them right
  // after the longest label (a bar panel); a form page gives its control
  // column, so the values stand under its dropdowns and buttons.
  property real valueColumn: 0
  // A value too long for its line wraps instead of losing its middle: for a
  // list of addresses, where every one counts.
  property bool wrapValues: false
  // One label width for the whole grid, so the values line up.
  readonly property real labelWidth: {
    var w = 0
    for (var i = 0; i < rows.length; i++) w = Math.max(w, metrics.advanceWidth(String(rows[i].label || "")))
    return Math.max(Math.ceil(w), valueColumn - Style.spacing.lg)
  }

  columns: 1
  columnSpacing: Style.space(20)
  rowSpacing: Style.spacing.labelGap

  FontMetrics {
    id: metrics
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
  }

  Repeater {
    model: root.rows

    RowLayout {
      id: pair
      required property var modelData
      readonly property string value: modelData.value === undefined || modelData.value === null || modelData.value === ""
        ? root.placeholder : String(modelData.value)
      Layout.fillWidth: true
      spacing: Style.spacing.lg

      Text {
        Layout.preferredWidth: root.justify ? -1 : root.labelWidth
        Layout.alignment: Qt.AlignTop
        textFormat: Text.PlainText
        text: String(pair.modelData.label || "")
        color: root.labelColor
        font.family: root.fontFamily
        font.pixelSize: root.fontSize
        elide: Text.ElideRight
      }

      Text {
        id: valueText
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: pair.value
        horizontalAlignment: root.justify ? Text.AlignRight : Text.AlignLeft
        color: pair.modelData.color !== undefined ? pair.modelData.color : root.foreground
        // `mono: true` on a row whose value is an address, a path or a
        // command: read as code, so in the mono font (D-149).
        font.family: pair.modelData.mono === true ? Style.font.mono : root.fontFamily
        font.pixelSize: root.fontSize
        font.features: { "tnum": 1 }
        elide: root.wrapValues ? Text.ElideNone : Text.ElideMiddle
        wrapMode: root.wrapValues ? Text.Wrap : Text.NoWrap

        MouseArea {
          id: valueMouse
          anchors.fill: parent
          enabled: pair.modelData.copyable === true && pair.value !== root.placeholder
          hoverEnabled: enabled
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onClicked: root.copyRequested(pair.value)
        }

        PanelToolTip {
          visible: valueMouse.enabled && valueMouse.containsMouse && !!pair.modelData.tooltip
          text: pair.modelData.tooltip || ""
          fontFamily: root.fontFamily
        }
      }
    }
  }
}
