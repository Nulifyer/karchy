// Settings › Keybindings' own logic (KeybindingsModel.js): a key press as
// Hyprland keys, the search, the filters and the grouping.
// Run: bun tests/keybindings-model.js "$PWD"
const assert = require("assert")
const fs = require("fs")
const root = process.argv[2] || "."
// The file is a QML library (.pragma), which is not JavaScript: load it without that line.
const source = fs.readFileSync(root + "/shell/plugins/settings/KeybindingsModel.js", "utf8").replace(/^\.pragma library$/m, "")
const M = {}
new Function("module", source)({ set exports(value) { Object.assign(M, value) } })
const eq = (a, b, msg) => assert.deepStrictEqual(a, b, msg)

const SHIFT = 0x02000000, CTRL = 0x04000000, ALT = 0x08000000, META = 0x10000000
// letters by name, modifiers in one order
eq(M.captureKeys(0x54, META, 28), { keys: "SUPER + T", mods: ["Super"], complete: true })
eq(M.captureKeys(0x54, SHIFT | META | CTRL | ALT, 28).keys, "SUPER + CTRL + ALT + SHIFT + T")
// named keys, function keys
eq(M.captureKeys(0x01000004, META, 36).keys, "SUPER + RETURN")
eq(M.captureKeys(0x01000000, META, 9).keys, "SUPER + ESCAPE")
eq(M.captureKeys(0x01000012, META | SHIFT, 113).keys, "SUPER + SHIFT + LEFT")
eq(M.captureKeys(0x01000030, 0, 67).keys, "F1")
eq(M.captureKeys(0x0100003b, CTRL, 96).keys, "CTRL + F12")
eq(M.captureKeys(0x01000002, ALT | SHIFT, 23).keys, "ALT + SHIFT + TAB", "Shift+Tab arrives as Backtab")
// digits and punctuation by keycode: Shift+1 is "!" to Qt, and still the 1 key
eq(M.captureKeys(0x21, META | SHIFT, 10).keys, "SUPER + SHIFT + code:10")
eq(M.captureKeys(0x2d, META, 20).keys, "SUPER + code:20")
// a media key with no name of its own
eq(M.captureKeys(0x01000070, 0, 122).keys, "code:122")
// only modifiers down: not a combination yet
eq(M.captureKeys(0x01000022, META, 133), { keys: "", mods: ["Super"], complete: false })
eq(M.captureKeys(0x01000020, META | SHIFT, 50).complete, false)
eq(M.captureKeys(0x7e, 0, 0).complete, false, "a key with no name and no keycode")
// Enter accepts and Escape cancels only without modifiers
eq([M.isPlain(0x01000004, 0, "enter"), M.isPlain(0x01000004, META, "enter"), M.isPlain(0x01000000, 0, "escape"), M.isPlain(0x01000000, META, "escape")], [true, false, true, false])
eq(M.roughLabels("SUPER + SHIFT + T"), ["Super", "Shift", "T"])

const link = (layer, source, labels, state, by) => ({ layer, source, labels, state, by, action: "x", keys: labels.join(" + ") })
const rows = [
  { id: "a", action: "Terminal", group: "Apps", labels: ["Super", "T"], source: "Settings", layer: "settings", state: "changed", what: "karchy-launch-terminal", conflicts: [],
    chain: [link("default", "karchy", ["Super", "Enter"], "replaced", "Settings"), link("settings", "Settings", ["Super", "T"], "wins")] },
  { id: "b", action: "Close window", group: "Windows", labels: ["Alt", "F4"], source: "karchy", layer: "default", state: "default", what: "", conflicts: [],
    chain: [link("default", "karchy", ["Alt", "F4"], "wins")] },
  { id: "c", action: "Project picker", group: "Project picker", labels: ["Ctrl", "Alt", "P"], source: "Project picker", layer: "addon", state: "default", what: "", conflicts: ["SSH"],
    chain: [link("addon", "Project picker", ["Ctrl", "Alt", "P"], "wins")] },
  { id: "d", action: "SSH", group: "Your own", labels: ["Ctrl", "Alt", "P"], source: "your bindings.lua", layer: "user", state: "yours", what: "footclient ssh my-server", conflicts: ["Project picker"],
    chain: [link("user", "your bindings.lua", ["Ctrl", "Alt", "P"], "wins")] },
  { id: "e", action: "File manager", group: "Apps", labels: [], source: "Settings", layer: "settings", state: "removed", what: "karchy-launch-files", conflicts: [],
    chain: [link("default", "karchy", ["Super", "E"], "removed", "Settings")] }
]
const ids = (text, filter, only) => M.visibleRows(rows, text, filter, only).map(r => r.id)
eq(ids("", "all"), ["a", "b", "c", "d", "e"])
eq(ids("term", "all"), ["a"], "by action")
eq(ids("super+t", "all"), ["a"], "by keys")
eq(ids("super enter", "all"), ["a"], "by the keys it had before")
eq(ids("my-server", "all"), ["d"], "by what it runs")
eq(ids("ctrl alt", "all"), ["c", "d"])
eq(ids("nothing here", "all"), [])
eq(ids("", "changed"), ["a", "d", "e"])
eq(ids("", "yours"), ["d"])
eq(ids("", "addons"), ["c"])
eq(ids("", "conflicts"), ["c", "d"])
eq(ids("anything", "all", ["b", "e"]), ["b", "e"], "recorded keys replace the text")
eq(ids("", "changed", ["b", "e"]), ["e"], "and the filter still applies")

eq(M.grouped(rows).map(g => [g.name, g.rows.map(r => r.id)]), [["Windows", ["b"]], ["Apps", ["a", "e"]], ["Project picker", ["c"]], ["Your own", ["d"]]])
eq([M.chainShown(rows[0]), M.chainShown(rows[1]), M.chainShown(rows[4])], [true, false, true])
eq([M.chainNote(rows[0].chain[0]), M.chainNote(rows[0].chain[1]), M.chainNote(rows[4].chain[0])], ["replaced in Settings", "wins", "removed in Settings"])
console.log("keybindings-model: ok")
