.pragma library

// Settings › Keybindings: what the page works out for itself. The list, the
// layers and every change are karchy-settings-keybindings's; this is the
// search, the grouping and turning a key press into keys as Hyprland writes
// them. Tested by tests/keybindings-model.js.

// Qt's key and modifier numbers (Qt::Key, Qt::KeyboardModifier).
var MOD_SHIFT = 0x02000000, MOD_CTRL = 0x04000000, MOD_ALT = 0x08000000, MOD_META = 0x10000000
var NAMED = {
  0x01000000: "ESCAPE", 0x01000001: "TAB", 0x01000002: "TAB", 0x01000003: "BACKSPACE", 0x01000004: "RETURN",
  0x01000005: "KP_Enter", 0x01000006: "INSERT", 0x01000007: "DELETE", 0x01000009: "PRINT", 0x01000010: "HOME",
  0x01000011: "END", 0x01000012: "LEFT", 0x01000013: "UP", 0x01000014: "RIGHT", 0x01000015: "DOWN",
  0x01000016: "PRIOR", 0x01000017: "NEXT", 0x20: "SPACE"
}
// Shift, Control, Meta, Alt, AltGr, CapsLock, NumLock, ScrollLock, Super_L/R, Hyper_L/R
var MODIFIER_KEYS = [0x01000020, 0x01000021, 0x01000022, 0x01000023, 0x01001103, 0x01000024, 0x01000025, 0x01000026, 0x01000053, 0x01000054, 0x01000055, 0x01000056]

var MOD_NAMES = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MOD_LABELS = { SUPER: "Super", CTRL: "Ctrl", ALT: "Alt", SHIFT: "Shift" }

// A key press as keys Hyprland binds: { keys: "SUPER + SHIFT + T", mods:
// ["Super", "Shift"], complete }. Letters, function keys and the named keys
// go by name; everything else (digits, punctuation, media keys) by its
// keycode, which means the same key on every layout, as karchy's own
// defaults write them. `complete` is false while only modifiers are down.
function captureKeys(key, modifiers, scanCode) {
  var mods = []
  if (modifiers & MOD_META) mods.push("SUPER")
  if (modifiers & MOD_CTRL) mods.push("CTRL")
  if (modifiers & MOD_ALT) mods.push("ALT")
  if (modifiers & MOD_SHIFT) mods.push("SHIFT")
  var labels = mods.map(function(mod) { return MOD_LABELS[mod] })

  if (MODIFIER_KEYS.indexOf(key) >= 0 || key === 0 || key === 0x01ffffff)
    return { keys: "", mods: labels, complete: false }

  var name = ""
  if (key >= 0x41 && key <= 0x5a) name = String.fromCharCode(key)
  else if (key >= 0x01000030 && key <= 0x01000052) name = "F" + (key - 0x01000030 + 1)
  else if (NAMED[key]) name = NAMED[key]
  else if (scanCode > 0) name = "code:" + scanCode
  if (name === "") return { keys: "", mods: labels, complete: false }

  return { keys: mods.concat([name]).join(" + "), mods: labels, complete: true }
}

// Unmodified Enter accepts and unmodified Escape cancels, as in VS Code's
// editor, so neither can be bound here by itself.
function isPlain(key, modifiers, which) {
  if (modifiers & (MOD_META | MOD_CTRL | MOD_ALT | MOD_SHIFT)) return false
  if (which === "enter") return key === 0x01000004 || key === 0x01000005
  return key === 0x01000000
}

// Key caps for keys the command has not labelled yet.
function roughLabels(keys) {
  return String(keys || "").split("+").map(function(part) {
    var word = part.trim()
    if (MOD_LABELS[word.toUpperCase()]) return MOD_LABELS[word.toUpperCase()]
    if (word === "RETURN" || word === "KP_Enter") return "Enter"
    if (word === "ESCAPE") return "Esc"
    if (word.indexOf("code:") === 0) return "…"
    return word.length === 1 ? word : word.charAt(0) + word.slice(1).toLowerCase()
  }).filter(function(label) { return label !== "" })
}

