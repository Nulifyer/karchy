import QtQuick
import QtQuick.Controls as Controls
import qs.Commons
import qs.Commons as Commons

// A window's sidebar when the window is narrow (a tile beside other windows,
// under Style.spacing.windowNarrow), in the form people know from Windows
// Settings and every app built on its navigation view (D-177): the sidebar
// goes behind a menu button at the top left, and the button opens the same
// list as a pane over the page. Beside the button is the window's name, as at
// the top of the sidebar. The open page is named once, by its own heading
// right under the bar, which also has what the sidebar showed beside the
// name (a count, a state), the (i) and the page's buttons: the bar doesn't
// repeat it (D-178).
// Settings, Quick install, Virtual machines and Containers all turn their
// sidebar into this; none keeps a sidebar of its own design at that width.
//
//   SidebarSwitcher {
//     visible: root.narrow
//     Layout.fillWidth: true
//     title: "Settings"
//     value: root.section
//     options: root.sections.map(function(s) {
//       return { value: s.id, label: s.label, icon: Icons.glyph(s.iconName) }
//     })
//     onChanged: function(value) { root.section = value }
//   }
//
// An option is { value, label } with, as the sidebar's row has them:
//   icon       a glyph from Icons.glyph, before the name
//   detail     what stood beside the name: a count, a state ("Running")
//   separator  true for a rule above the row, where the sidebar has one
// `title` is the window's name, in the bar and at the top of the pane;
// `status` is the line the sidebar has under it ("12 apps · 3 installed"),
// in the pane. `note` is a line under the bar for what the sidebar said under
// the window's name and has to stay in view (which engine the containers are
// from, that the installed apps couldn't be read).
//
// The open page is `value`, which the window binds: a choice is only
// reported (`changed`), and the window changes what it shows.
//
// Pointer: the button opens the pane and closes it again from the same
// place; a row chooses and closes; a click beside the pane closes it.
// Keyboard: the button is one Tab stop; Enter, Space or Down opens the pane
// with the keyboard on the open page's row. There Up/Down or j/k, Home, End,
// Page Up and Page Down move, Enter or Space chooses, Escape closes, and Tab
// goes between the list and the button. After a choice made with a key the
// keyboard is on the page: its first control, or wherever `focusPage` puts
// it. After Escape it is back on the button. A choice or a close made with
// the pointer leaves it on the button, as a click on a sidebar's row leaves
// it on the row: Tab goes on into the page, and no control of the page
// lights up that nobody went to.
// `takeFocus()` puts the keyboard on the button, as a window does where it
// would have started in its sidebar.
Rectangle {
  id: root

  property string value: ""
  property var options: []
  property string title: ""
  property string status: ""
  property color statusColor: Commons.Color.textSecondary
  property string note: ""
  // A function of the window's own that puts the keyboard on the page after
  // a choice, given how it was made (a Qt focus reason: Tab for a key, Mouse
  // for the pointer). Without one a key's choice goes to the Tab stop after
  // the button, and the pointer's stays on the button.
  property var focusPage: null

  readonly property bool popupOpen: pane.opened
  // The keyboard is on the button or in the pane: for a window that moves
  // it when this gives way to the sidebar again.
  readonly property bool hasKeyboard: menuButton.activeFocus || pane.visible

  signal changed(string value)
  // Tab or Shift+Tab on the button, for a window that keeps a Tab order of
  // its own (it accepts the event); otherwise the keyboard goes on to the page.
  signal tabbed(var event)

  function takeFocus() { menuButton.forceActiveFocus(Qt.TabFocusReason) }
  function open() { pane.open() }
  function close() { pane.close() }

  function optionValue(o) { return (o && typeof o === "object") ? String(o.value) : String(o) }
  function optionLabel(o) { return (o && typeof o === "object") ? String(o.label) : String(o) }
  function optionIcon(o) { return (o && typeof o === "object" && o.icon) ? String(o.icon) : "" }
  function optionDetail(o) {
    return (o && typeof o === "object" && o.detail !== undefined && o.detail !== null) ? String(o.detail) : ""
  }
  function indexOfValue(value) {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return i
    return -1
  }
  // A choice closes the pane and hands the keyboard to the page.
  property bool _chosen: false
  property int _reason: Qt.TabFocusReason
  function choose(index, reason) {
    if (index < 0 || index >= options.length) return
    root._chosen = true
    root._reason = reason
    pane.close()
    root.changed(optionValue(options[index]))
  }
  function toPage() {
    if (typeof root.focusPage === "function") { root.focusPage(root._reason); return }
    var next = root._reason === Qt.MouseFocusReason ? null : menuButton.nextItemInFocusChain(true)
    if (next && next !== menuButton) next.forceActiveFocus(root._reason)
    else menuButton.forceActiveFocus(root._reason)
  }
  // Closed without a choice, with a key (Escape, Enter on the button) or
  // with the pointer.
  function dismiss(byKey) {
    root._reason = byKey ? Qt.TabFocusReason : Qt.MouseFocusReason
    pane.close()
  }

  // Another page was opened from outside while the pane was open (the menu,
  // `karchy settings <page>`): the pane gives way to it.
  onValueChanged: if (pane.visible && !root._chosen) root.dismiss(true)

  // The sidebar is back (the window got wider) with the pane open: the pane
  // goes, a turn later, so the window still finds the keyboard here.
  onVisibleChanged: if (!visible && pane.visible) Qt.callLater(function() { root._chosen = false; root._hidden = true; pane.close() })
  property bool _hidden: false

  readonly property real barPadding: Style.spacing.lg
  implicitHeight: menuButton.height + barPadding * 2
    + (noteText.visible ? noteText.implicitHeight + Style.spacing.sm : 0)
  // The sidebar's own tint: it is the same list, folded up.
  color: Util.alpha(Commons.Color.foreground, 0.04)

  Accessible.role: Accessible.ToolBar
  Accessible.name: root.title

  Button {
    id: menuButton
    x: Style.spacing.panelPadding
    y: root.barPadding
    focusable: true
    iconText: Icons.glyph("ui.menu")
    tooltipText: "Open navigation"
    onClicked: pane.open()
    Keys.onDownPressed: pane.open()
    Keys.onTabPressed: function(event) { event.accepted = false; root.tabbed(event) }
    Keys.onBacktabPressed: function(event) { event.accepted = false; root.tabbed(event) }
  }

  // The window's name, quiet as at the top of the sidebar: the page's own
  // heading under the bar is the title.
  Text {
    anchors.left: menuButton.right
    anchors.leftMargin: Style.spacing.lg
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.verticalCenter: menuButton.verticalCenter
    textFormat: Text.PlainText
    text: root.title
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.title
    font.bold: true
    elide: Text.ElideRight
  }

  Text {
    id: noteText
    visible: root.note !== ""
    anchors.left: menuButton.left
    anchors.right: parent.right
    anchors.rightMargin: Style.spacing.panelPadding
    anchors.top: menuButton.bottom
    anchors.topMargin: Style.spacing.sm
    textFormat: Text.PlainText
    text: root.note
    wrapMode: Text.Wrap
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  // The sidebar's list over the page, from the window's left edge, as tall
  // as the window. The rest of the window is covered while it is open: a
  // click there closes the pane and does nothing else.
  Controls.Popup {
    id: pane

    parent: Controls.Overlay.overlay
    x: 0
    y: 0
    // The sidebar's width where the window has it, and always some of the
    // page left beside it to click on.
    width: parent ? Math.round(Math.min(Style.space(300), parent.width - Style.space(44))) : 0
    height: parent ? parent.height : 0
    padding: 0
    modal: true
    dim: true
    focus: true
    closePolicy: Controls.Popup.CloseOnEscape | Controls.Popup.CloseOnPressOutside

    Controls.Overlay.modal: Rectangle { color: Util.alpha(Commons.Color.background, 0.7) }

    enter: Transition {
      NumberAnimation { property: "x"; from: -pane.width; to: 0; duration: Style.duration(Style.motion.base); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.easeOut }
    }
    exit: Transition {
      NumberAnimation { property: "x"; from: 0; to: -pane.width; duration: Style.duration(Style.motion.fast); easing.type: Easing.InCubic }
    }

    background: Rectangle {
      color: Commons.Color.background
      Rectangle { anchors.fill: parent; color: root.color }
      Rectangle {
        anchors.right: parent.right
        width: Math.max(1, Style.space(1))
        height: parent.height
        color: Util.alpha(Commons.Color.foreground, 0.12)
      }
    }

    // The keyboard is in the list from the moment the pane starts to open:
    // a Down pressed right after Enter is not lost to the slide.
    onAboutToShow: {
      root._chosen = false
      root._hidden = false
      // A click beside the pane closes it with no word from us.
      root._reason = Qt.MouseFocusReason
      entryList.currentIndex = Math.max(0, root.indexOfValue(root.value))
      entryList.positionViewAtIndex(entryList.currentIndex, ListView.Contain)
      entryList.focus = true
    }
    onOpened: entryList.forceActiveFocus(Qt.TabFocusReason)
    onClosed: {
      if (root._hidden) return
      if (root._chosen) Qt.callLater(root.toPage)
      else menuButton.forceActiveFocus(root._reason)
    }

    contentItem: Item {
      Accessible.role: Accessible.Pane
      Accessible.name: root.title
      // From the button; the list answers its own.
      Keys.onEscapePressed: root.dismiss(true)

      // In the bar's button's place, so the same spot opens and closes.
      Button {
        id: closeButton
        x: menuButton.x
        y: menuButton.y
        focusable: true
        iconText: Icons.glyph("ui.menu")
        // No tooltip: the pointer is on it the moment the pane opens, and
        // the tip would cover the first rows.
        accessibleName: "Close navigation"
        onClicked: root.dismiss(closeButton.focusReason !== Qt.MouseFocusReason)
      }

      // A sidebar row's height, so the pane's rows are the sidebar's.
      Button { id: rowProbe; visible: false; leftAlign: true; iconText: Icons.glyph("ui.menu"); text: "Row" }

      // The window's name, as at the top of the sidebar.
      Text {
        id: paneTitle
        anchors.left: closeButton.right
        anchors.leftMargin: Style.spacing.lg
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.panelPadding
        anchors.verticalCenter: closeButton.verticalCenter
        textFormat: Text.PlainText
        text: root.title
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.title
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        id: paneStatus
        visible: root.status !== ""
        anchors.left: closeButton.left
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.panelPadding
        anchors.top: closeButton.bottom
        anchors.topMargin: Style.spacing.lg
        textFormat: Text.PlainText
        text: root.status
        color: root.statusColor
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: Style.font.labelSpacing
        elide: Text.ElideRight
      }

      ListView {
        id: entryList
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: paneStatus.visible ? paneStatus.bottom : closeButton.bottom
        anchors.bottom: parent.bottom
        anchors.margins: Style.spacing.panelPadding
        anchors.topMargin: Style.spacing.lg
        clip: true
        spacing: Style.spacing.sm
        boundsBehavior: Flickable.StopAtBounds
        model: root.options
        currentIndex: -1
        highlightMoveDuration: 0
        focus: true
        activeFocusOnTab: true
        Controls.ScrollBar.vertical: ListScrollBar {}

        Accessible.role: Accessible.List
        Accessible.name: root.title

        function move(to) {
          currentIndex = Math.max(0, Math.min(count - 1, to))
          positionViewAtIndex(currentIndex, ListView.Contain)
        }
        readonly property int page: Math.max(1, Math.floor(height / (rowProbe.implicitHeight + spacing)) - 1)

        Keys.priority: Keys.BeforeItem
        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Down || event.text === "j") move(currentIndex + 1)
          else if (event.key === Qt.Key_Up || event.text === "k") move(currentIndex - 1)
          else if (event.key === Qt.Key_Home) move(0)
          else if (event.key === Qt.Key_End) move(count - 1)
          else if (event.key === Qt.Key_PageDown) move(currentIndex + page)
          else if (event.key === Qt.Key_PageUp) move(currentIndex - page)
          else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
            root.choose(currentIndex, Qt.TabFocusReason)
          else if (event.key === Qt.Key_Escape) root.dismiss(true)
          else return
          event.accepted = true
        }

        delegate: Item {
          id: entry
          required property var modelData
          required property int index
          readonly property bool open: root.optionValue(modelData) === root.value
          readonly property bool cursor: index === entryList.currentIndex
          readonly property bool separated: !!modelData && typeof modelData === "object" && modelData.separator === true && index > 0
          // Under the scrollbar's lane where the list scrolls.
          width: entryList.width - (entryList.contentHeight > entryList.height ? Style.spacing.md : 0)
          height: row.height + (separated ? Style.spacing.lg * 2 - entryList.spacing + rule.height : 0)

          Accessible.role: Accessible.ListItem
          Accessible.name: root.optionLabel(modelData)
            + (root.optionDetail(modelData) !== "" ? ", " + root.optionDetail(modelData) : "")
          Accessible.selected: entry.open
          Accessible.onPressAction: root.choose(entry.index, Qt.TabFocusReason)

          Rectangle {
            id: rule
            visible: entry.separated
            anchors.left: parent.left
            anchors.right: parent.right
            y: Style.spacing.lg - entryList.spacing
            height: Math.max(1, Style.space(1))
            color: Util.alpha(Commons.Color.foreground, 0.12)
          }

          BorderSurface {
            id: row
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: rowProbe.implicitHeight
            radius: Style.radius.control
            readonly property bool hot: entry.cursor || rowMouse.containsMouse
            color: rowMouse.pressed ? Style.pressedFillFor(Commons.Color.foreground, Commons.Color.accent)
              : entry.cursor && entryList.activeFocus ? Style.focusFillFor(Commons.Color.foreground, Commons.Color.accent)
              : hot ? Style.hoverFillFor(Commons.Color.foreground, Commons.Color.accent)
              : entry.open ? Style.selectedFillFor(Commons.Color.foreground, Commons.Color.accent)
              : "transparent"
            borderSpec: hot ? Border.controlSpec("hover-cursor", Commons.Color.foreground, Commons.Color.accent) : Border.none()

            FocusRing { shown: entry.cursor && entryList.activeFocus; keyboardOnly: false }

            Text {
              id: entryIcon
              visible: text !== ""
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.leftMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: root.optionIcon(entry.modelData)
              color: Commons.Color.foreground
              font.family: Icons.family
              font.pixelSize: Style.font.icon
            }

            Text {
              textFormat: Text.PlainText
              anchors.left: entryIcon.visible ? entryIcon.right : parent.left
              anchors.leftMargin: entryIcon.visible ? Style.spacing.md : Style.spacing.controlPaddingX
              anchors.right: entryDetail.visible ? entryDetail.left : parent.right
              anchors.rightMargin: entryDetail.visible ? Style.spacing.lg : Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              text: root.optionLabel(entry.modelData)
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: entry.open
              elide: Text.ElideRight
            }

            Text {
              id: entryDetail
              visible: text !== ""
              textFormat: Text.PlainText
              anchors.right: parent.right
              anchors.rightMargin: Style.spacing.controlPaddingX
              anchors.verticalCenter: parent.verticalCenter
              // The name keeps at least half the row.
              width: Math.min(implicitWidth, parent.width * 0.45)
              text: root.optionDetail(entry.modelData)
              color: entry.open ? Commons.Color.focus : Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              font.features: { "tnum": 1 }
              elide: Text.ElideRight
            }

            MouseArea {
              id: rowMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.choose(entry.index, Qt.MouseFocusReason)
            }
          }
        }
      }
    }
  }
}
