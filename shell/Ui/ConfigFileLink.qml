import Quickshell
import QtQuick
import qs.Commons
import qs.Commons as Commons

// A quiet link from a window page to a config file of the person's own, the
// one they can edit by hand (D-133). It sits in the page's header, after the
// title, on every Settings page whose area has such a file:
//
//   PageHeader {
//     title: "Input"
//     explanation: "A setting in input.lua wins over the one here."
//     ConfigFileLink { file: ".config/hypr/input.lua" }
//   }
//
// `file` is relative to the home folder. Link a file the person owns, never
// one karchy generates under ~/.local/state. The editor is the default one
// (karchy-launch-config-editor); a file that isn't there yet is made from
// karchy's starter for it, or empty. Where the file wins over the page's
// controls, the page's (i) says so in one line.
//
// `closes` is the window the page is in, when that window floats above
// everything else (Settings): it steps aside, since the editor opens under it.
Button {
  id: root

  property string file: ""
  // What the link reads as: the file's name, or a clearer one ("ssh config").
  property string label: file.split("/").pop()
  // An object with close(), closed once the editor is asked for.
  property var closes: null

  visible: file !== ""
  focusable: true
  iconText: Icons.glyph("config")
  text: label
  // A file's name is read as code (D-149).
  fontFamily: Style.font.mono
  fontSize: Style.font.bodySmall
  foreground: Commons.Color.textSecondary
  tooltipText: "Open ~/" + file + " in your editor"
  accessibleName: "Open the config file ~/" + file

  onClicked: {
    Quickshell.execDetached(["karchy-launch-config-editor", Quickshell.env("HOME") + "/" + file])
    if (closes && typeof closes.close === "function") closes.close()
  }
}
