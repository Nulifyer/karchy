pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// The shell's icons by name. default/karchy/icons.json is the one map from
// concept names ("system.lock", "net.wifi.3") to Nerd Font codepoints;
// scripts read the same file through bin/karchy-icon (docs/architecture.md,
// "Shell design foundations").
//
//   Text {
//     text: Icons.glyph("system.lock")
//     font.family: Icons.family
//   }
//
// Glyphs are drawn in the Symbols Nerd Font, never the text font, so icons
// stay the same when `karchy font set` changes the monospace font. Shared
// controls (Button, PanelActionButton, BarIconButton, OpticalGlyph) already
// use Icons.family; a plugin's own glyph Text sets it.
QtObject {
  id: root

  readonly property string karchyPath: Quickshell.env("KARCHY_PATH")
  readonly property string family: "Symbols Nerd Font Mono"

  // name -> glyph string. Rebuilt when the map file changes.
  readonly property var glyphs: parse(mapFile.text())

  function parse(raw) {
    var out = ({})
    var parsed
    try {
      parsed = JSON.parse(raw || "{}")
    } catch (e) {
      return out
    }
    for (var name in parsed) {
      var entry = parsed[name]
      var code = parseInt(entry && entry.cp, 16)
      if (isFinite(code) && code > 0) out[name] = String.fromCodePoint(code)
    }
    return out
  }

  // The glyph for a map name; "" (and a warning) for a name the map lacks.
  function glyph(name) {
    var g = root.glyphs[name]
    if (g !== undefined) return g
    if (name) console.warn("Icons: no icon named", name)
    return ""
  }

  function has(name) {
    return root.glyphs[name] !== undefined
  }

  // For icons that arrive from outside the shell (menu JSONC, dmenu rows,
  // OSD requests): a map name becomes its glyph, anything else (a glyph a
  // user or a plugin wrote) is kept as it is.
  function resolve(value) {
    var g = root.glyphs[value]
    return g !== undefined ? g : String(value || "")
  }

  property FileView mapFile: FileView {
    path: root.karchyPath + "/default/karchy/icons.json"
    watchChanges: true
    printErrors: false
    blockLoading: true
    onFileChanged: reload()
  }
}
