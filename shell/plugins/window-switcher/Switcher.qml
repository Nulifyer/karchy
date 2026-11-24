import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "SwitcherModel.js" as Model

// The windows of an Alt+Tab walk, while Alt is held (D-165).
//
// This draws and decides nothing. Which windows, in which order and where the
// walk stands is kept by default/hypr/window-switch.lua, which sends every
// change as a `custom` event on Hyprland's event socket (SwitcherModel.js has
// the form). The keys are Hyprland's binds and the switch happens there when
// Alt is let go, so they work the same with this plugin off, and the picture
// cannot say one window while the keys go to another.
//
// It takes neither the keyboard nor the pointer, so the window in use keeps
// both until the switch.
Item {
  id: root

  // A walk is on, as Hyprland last said.
  property bool walking: false
  // The picture is up: the walk has lasted past a quick Alt+Tab.
  property bool opened: false
  property var windows: []
  property int target: -1

  readonly property int pad: Style.spacing.panelPadding
  readonly property int gap: Style.spacing.lg
  readonly property int tileWidth: Style.space(148)
  readonly property int tilePad: Style.spacing.xxl
  readonly property int iconSize: Style.space(48)
  readonly property int badgeSize: Style.space(18)
  readonly property int titleLines: 2

  // Hyprland's window list, by address, read when the walk says something.
  function toplevels() {
    var found = ({})
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) found[String(values[i].address).toLowerCase()] = values[i]
    return found
  }

  function apply(state) {
    if (!state.shown) {
      holdTimer.stop()
      root.walking = false
      root.opened = false
      root.windows = []
      root.target = -1
      return
    }

    var known = root.toplevels()
    root.windows = state.windows.map(function(entry) {
      return { address: entry.address, minimized: entry.minimized, toplevel: known[entry.address] || null }
    })
    root.target = state.target

    if (!root.walking) {
      root.walking = true
      holdTimer.restart()
    } else if (!root.opened) {
      // A second Tab: this is a walk, not a quick switch.
      holdTimer.stop()
      root.opened = true
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event.name) !== "custom") return
      var state = Model.parse(event.data)
      if (state) root.apply(state)
    }
  }

  Timer {
    id: holdTimer
    interval: Model.HOLD_MS
    onTriggered: if (root.walking) root.opened = true
  }

  ShellIpc {
    target: "window-switcher"
    function state(): string { return root.opened ? "open" : (root.walking ? "walking" : "closed") }
    function ping(): string { return "ok" }
  }

  OverlayWindow {
    id: panel
    shown: root.opened
    shownKeyboardFocus: WlrKeyboardFocus.None
    WlrLayershell.namespace: "karchy-window-switcher"
    // Nothing here is clicked: the pointer stays with the windows below.
    mask: Region {}

    BorderSurface {
      id: card

      readonly property int available: panel.width - Style.space(96) - 2 * root.pad
      readonly property int columns: Model.columns(root.windows.length, root.tileWidth, root.gap, available)

      anchors.centerIn: parent
      width: card.borderLeft + root.pad + grid.width + root.pad + card.borderRight
      height: card.borderTop + root.pad + grid.height + root.pad + card.borderBottom
      color: Commons.Color.popups.background
      borderSpec: Border.surfaceSpec("popups", "border", Commons.Color.popups.border, Style.border.surface)
      radius: Style.radius.surface
      opacity: root.opened ? 1 : 0

      Behavior on opacity {
        enabled: root.opened
        NumberAnimation { duration: Style.duration(Style.motion.fast); easing.type: Easing.OutCubic }
      }

      Grid {
        id: grid
        x: card.borderLeft + root.pad
        y: card.borderTop + root.pad
        columns: card.columns
        spacing: root.gap
        horizontalItemAlignment: Grid.AlignHCenter

        Repeater {
          model: root.windows

          Rectangle {
            id: tile
            required property var modelData
            required property int index

            readonly property var toplevel: modelData.toplevel
            readonly property bool current: index === root.target
            readonly property bool minimized: modelData.minimized
            readonly property string app: {
              if (!toplevel) return ""
              if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
              return toplevel.lastIpcObject && toplevel.lastIpcObject.class ? String(toplevel.lastIpcObject.class) : ""
            }
            readonly property string title: Model.label(toplevel ? toplevel.title : "", app)
            // The app's own icon: its desktop entry's, else one the icon
            // theme has under the app's name. Nothing found: a letter.
            readonly property string iconSource: {
              var revision = DesktopEntries.applications.values.length
              if (app === "") return ""
              var entry = DesktopEntries.heuristicLookup(app)
              var name = entry && entry.icon ? String(entry.icon) : ""
              if (name.charAt(0) === "/") return Util.fileUrl(name)
              return (name !== "" ? Quickshell.iconPath(name, true) : "")
                || Quickshell.iconPath(app, true) || Quickshell.iconPath(app.toLowerCase(), true)
            }

            width: root.tileWidth
            height: root.tilePad + root.iconSize + Style.spacing.lg + titleMetrics.height * root.titleLines + root.tilePad
            radius: Style.radius.control
            color: tile.current ? Style.selectedAccentFill : "transparent"
            border.width: tile.current ? Style.border.surface : 0
            border.color: Commons.Color.accent

            Item {
              id: icon
              width: root.iconSize
              height: root.iconSize
              y: root.tilePad
              anchors.horizontalCenter: parent.horizontalCenter
              // A minimized window is not on the screen: its icon is dimmed
              // and carries the minimized mark.
              opacity: tile.minimized ? 0.45 : 1

              Image {
                id: picture
                anchors.fill: parent
                source: tile.iconSource
                sourceSize.width: root.iconSize * 2
                sourceSize.height: root.iconSize * 2
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                visible: status === Image.Ready
              }

              Rectangle {
                anchors.fill: parent
                visible: !picture.visible
                radius: Style.radius.control
                color: Style.normalFillFor(Commons.Color.popups.text, Commons.Color.accent, Commons.Color.urgent)

                Text {
                  textFormat: Text.PlainText
                  anchors.centerIn: parent
                  text: Model.initial(tile.app, tile.title)
                  color: Commons.Color.popups.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.display
                  font.weight: Font.DemiBold
                }
              }
            }

            Rectangle {
              visible: tile.minimized
              width: root.badgeSize
              height: root.badgeSize
              radius: width / 2
              anchors.right: icon.right
              anchors.bottom: icon.bottom
              anchors.rightMargin: -Style.spacing.sm
              anchors.bottomMargin: -Style.spacing.sm
              color: Commons.Color.popups.background
              border.width: Style.spacing.hairline
              border.color: Commons.Color.textSecondary

              Text {
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: Icons.glyph("window.minimized")
                color: Commons.Color.popups.text
                font.family: Icons.family
                font.pixelSize: Style.font.iconSmall
              }
            }

            TextMetrics {
              id: titleMetrics
              font: label.font
              text: "Xg"
            }

            Text {
              id: label
              textFormat: Text.PlainText
              anchors.top: icon.bottom
              anchors.topMargin: Style.spacing.lg
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.leftMargin: Style.spacing.lg
              anchors.rightMargin: Style.spacing.lg
              text: tile.title
              color: tile.minimized && !tile.current ? Commons.Color.textSecondary : Commons.Color.popups.text
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.weight: tile.current ? Font.DemiBold : Font.Normal
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.Wrap
              elide: Text.ElideRight
              maximumLineCount: root.titleLines
            }
          }
        }
      }
    }
  }
}
