import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// The button. One component for every clickable thing in the kit.
// States compose independently and are applied in priority order:
//
//   pressed (mouse down)         pressed fill
//   activeFocus || hasCursor     focus fill + hover-cursor border + FocusRing
//   hover                        hover-cursor fill + hover-cursor border
//   selected                     selected fill + optional selected border
//   active                       selected fill
//   idle                         transparent or normal border if `bordered`
//
// `variant`:
//   "neutral"      the default; quiet, for most actions
//   "primary"      the one action a page or dialog is for: accent fill
//   "destructive"  deletes, removes or forces something: error-colored text
//                  and border, an error tint under the pointer or focus. Put
//                  it apart from the others and confirm it (ConfirmDialog).
//
// `enabled: false` draws the disabled text role and takes no clicks; callers
// don't dim it themselves. `busy` keeps the label, spins a busy icon in
// place of the icon and takes no clicks while the action runs.
//
// All fills/borders come from `qs.Commons.Style` tokens, so themes
// control the look via [controls] in shell.toml.
//
// Emits `hovered(bool)` so panels with their own keyboard cursor model
// can update state on mouse enter/leave.
BorderSurface {
  id: root

  property string text: ""
  property string iconText: ""
  property string tooltipText: ""

  // State flags (see comment above for paint priority).
  property bool selected: false
  property bool active: false
  property bool hasCursor: false
  property bool focusable: false
  property bool bordered: false
  property string variant: "neutral"
  property bool busy: false
  // What a screen reader says; the label, else the tooltip.
  property string accessibleName: text !== "" ? text : tooltipText

  // Colors. Defaults track the theme; per-instance overrides are honored.
  property color foreground: Commons.Color.foreground
  property color background: "transparent"
  property color accent: Commons.Color.accent

  // Sizing.
  property string fontFamily: Style.font.family
  property real fontSize: Style.font.body
  property real iconSize: Style.font.icon
  property real iconRotation: 0
  property bool iconSpinning: false
  property real horizontalPadding: Style.spacing.controlPaddingX
  property real verticalPadding: Style.spacing.controlPaddingY
  property bool leftAlign: false

  leftPadding: horizontalPadding
  rightPadding: horizontalPadding
  topPadding: verticalPadding
  bottomPadding: verticalPadding

  // Tooltip palette. Auto-rendered if tooltipText is set. Defaults pull
  // from [tooltip] in shell.toml; override per-instance only when a button
  // intentionally wants a tooltip that diverges from the theme.
  property color tooltipBackground: Commons.Color.tooltip.background
  property color tooltipForeground: Commons.Color.tooltip.text
  property color tooltipBorder: Commons.Color.tooltip.border

  signal clicked()
  signal rightClicked()
  signal hovered(bool isHovered)

  activeFocusOnTab: focusable && enabled
  Keys.onReturnPressed: if (focusable && root._live) root.clicked()
  Keys.onEnterPressed: if (focusable && root._live) root.clicked()
  Keys.onSpacePressed: if (focusable && root._live) root.clicked()

  Accessible.role: Accessible.Button
  Accessible.name: root.accessibleName
  Accessible.onPressAction: if (root._live) root.clicked()

  // Reserve the largest border any visual state can paint. Otherwise a
  // borderless idle button grows by a pixel per side on hover/focus and
  // relayouts neighboring controls.
  // Measured from the label's natural width rather than the row, which
  // narrows the label when the button is held narrower than that.
  implicitWidth: _contentNaturalWidth + horizontalPadding * 2 + _reservedBorderLeft + _reservedBorderRight
  implicitHeight: row.implicitHeight + verticalPadding * 2 + _reservedBorderTop + _reservedBorderBottom
  radius: Style.radius.control

  readonly property bool _live: enabled && !busy
  readonly property bool _primary: variant === "primary"
  readonly property bool _destructive: variant === "destructive"
  // The color the label, icon and borders are drawn in.
  readonly property color _ink: !enabled ? Commons.Color.disabledText(root.foreground)
    : _primary ? Commons.Color.accentText
    : _destructive ? Commons.Color.status.error
    : root.foreground
  readonly property bool hot: enabled && (mouseArea.containsMouse || hasCursor)
  // Where the keyboard is: Tab focus, or a panel's keyboard cursor (which the
  // panels also move under the pointer, so it is their one highlight).
  readonly property bool _showFocusRing: (focusable && activeFocus) || hasCursor
  readonly property color _selectedColor: Style.selectedStateColor(root.foreground, root.accent)
  readonly property var _hoverBorderSpec: _primary ? Border.flat(Commons.Color.accent, Style.hoverBorderWidth)
    : Border.controlSpec("hover-cursor", root._ink, root._destructive ? root._ink : root.accent)
  readonly property var _selectedBorderSpec: Border.controlSpec("selected", root.foreground, root.accent)
  readonly property var _normalBorderSpec: _primary ? Border.flat(Commons.Color.accent, Style.normalBorderWidth)
    : Border.controlSpec("normal", root._ink, root._destructive ? root._ink : root.accent)
  readonly property real _reservedBorderTop: Math.max(
    Border.top(_hoverBorderSpec),
    Border.top(_selectedBorderSpec),
    bordered ? Border.top(_normalBorderSpec) : 0)
  readonly property real _reservedBorderRight: Math.max(
    Border.right(_hoverBorderSpec),
    Border.right(_selectedBorderSpec),
    bordered ? Border.right(_normalBorderSpec) : 0)
  readonly property real _reservedBorderBottom: Math.max(
    Border.bottom(_hoverBorderSpec),
    Border.bottom(_selectedBorderSpec),
    bordered ? Border.bottom(_normalBorderSpec) : 0)
  readonly property real _reservedBorderLeft: Math.max(
    Border.left(_hoverBorderSpec),
    Border.left(_selectedBorderSpec),
    bordered ? Border.left(_normalBorderSpec) : 0)
  readonly property real _reservedContentLeftInset: _reservedBorderLeft + leftPadding
  // Keyed on the text, not the Texts' visible: a hidden button (a width probe)
  // reports its children invisible too, which would collapse it to padding.
  readonly property bool _spinning: root.iconSpinning || root.busy
  readonly property real _iconRoom: root.iconText !== "" || root.busy ? iconGlyph.implicitWidth + (root.text !== "" ? row.spacing : 0) : 0
  readonly property real _contentNaturalWidth: _iconRoom + (root.text !== "" ? label.implicitWidth : 0)
  // A translated label can outgrow a button laid out at a fixed width (a
  // grid of equal pills): it first spends half the padding, then shrinks to
  // fit, and elides only when even the smallest size does not.
  readonly property real _labelRoom: width - horizontalPadding - _reservedBorderLeft - _reservedBorderRight - _iconRoom
  readonly property var _borderSpec: hot || _showFocusRing ? _hoverBorderSpec
    : selected                 ? (Border.controlHasWidth("selected") ? _selectedBorderSpec : (bordered ? _normalBorderSpec : Border.none()))
    : bordered || _primary || _destructive ? _normalBorderSpec
    : Border.none()

  // A primary button keeps its accent fill and shows hover and press by
  // mixing in its text color; the others lay the state fills over `background`.
  readonly property color _primaryFill: !enabled ? Util.alpha(Commons.Color.accent, 0.35)
    : mouseArea.pressed ? Util.mix(Commons.Color.accentText, Commons.Color.accent, 0.2)
    : hot || _showFocusRing ? Util.mix(Commons.Color.accentText, Commons.Color.accent, 0.1)
    : Commons.Color.accent
  readonly property color _stateTint: _destructive ? Commons.Color.status.error : root.foreground

  color: _primary              ? _primaryFill
    : !enabled                 ? (selected ? Style.selectedFillFor(root._ink, root.accent) : background)
    : mouseArea.pressed        ? Style.pressedFillFor(root._stateTint, root.accent)
    : _showFocusRing           ? Style.focusFillFor(root._stateTint, root.accent)
    : hot                      ? Style.hoverFillFor(root._stateTint, root.accent)
    : selected                 ? Style.selectedFillFor(root.foreground, root.accent)
    : active                   ? Style.selectedFillFor(root.foreground, root.accent)
    : background

  // Border follows the same state precedence as fill. Buttons stay
  // borderless at rest unless `bordered` is set, but hover-cursor/focus
  // always use the shared cursor border so the keyboard target is visible
  // and consistent with the rest of the kit. Selected borders are off by
  // default for plain buttons; explicitly bordered buttons keep their
  // normal border when selected unless selected-border-width opts in to a
  // dedicated selected border.
  borderSpec: _borderSpec

  Behavior on color { ColorAnimation { duration: Style.duration(Style.motion.fast) } }

  // Held down, the button gives a little, so a click is felt as well as seen.
  scale: mouseArea.pressed && _live ? 0.97 : 1
  Behavior on scale {
    NumberAnimation {
      duration: Style.duration(160)
      easing.type: Easing.Bezier
      easing.bezierCurve: Style.easeOut
    }
  }

  FocusRing { id: focusRing; shown: root._showFocusRing }

  // On the accent fill the ring's own color would vanish, so a primary
  // button's ring gets a line of the page color just inside it.
  BorderSurface {
    visible: focusRing.visible && root._primary
    anchors.fill: parent
    anchors.margins: Style.focusBorderWidth
    z: 100
    color: "transparent"
    radius: Math.max(0, root.radius - Style.focusBorderWidth)
    borderSpec: Border.flat(Commons.Color.background, Math.max(1, Style.space(1)))
  }

  PanelToolTip {
    visible: root.tooltipText !== "" && mouseArea.containsMouse
    text: root.tooltipText
    fontFamily: root.fontFamily
    panelForeground: root.tooltipForeground
    panelBackground: root.tooltipBackground
    panelBorder: root.tooltipBorder
  }

  Row {
    id: row
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: root.leftAlign ? parent.left : undefined
    anchors.leftMargin: root.leftAlign ? root._reservedContentLeftInset : 0
    anchors.horizontalCenter: root.leftAlign ? undefined : parent.horizontalCenter
    spacing: Style.spacing.controlGap

    Text {
      id: iconGlyph
      textFormat: Text.PlainText
      visible: root.iconText !== "" || root.busy
      text: root.busy ? Icons.glyph("ui.busy") : root.iconText
      color: root.selected && root.enabled ? root._selectedColor : root._ink
      font.family: Icons.family
      font.pixelSize: root.iconSize
      rotation: root._spinning ? 0 : root.iconRotation
      transformOrigin: Item.Center
      anchors.verticalCenter: parent.verticalCenter

      RotationAnimation on rotation {
        from: 0
        to: 360
        duration: Style.duration(900)
        loops: Animation.Infinite
        running: root._spinning && !Style.reduceMotion
      }
    }

    Text {
      id: label
      textFormat: Text.PlainText
      visible: root.text !== ""
      text: root.text
      color: root.selected && root.enabled ? root._selectedColor : root._ink
      font.family: root.fontFamily
      font.pixelSize: root.fontSize
      font.bold: root.selected || root._primary
      width: Math.max(0, Math.min(implicitWidth, root._labelRoom))
      fontSizeMode: Text.HorizontalFit
      // A tight label gives up a little size, never below the smallest text
      // role, then elides: nine-pixel labels were the result at three quarters.
      minimumPixelSize: Math.min(root.fontSize, Math.max(Style.font.caption, Math.round(root.fontSize * 0.9)))
      elide: Text.ElideRight
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    // Undoes the press scale, so the button only looks smaller: a press near
    // its edge still counts as a click when it's let go there.
    scale: 1 / root.scale
    hoverEnabled: true
    cursorShape: root._live ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: function(mouse) {
      if (!root._live) return
      if (root.focusable) root.forceActiveFocus(Qt.MouseFocusReason)
      if (mouse.button === Qt.RightButton) root.rightClicked()
      else root.clicked()
    }
  }

  HoverHandler {
    onHoveredChanged: root.hovered(hovered)
  }
}
