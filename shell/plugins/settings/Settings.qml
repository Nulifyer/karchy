import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// karchy Settings window (D-27). A normal application window, so it tiles,
// floats and closes like any other. Each section reads and writes through a
// karchy-settings-* command, which saves JSON under ~/.config/karchy and
// generates config under ~/.local/state/karchy; the user's own files load
// after that and always win.
//
// Open it with: karchy-settings [section] [item]. The summon payload is
// {"section": …} plus whatever opens the section at one thing in it (Network
// takes "item", "connection", "device" or "anchor"); the section gets it as
// `target`.
//
// Keyboard: Tab and Shift+Tab walk the section list, then every control of
// the page; Up/Down or j/k move through the section list; Escape closes. The
// focused control shows the FocusRing and is scrolled into view.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property string karchyPath: Quickshell.env("KARCHY_PATH")
  property bool opened: false
  property string section: "network"
  // What the section was opened at, from the summon payload.
  property var target: ({})
  onSectionChanged: if (!root.target || root.target.section !== root.section) root.target = ({})

  // The pages, grouped by what people come to Settings for (user
  // 2026-11-19): connecting and controlling the machine, how it looks and
  // behaves, the system, accounts and access, and About last. The list shows
  // a quiet rule where the group changes; a page hidden on this machine
  // (`visible: false`) leaves no empty group and no doubled rule. Keep the
  // order the same in bin/karchy-settings, the menu's search rows and the
  // docs.
  readonly property var allSections: [
    { id: "network", label: "Network", iconName: "net.network", group: 1 },
    // Only with a Bluetooth adapter, as the bar's panel and Reload › Bluetooth.
    { id: "bluetooth", label: "Bluetooth", iconName: "bluetooth", group: 1, visible: BluetoothControl.available },
    { id: "displays", label: "Displays", iconName: "display", group: 1 },
    { id: "sound", label: "Sound", iconName: "audio.speaker", group: 1 },
    { id: "input", label: "Input", iconName: "input.keyboard", group: 1 },
    { id: "keybindings", label: "Keybindings", iconName: "config.keybindings", group: 1 },
    { id: "appearance", label: "Appearance", iconName: "menu.appearance", group: 2 },
    { id: "fonts", label: "Fonts", iconName: "look.font", group: 2 },
    { id: "notifications", label: "Notifications", iconName: "notify.bell", group: 2 },
    { id: "apps", label: "Default apps", iconName: "menu.apps", group: 2 },
    { id: "power", label: "Power", iconName: "system.power", group: 3 },
    { id: "storage", label: "Storage", iconName: "disk", group: 3 },
    { id: "datetime", label: "Date & Time", iconName: "time", group: 3 },
    { id: "users", label: "Users", iconName: "account.user", group: 4 },
    { id: "security", label: "Security", iconName: "security", group: 4 },
    { id: "ssh", label: "SSH & Git", iconName: "security.ssh", group: 4 },
    { id: "about", label: "About", iconName: "info", group: 5 }
  ]
  readonly property var sections: allSections.filter(function(entry) { return entry.visible !== false })

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    // The page asked for, else the first one.
    root.section = payload && payload.section ? String(payload.section) : root.sections[0].id
    root.target = payload || {}
    if (sectionLoader.item && "target" in sectionLoader.item) sectionLoader.item.target = root.target
    // Already open: move the keyboard to the section asked for (or let the
    // section put it on the item it was opened at).
    if (root.opened && !root.targetsItem()) Qt.callLater(function() { root.focusSection(root.currentSectionIndex()) })
    root.opened = true
    root.refresh()
  }

  function close() {
    // shell.hide() calls back into close(); stop the second time round.
    if (!root.opened) return
    // Closing while a change waits to be kept counts as "Go back", as the
    // timer would.
    if (confirmDialog.opened && typeof confirmDialog.onNo === "function") confirmDialog.canceled()
    root.opened = false
    if (root.shell && root.manifest) root.shell.hide(root.manifest.id)
  }

  // Sections that show live state reload it on open and on Hyprland's monitor
  // and config events, so the window never shows a stale screen layout.
  function refresh() {
    if (sectionLoader.item && typeof sectionLoader.item.refresh === "function") sectionLoader.item.refresh()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!root.opened) return
      var name = String(event.name)
      if (name.indexOf("monitor") === 0 || name === "configreloaded") {
        root.refresh()
        Hyprland.refreshMonitors()
        refitTimer.restart()
      }
    }
  }

  // A new scale or resolution changes the screen's logical size, and a
  // floating window keeps its old size and place, so it could end up off the
  // screen with the controls that undo the change. Size it to the screen
  // again and center it, once Hyprland has reported the new monitor size.
  function fitSize() {
    var m = Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
    var w = m ? m.width / m.scale : 1280
    var h = m ? m.height / m.scale : 800
    if (m && (m.transform || 0) % 2 === 1) { var t = w; w = h; h = t }
    return { width: Math.round(Math.min(Style.space(900), w * 0.85)), height: Math.round(Math.min(Style.space(680), h * 0.85)) }
  }

  Timer {
    id: refitTimer
    interval: 400
    onTriggered: {
      var size = root.fitSize()
      var target = '"title:^karchy Settings$"'
      refitProc.command = ["sh", "-c",
        "hyprctl dispatch 'hl.dsp.window.resize({ x = " + size.width + ", y = " + size.height + ", relative = false, window = " + target + " })' >/dev/null && " +
        "hyprctl dispatch 'hl.dsp.window.center({ window = " + target + " })' >/dev/null"]
      refitProc.running = true
    }
  }

  Process { id: refitProc }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // Sections ask before an action that removes or resets something, or
  // changes what gets installed, through this. The dialog opens on Cancel
  // either way; `destructive: false` draws the action as the primary button
  // instead of in the error color. `declineText` names the other button
  // where "Cancel" would be wrong: nothing is cancelled by "Not now". See
  // ConfirmDialog.
  function ask(message, confirmText, action, destructive, declineText) {
    confirmDialog.returnFocus = frame.Window.activeFocusItem
    confirmDialog.message = message
    confirmDialog.confirmText = confirmText
    confirmDialog.cancelText = declineText || Commons.I18n.t("common.cancel")
    confirmDialog.destructive = destructive !== false
    confirmDialog.onYes = action
    confirmDialog.onNo = null
    confirmDialog.countdown = 0
    confirmDialog.opened = true
  }

  // Asks to keep a change that could leave the screen unusable, and undoes it
  // unless kept within `seconds`: Escape, the undo button and the timer all
  // undo it. `messageFor(n)` gives the question with n seconds left. Opens on
  // the undo button, so a stray Enter undoes.
  function askToKeep(messageFor, keepText, undoText, seconds, onUndo) {
    confirmDialog.returnFocus = frame.Window.activeFocusItem
    confirmDialog.messageFor = messageFor
    confirmDialog.countdown = seconds
    confirmDialog.message = messageFor(seconds)
    confirmDialog.confirmText = keepText
    confirmDialog.cancelText = undoText
    confirmDialog.destructive = false
    confirmDialog.onYes = null
    confirmDialog.onNo = onUndo
    confirmDialog.opened = true
  }

  // Opened at one thing in the section: the section moves the keyboard there.
  function targetsItem() {
    var t = root.target || {}
    return !!(t.item || t.connection || t.device || t.anchor)
  }

  function focusSection(index) {
    var item = navRepeater.itemAt(index)
    if (item) item.forceActiveFocus()
  }

  function currentSectionIndex() {
    for (var i = 0; i < root.sections.length; i++)
      if (root.sections[i].id === root.section) return i
    return 0
  }

  // Keep the focused control on screen as Tab walks down a long page.
  //
  // A control that holds the keyboard for something else says what to show
  // with a `revealItem()` function: a list that is one Tab stop gives its
  // current row, and nothing (null) when the pointer put the keyboard there,
  // since what was clicked is on screen and must stay under the pointer.
  // Without it the whole list was "revealed": a click on a row scrolled the
  // page to the list's end or start, and the next click hit another row.
  function revealFocused(item) {
    var page = sectionLoader.item
    if (!item || !page) return
    for (var p = item; p && p !== page; p = p.parent) {}
    if (!p) return
    if (typeof item.revealItem === "function") {
      item = item.revealItem()
      if (!item) return
    }
    var margin = Style.spacing.lg
    var top = item.mapToItem(content.contentItem, 0, 0).y
    var bottom = top + item.height
    var maxY = Math.max(0, content.contentHeight - content.height)
    // Something taller than the view is shown from its start.
    var fits = item.height + margin * 2 <= content.height
    if (top - margin < content.contentY) content.contentY = Math.max(0, top - margin)
    else if (bottom + margin > content.contentY + content.height)
      content.contentY = Math.min(maxY, fits ? bottom + margin - content.height : top - margin)
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "karchy Settings"
    color: Commons.Color.background
    // Fit the screen it opens on: 900×680 where there is room (the height
    // that shows every page in the list), less where not.
    readonly property var fitScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
      ? Hyprland.focusedMonitor.lastIpcObject : null
    readonly property real screenWidth: fitScreen ? fitScreen.width / fitScreen.scale : 1280
    readonly property real screenHeight: fitScreen ? fitScreen.height / fitScreen.scale : 800
    implicitWidth: Math.round(Math.min(Style.space(900), screenWidth * 0.85))
    implicitHeight: Math.round(Math.min(Style.space(680), screenHeight * 0.85))

    onVisibleChanged: {
      if (!visible && root.opened) root.close()
      // Start on the open section's entry, so Tab and Escape work at once.
      if (visible && !root.targetsItem()) Qt.callLater(function() { root.focusSection(root.currentSectionIndex()) })
    }
    RowLayout {
      id: frame
      anchors.fill: parent
      spacing: 0
      readonly property Item focusedItem: frame.Window.activeFocusItem
      onFocusedItemChanged: root.revealFocused(focusedItem)
      // Keys the focused control leaves unhandled end up here. An open
      // dropdown's list sits in its own popup and takes Escape first.
      // A held or late-repeating Escape that just answered the dialog (a
      // display change can delay its release) doesn't also close the window.
      Keys.onEscapePressed: function(event) {
        if (event.isAutoRepeat || Date.now() - confirmDialog.closedAt < 500) return
        root.close()
      }

      // Section list
      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: Style.spacing.sidebarWidth
        color: Util.alpha(Commons.Color.foreground, 0.04)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.sm

          // The window's name, quieter than the page title beside it.
          Text {
            text: "Settings"
            color: Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            Layout.bottomMargin: Style.spacing.lg
          }

          // The pages. On a screen too low for all of them the list scrolls,
          // and the one the keyboard is on is brought into view.
          Flickable {
            id: navList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: navColumn.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            function reveal(item) {
              var top = item.y - Style.spacing.lg, bottom = item.y + item.height + Style.spacing.lg
              var maxY = Math.max(0, contentHeight - height)
              if (top < contentY) contentY = Math.max(0, top)
              else if (bottom > contentY + height) contentY = Math.min(maxY, bottom - height)
            }

            ColumnLayout {
              id: navColumn
              width: navList.width
              spacing: Style.spacing.sm

              Repeater {
                id: navRepeater
                model: root.sections
                delegate: Button {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  onActiveFocusChanged: if (activeFocus) navList.reveal(this)
                  // Where the group changes: room above, with a thin rule in it.
                  readonly property bool startsGroup: index > 0 && root.sections[index - 1].group !== modelData.group
                  Layout.topMargin: startsGroup ? Style.spacing.lg : 0
                  Rectangle {
                    visible: parent.startsGroup
                    anchors.left: parent.left
                    anchors.right: parent.right
                    y: -Math.round((Style.spacing.lg + Style.spacing.sm) / 2) - height
                    height: Math.max(1, Style.space(1))
                    color: Util.alpha(Commons.Color.foreground, 0.12)
                  }
                  focusable: true
                  function step(dy) {
                    var next = index + dy
                    if (next < 0 || next >= root.sections.length) return
                    root.section = root.sections[next].id
                    root.focusSection(next)
                  }
                  Keys.onUpPressed: step(-1)
                  Keys.onDownPressed: step(1)
                  Keys.onPressed: function(event) {
                    if (event.text === "k") { step(-1); event.accepted = true }
                    else if (event.text === "j") { step(1); event.accepted = true }
                  }
                  leftAlign: true
                  iconText: Icons.glyph(modelData.iconName)
                  text: modelData.label
                  selected: root.section === modelData.id
                  onClicked: root.section = modelData.id
                }
              }
            }
          }
        }
      }

      // Section content. The page's padding at the top and bottom is the
      // view's own margin, not part of what scrolls: a long page (the
      // keybindings, the notification apps, a disk's parts) ends at the
      // padding, and no row is cut by the window's border.
      Flickable {
        id: content
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.topMargin: Style.spacing.panelPadding
        Layout.bottomMargin: Style.spacing.panelPadding
        clip: true
        contentWidth: width
        contentHeight: sectionLoader.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        Loader {
          id: sectionLoader
          x: Style.spacing.panelPadding * 2
          width: content.width - Style.spacing.panelPadding * 4
          active: root.opened
          source: {
            switch (root.section) {
              case "input": return "InputSection.qml"
              case "keybindings": return "KeybindingsSection.qml"
              case "power": return "PowerSection.qml"
              case "notifications": return "NotificationsSection.qml"
              case "storage": return "StorageSection.qml"
              case "users": return "UsersSection.qml"
              case "security": return "SecuritySection.qml"
              case "ssh": return "SshSection.qml"
              case "datetime": return "DateTimeSection.qml"
              case "appearance": return "AppearanceSection.qml"
              case "fonts": return "FontsSection.qml"
              case "apps": return "DefaultAppsSection.qml"
              case "about": return "AboutSection.qml"
              case "displays": return "DisplaysSection.qml"
              case "bluetooth": return "BluetoothSection.qml"
              case "sound": return "SoundSection.qml"
              default: return "NetworkSection.qml"
            }
          }
          onLoaded: {
            if ("settings" in item) item.settings = root
            if ("target" in item) item.target = root.target
          }
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      ownsKeys: true
      defaultIndex: 0
      property var onYes: null
      property var onNo: null
      property Item returnFocus: null
      // askToKeep: seconds left, and the question for that many.
      property int countdown: 0
      property var messageFor: null
      property real closedAt: 0
      function finish() {
        closedAt = Date.now()
        opened = false
        onYes = null
        onNo = null
        countdown = 0
        messageFor = null
        if (returnFocus) returnFocus.forceActiveFocus()
        returnFocus = null
      }
      onCanceled: {
        var action = onNo
        finish()
        if (typeof action === "function") action()
      }
      onConfirmed: {
        var action = onYes
        finish()
        if (typeof action === "function") action()
      }
      Timer {
        interval: 1000
        repeat: true
        running: confirmDialog.opened && confirmDialog.countdown > 0
        onTriggered: {
          confirmDialog.countdown -= 1
          if (confirmDialog.countdown <= 0) confirmDialog.canceled()
          else if (confirmDialog.messageFor) confirmDialog.message = confirmDialog.messageFor(confirmDialog.countdown)
        }
      }
    }
  }
}
