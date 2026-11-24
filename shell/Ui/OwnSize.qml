import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Keeps a shell window that floats at the size it gives itself (D-175).
//
// On a floating workspace Hyprland's rule opens karchy's windows at the size
// default/hypr/apps names for each, which is the window's own at the default
// text size. With larger text the window wants more, and after a monitor's
// scale or resolution changes it wants what fits the screen now: `refit()`
// asks Hyprland to size the window to `width` by `height` and center it.
// It does nothing to a tile, nor to a window that already has that size
// (`refit(true)` centers that one too: the screen under it changed).
//
//   OwnSize {
//     id: ownSize
//     title: root.windowTitle
//     active: root.opened
//     width: window.implicitWidth
//     height: window.implicitHeight
//   }
//
// It runs on Hyprland's own event for the window opening, never on a timer.
// A window floated later (Super+T, a workspace set to float) gets the size
// the floating mode gives every app window, and keeps it.
Item {
  id: root

  // The window's title, as Hyprland's rules match it.
  property string title: ""
  // The window is open.
  property bool active: false

  visible: false

  function refit(always) {
    if (root.title === "" || root.width <= 0 || root.height <= 0) return
    var w = Math.round(root.width), h = Math.round(root.height)
    var target = '"title:^' + root.title + '$"'
    proc.command = ["sh", "-c",
      "hyprctl -j clients | jq -e --arg t \"$1\" --argjson w \"$2\" --argjson h \"$3\" --argjson always \"$4\" "
        + "'any(.[]; .title == $t and .floating and .fullscreen == 0 and ($always or .size != [$w, $h]))' >/dev/null || exit 0; "
        + "hyprctl dispatch 'hl.dsp.window.resize({ x = " + w + ", y = " + h + ", relative = false, window = " + target + " })' >/dev/null && "
        + "hyprctl dispatch 'hl.dsp.window.center({ window = " + target + " })' >/dev/null",
      "own-size", root.title, String(w), String(h), always === true ? "true" : "false"]
    proc.running = true
  }

  Connections {
    target: Hyprland
    enabled: root.active
    function onRawEvent(event) {
      // openwindow>>ADDRESS,WORKSPACE,CLASS,TITLE
      if (String(event.name) !== "openwindow") return
      var data = String(event.data)
      if (data.slice(-(root.title.length + 1)) === "," + root.title) root.refit()
    }
  }

  Process { id: proc }
}
