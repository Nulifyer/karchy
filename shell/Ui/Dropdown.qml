import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// Themed single-select dropdown. Trigger row paints with the kit's focus
// chrome; the popup anchors below and uses Commons.Color.popups.background +
// Commons.Color.popups.border so it reads as a panel surface rather than the
// platform-native ComboBox look. Where the window has too little room under
// the trigger the popup opens over it instead, and where neither side fits
// the whole list it takes the larger side and the list scrolls.
//
// `options` accepts either a plain string[] or an array of
// { value, label } objects (label is what we render; value is what we
// emit). Mixing is fine — each row is interpreted independently. An option
// may carry `icon` (a glyph from Icons.glyph, drawn before the label) and
// `detail` (a count or a state, quieter, at the end of the row); the trigger
// shows the chosen option's too. SidebarSwitcher lists a window's pages so.
//
// Keyboard: Tab to focus the trigger, Enter/Space opens, Esc closes,
// j/k or Up/Down walks options inside the open popup, Enter selects.
// A sibling SearchableDropdown reuses the same visuals but adds an
// embedded filter input — keep the two separate so each stays simple.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []

  property color foreground: Commons.Color.popups.text
  property color background: Commons.Color.popups.background
  property color popupBorder: Commons.Color.popups.border
  property color accent: Commons.Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Commons.Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true
  // How many options show before the list scrolls.
  property int maxRows: 8

  // Panel-cursor flag. When true, the trigger renders the shared
  // hover-cursor state. Active Qt focus defaults to the same visuals.
  // Emits `hovered(bool)` on pointer enter/leave so the panel can keep
  // its cursor state in sync with the mouse.
  property bool hasCursor: false

  // popupOpen + open()/close()/toggle() let a parent panel know when the
  // dropdown owns keys (its embedded ListView is active) and suspend its
  // own keyCatcher so j/k inside the popup don't double-drive the panel
  // cursor.
  readonly property bool popupOpen: popup.opened
  // Puts the keyboard on the trigger, as Tab would (a page opened at it).
  function takeFocus() { trigger.forceActiveFocus(Qt.TabFocusReason) }
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)
  signal hovered(bool isHovered)
  // Tab or Shift+Tab on the trigger, before the keyboard moves on: a window
  // that keeps its own Tab order accepts the event and moves it itself.
  signal tabbed(var event)

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }
  function optionIcon(o) {
    return (o && typeof o === "object" && o.icon) ? String(o.icon) : ""
  }
  function optionDetail(o) {
    return (o && typeof o === "object" && o.detail !== undefined && o.detail !== null) ? String(o.detail) : ""
  }
  function currentOption() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return options[i]
    }
    return null
  }
  function currentLabel() {
    var o = currentOption()
    return o !== null ? optionLabel(o) : value
  }

  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Commons.Color.secondaryText(root.foreground, root.background)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.radius.control

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor
      readonly property var _borderSpec: Border.controlSpec(trigger._focused || trigger._hot ? "hover-cursor" : "normal", root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec

      activeFocusOnTab: true

      FocusRing { shown: trigger._focused || root.hasCursor }

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
          root.tabbed(event)
        }
      }

      Text {
        id: triggerIcon
        visible: text !== ""
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        text: root.optionIcon(root.currentOption())
        color: root.enabled ? root.foreground : Commons.Color.disabledText(root.foreground, root.background)
        font.family: Icons.family
        font.pixelSize: Style.font.icon
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: triggerIcon.visible ? triggerIcon.right : parent.left
        anchors.right: triggerDetail.visible ? triggerDetail.left : chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: triggerIcon.visible ? Style.spacing.md : trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: triggerDetail.visible ? Style.spacing.lg : trigger.borderRight + Style.spacing.md
        text: root.currentLabel()
        color: root.enabled ? root.foreground : Commons.Color.disabledText(root.foreground, root.background)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: triggerDetail
        visible: text !== ""
        textFormat: Text.PlainText
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        // The label keeps at least half the trigger.
        width: Math.min(implicitWidth, trigger.width * 0.45)
        text: root.optionDetail(root.currentOption())
        color: Commons.Color.secondaryText(root.foreground, root.background)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.features: { "tnum": 1 }
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: Icons.glyph("ui.chevron.down")
        color: root.enabled ? Commons.Color.secondaryText(root.foreground, root.background) : Commons.Color.disabledText(root.foreground, root.background)
        font.family: Icons.family
        font.pixelSize: Style.font.iconSmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // CloseOnPressOutsideParent treats a press on the trigger as inside,
        // so the popup is still open here and a second click collapses it
        // instead of reopening.
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      Popup {
        id: popup

        // A popup is drawn inside its window and cut off at the window's
        // edge, so where it opens is decided each time it opens, from the
        // room the window then has on each side of the trigger.
        property bool above: false
        // The most height the chosen side has room for; 0 before the first open.
        property real room: 0
        readonly property real gap: Style.spacing.xxs
        readonly property real fullHeight:
          Math.min(root.options.length * root.popupRowHeight + Math.max(0, root.options.length - 1) * Style.spacing.labelGap,
                   root.popupRowHeight * root.maxRows + (root.maxRows - 1) * Style.spacing.labelGap)
          + topPadding + bottomPadding

        function place() {
          var win = trigger.Window.window
          if (!win) {
            popup.above = false
            popup.room = 0
            return
          }
          // The window's top and bottom edges, seen from the trigger.
          var windowTop = trigger.mapFromItem(null, 0, 0).y
          var windowBottom = trigger.mapFromItem(null, 0, win.height).y
          var edge = Style.spacing.sm
          var below = windowBottom - trigger.height - popup.gap - edge
          var over = -windowTop - popup.gap - edge
          popup.above = popup.fullHeight > below && over > below
          popup.room = Math.max(root.popupRowHeight + topPadding + bottomPadding, popup.above ? over : below)
        }

        x: 0
        y: above ? -height - gap : trigger.height + gap
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        width: trigger.width
        implicitHeight: room > 0 ? Math.min(fullHeight, room) : fullHeight
        onAboutToShow: place()
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.radius.surface
        }

        onOpened: {
          optionList.currentIndex = Math.max(0, optionList.indexOfValue(root.value))
          optionList.forceActiveFocus()
        }

        contentItem: ListView {
          id: optionList
          spacing: Style.spacing.labelGap

          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
            else if (event.key === Qt.Key_Down || event.text === "j") {
              optionList.currentIndex = Math.min(root.options.length - 1, optionList.currentIndex + 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Up || event.text === "k") {
              optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              optionList.selectCurrent(); event.accepted = true
            }
          }
          implicitHeight: contentHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          model: root.options
          currentIndex: -1

          function indexOfValue(v) {
            for (var i = 0; i < root.options.length; i++)
              if (root.optionValue(root.options[i]) === v) return i
            return -1
          }

          function selectCurrent() {
            if (currentIndex < 0 || currentIndex >= root.options.length) return
            var v = root.optionValue(root.options[currentIndex])
            root.value = v
            root.changed(v)
            popup.close()
          }

          delegate: Rectangle {
            required property var modelData
            required property int index
            width: optionList.width
            height: root.popupRowHeight
            radius: Style.radius.control
            color: index === optionList.currentIndex
              ? Style.hoverFillFor(root.foreground, root.accent)
              : "transparent"

            FocusRing { shown: index === optionList.currentIndex; keyboardOnly: false }

            Text {
              id: optionIconText
              visible: text !== ""
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.controlPaddingX
              text: root.optionIcon(modelData)
              color: index === optionList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
              font.family: Icons.family
              font.pixelSize: Style.font.icon
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: optionIconText.visible ? optionIconText.right : parent.left
              anchors.right: optionDetailText.visible ? optionDetailText.left : parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: optionIconText.visible ? Style.spacing.md : Style.spacing.controlPaddingX
              anchors.rightMargin: optionDetailText.visible ? Style.spacing.lg : Style.spacing.controlPaddingX
              text: root.optionLabel(modelData)
              color: index === optionList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Text {
              id: optionDetailText
              visible: text !== ""
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.rightMargin: Style.spacing.controlPaddingX
              width: Math.min(implicitWidth, parent.width * 0.45)
              text: root.optionDetail(modelData)
              color: Commons.Color.secondaryText(root.foreground, root.background)
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              font.features: { "tnum": 1 }
              elide: Text.ElideRight
            }

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onPositionChanged: optionList.currentIndex = parent.index
              onClicked: optionList.selectCurrent()
            }
          }
        }
      }
    }
  }
}
