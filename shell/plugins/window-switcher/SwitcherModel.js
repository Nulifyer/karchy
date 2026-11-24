// What Hyprland says about an Alt+Tab walk, read into what the switcher
// draws. The walk itself (which windows, in which order, where it stands) is
// kept by default/hypr/window-switch.lua and nowhere else; it sends every
// change as one event on Hyprland's event socket:
//
//   custom>>karchy-window-switch show 2 0x55d0a 0x55d0b* 0x55d0c
//   custom>>karchy-window-switch hide
//
// "show": the place of the window the walk stands on, counted from 1, then
// the windows in the walk's order, a minimized one marked with a star.
.pragma library

var EVENT = "karchy-window-switch"

// Windows shows its switcher after a short hold, so a quick Alt+Tab switches
// with nothing drawn. A second Tab is no longer quick: it shows at once.
var HOLD_MS = 150

// The data of a `custom` event -> null for somebody else's event,
// { shown: false } for "hide", or { shown: true, target, windows }.
function parse(data) {
  var words = String(data || "").split(" ").filter(function(word) { return word !== "" })
  if (words[0] !== EVENT) return null
  if (words[1] !== "show") return { shown: false, target: -1, windows: [] }

  var windows = []
  for (var i = 3; i < words.length; i++) {
    var minimized = words[i].charAt(words[i].length - 1) === "*"
    var address = address_of(minimized ? words[i].slice(0, -1) : words[i])
    if (address) windows.push({ address: address, minimized: minimized })
  }

  var target = parseInt(words[2], 10) - 1
  if (!(target >= 0 && target < windows.length)) target = windows.length > 0 ? 0 : -1
  return { shown: windows.length > 0, target: target, windows: windows }
}

// Hyprland writes an address as 0x55d0a; Quickshell's window list as 55d0a.
function address_of(text) {
  var address = String(text || "").toLowerCase().replace(/^0x/, "")
  return /^[0-9a-f]+$/.test(address) ? address : ""
}

// A window's name in the list: its title, or its app when it has none.
function label(title, app) {
  var text = String(title || "").replace(/\s+/g, " ").trim()
  return text !== "" ? text : String(app || "").trim()
}

// karchy's own windows are the shell's: one app id for all of them and no
// desktop entry (shell/shell.qml), so the title says which window it is. Each
// gets the icon the menu and its own pages show for it, from the icon map.
// The titles are the plugins' names (their manifest.json); the test holds
// this list to them and to the map.
var OWN_ICONS = {
  "Settings": "settings",
  "Quick install": "quick-install",
  "Updates": "update",
  "Virtual machines": "vms",
  "Containers": "containers"
}

// The icon map's name for one of the shell's own windows, "" for any other.
function ownIcon(title) {
  var name = String(title || "").trim()
  return Object.prototype.hasOwnProperty.call(OWN_ICONS, name) ? OWN_ICONS[name] : ""
}

// The letter drawn for an app that has no icon.
function initial(app, title) {
  var text = String(app || "").trim() || String(title || "").trim()
  var match = /[A-Za-z0-9]/.exec(text.split(".").pop() || text)
  return match ? match[0].toUpperCase() : "?"
}

// How many tiles go in a row: all of them when they fit the screen.
function columns(count, tileWidth, gap, available) {
  if (count <= 0) return 1
  var fit = Math.max(1, Math.floor((available + gap) / (tileWidth + gap)))
  if (count <= fit) return count
  // Rows of equal length rather than one full row and a stub.
  return Math.ceil(count / Math.ceil(count / fit))
}
