import Quickshell
import Quickshell.Hyprland
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
  property string section: "displays"
  // What the section was opened at, from the summon payload.
  property var target: ({})
  onSectionChanged: if (!root.target || root.target.section !== root.section) root.target = ({})

  readonly property var sections: [
    { id: "displays", label: "Displays", iconName: "display" },
    { id: "input", label: "Input", iconName: "input.keyboard" },
    { id: "network", label: "Network", iconName: "net.network" },
    { id: "appearance", label: "Appearance", iconName: "menu.appearance" },
    { id: "apps", label: "Default apps", iconName: "menu.apps" },
    { id: "features", label: "Optional features", iconName: "features" },
    { id: "about", label: "About", iconName: "info" }
  ]

  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    if (payload && payload.section) root.section = String(payload.section)
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
      if (name.indexOf("monitor") === 0 || name === "configreloaded") root.refresh()
    }
  }

  function toggle() {
    if (root.opened) root.close()
    else root.open("{}")
  }

  // Sections ask before an action that removes or resets something, or
  // changes what gets installed, through this. The dialog opens on Cancel
  // either way; `destructive: false` draws the action as the primary button
  // instead of in the error color. See ConfirmDialog.
  function ask(message, confirmText, action, destructive) {
    confirmDialog.returnFocus = frame.Window.activeFocusItem
    confirmDialog.message = message
    confirmDialog.confirmText = confirmText
    confirmDialog.destructive = destructive !== false
    confirmDialog.onYes = action
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
  function revealFocused(item) {
    var page = sectionLoader.item
    if (!item || !page) return
    for (var p = item; p && p !== page; p = p.parent) {}
    if (!p) return
    var margin = Style.spacing.panelPadding
    var top = item.mapToItem(content.contentItem, 0, 0).y
    var bottom = top + item.height
    var maxY = Math.max(0, content.contentHeight - content.height)
    if (top - margin < content.contentY) content.contentY = Math.max(0, top - margin)
    else if (bottom + margin > content.contentY + content.height)
      content.contentY = Math.min(maxY, bottom + margin - content.height)
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: "karchy Settings"
    color: Commons.Color.background
    // Fit the screen it opens on: 900×640 where there is room, less where not.
    readonly property var fitScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
      ? Hyprland.focusedMonitor.lastIpcObject : null
    readonly property real screenWidth: fitScreen ? fitScreen.width / fitScreen.scale : 1280
    readonly property real screenHeight: fitScreen ? fitScreen.height / fitScreen.scale : 800
    implicitWidth: Math.round(Math.min(Style.space(900), screenWidth * 0.85))
    implicitHeight: Math.round(Math.min(Style.space(640), screenHeight * 0.85))

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
      Keys.onEscapePressed: root.close()

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

          Repeater {
            id: navRepeater
            model: root.sections
            delegate: Button {
              required property var modelData
              required property int index
              Layout.fillWidth: true
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

          Item { Layout.fillHeight: true }
        }
      }

      // Section content
      Flickable {
        id: content
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: sectionLoader.implicitHeight + Style.spacing.panelPadding * 2
        boundsBehavior: Flickable.StopAtBounds

        Loader {
          id: sectionLoader
          x: Style.spacing.panelPadding * 2
          y: Style.spacing.panelPadding
          width: content.width - Style.spacing.panelPadding * 4
          active: root.opened
          source: {
            switch (root.section) {
              case "input": return "InputSection.qml"
              case "network": return "NetworkSection.qml"
              case "appearance": return "AppearanceSection.qml"
              case "apps": return "DefaultAppsSection.qml"
              case "features": return "FeaturesSection.qml"
              case "about": return "AboutSection.qml"
              default: return "DisplaysSection.qml"
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
      property Item returnFocus: null
      function finish() {
        opened = false
        onYes = null
        if (returnFocus) returnFocus.forceActiveFocus()
        returnFocus = null
      }
      onCanceled: finish()
      onConfirmed: {
        var action = onYes
        finish()
        if (typeof action === "function") action()
      }
    }
  }
}