var FILTERS = [
  { value: "all", label: "All" },
  { value: "changed", label: "Changed" },
  { value: "yours", label: "Yours" },
  { value: "addons", label: "Add-ons" },
  { value: "conflicts", label: "Conflicts" }
]

// Changed: anything that isn't as karchy or an add-on ships it. Yours: set
// by the person's own files. Add-ons: an add-on's binding, changed or not.
function matchesFilter(row, filter) {
  if (filter === "changed") return row.state !== "default"
  if (filter === "yours") return row.layer === "user" || row.chain.some(function(link) { return link.layer === "user" })
  if (filter === "addons") return row.chain.some(function(link) { return link.layer === "addon" })
  if (filter === "conflicts") return row.conflicts.length > 0
  return true
}

// Every word of the search must be somewhere in the row: the action, its keys
// now or before ("super+t" and "super t" both find Super+T), where it comes
// from, or what it runs.
function searchText(row) {
  var parts = [row.action, row.source, row.what, row.group]
  var keys = [row.labels].concat(row.chain.map(function(link) { return link.labels }))
  for (var i = 0; i < keys.length; i++) {
    parts.push(keys[i].join("+"))
    parts.push(keys[i].join(" "))
  }
  for (var j = 0; j < row.chain.length; j++) parts.push(row.chain[j].action)
  return parts.join("\n").toLowerCase()
}

function matchesSearch(row, text) {
  var words = String(text || "").toLowerCase().trim().split(/\s+/)
  var hay = searchText(row)
  for (var i = 0; i < words.length; i++)
    if (words[i] !== "" && hay.indexOf(words[i]) < 0) return false
  return true
}

// The rows to show: `ids`, when given, are the rows on the keys that were
// recorded (the command's answer), and replace the text search.
function visibleRows(rows, text, filter, ids) {
  return (rows || []).filter(function(row) {
    if (!matchesFilter(row, filter)) return false
    if (ids) return ids.indexOf(row.id) >= 0
    return matchesSearch(row, text)
  })
}

// Groups in the order of docs/keybindings.md, then whatever add-ons and the
// person brought, each group's rows in the order the bindings were made.
var GROUP_ORDER = ["Windows", "Workspaces and monitors", "Clipboard", "Shell and system", "Apps", "Capture", "Hardware keys"]
var GROUPS_LAST = ["Your own", "Other"]

function grouped(rows) {
  var byName = {}, names = []
  for (var i = 0; i < rows.length; i++) {
    var name = rows[i].group || "Other"
    if (!byName[name]) { byName[name] = []; names.push(name) }
    byName[name].push(rows[i])
  }
  var rank = function(name) {
    var first = GROUP_ORDER.indexOf(name)
    if (first >= 0) return first
    var last = GROUPS_LAST.indexOf(name)
    return last >= 0 ? 1000 + last : 100 + names.indexOf(name)
  }
  names.sort(function(a, b) { return rank(a) - rank(b) })
  return names.map(function(name) { return { name: name, rows: byName[name] } })
}

// The history of a row, lowest layer first, for the line under it. Shown when
// there is something to say: more than one layer, or a binding taken away.
function chainShown(row) {
  return row.chain.length > 1 || row.state === "removed"
}

function chainNote(link) {
  if (link.state === "wins") return "wins"
  return (link.state === "removed" ? "removed" : "replaced") + (link.by ? " in " + link.by : "")
}

if (typeof module !== "undefined") {
  module.exports = {
    captureKeys: captureKeys, isPlain: isPlain, roughLabels: roughLabels, FILTERS: FILTERS,
    matchesFilter: matchesFilter, matchesSearch: matchesSearch, visibleRows: visibleRows,
    grouped: grouped, chainShown: chainShown, chainNote: chainNote
  }
}
