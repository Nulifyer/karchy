// The Alt+Tab switcher's reading of what Hyprland tells it (D-165):
// shell/plugins/window-switcher/SwitcherModel.js against the events
// default/hypr/window-switch.lua sends (tests/window-stacking.lua checks those).
//
//   bun tests/window-switcher.js "$PWD"      (or node)
const assert = require("assert")
const fs = require("fs")
const root = process.argv[2] || "."
// A QML library (.pragma): load its functions without that line.
const src = fs.readFileSync(root + "/shell/plugins/window-switcher/SwitcherModel.js", "utf8").replace(/^\.(pragma|import).*$/gm, "")
const M = new Function(src + "\nreturn { parse: parse, label: label, initial: initial, columns: columns, EVENT: EVENT, HOLD_MS: HOLD_MS }")()
const eq = (got, want, what) => assert.deepStrictEqual(got, want, what)

// A walk: the target counted from 1, the windows in order, a minimized one starred.
eq(M.parse("karchy-window-switch show 2 0x55D0a 0x55d0b 0x55d0c*"), {
  shown: true,
  target: 1,
  windows: [
    { address: "55d0a", minimized: false },
    { address: "55d0b", minimized: false },
    { address: "55d0c", minimized: true },
  ],
}, "addresses as Quickshell writes them, the target from 0")
eq(M.parse("karchy-window-switch hide"), { shown: false, target: -1, windows: [] })
// Another program's custom event is not the switcher's.
eq(M.parse("something else"), null)
eq(M.parse(""), null)
eq(M.parse("karchy-window-switcher show 1 0x1"), null, "a longer name is another event")
// Nothing to show, a target that is not there, a word that is no address.
eq(M.parse("karchy-window-switch show 1").shown, false)
eq(M.parse("karchy-window-switch show 9 0x1 0x2").target, 0)
eq(M.parse("karchy-window-switch show 1 0x1 junk; 0x2").windows.map(w => w.address), ["1", "2"])
// The quick Alt+Tab that draws nothing is shorter than a deliberate hold.
assert.ok(M.HOLD_MS >= 100 && M.HOLD_MS <= 250)

// The name in the list: the title, or the app when there is none.
eq(M.label("  notes.txt\n- Editor ", "editor"), "notes.txt - Editor")
eq(M.label("", "org.example.App"), "org.example.App")
eq(M.initial("org.gnome.Evince", ""), "E")
eq(M.initial("", "~"), "?")
eq(M.initial("foot", ""), "F")

// All tiles in one row while they fit; otherwise rows of equal length.
eq(M.columns(4, 148, 8, 1100), 4)
eq(M.columns(7, 148, 8, 1100), 7)
eq(M.columns(8, 148, 8, 1100), 4, "eight windows where seven fit: two rows of four")
eq(M.columns(15, 148, 8, 1100), 5)
eq(M.columns(0, 148, 8, 1100), 1)
eq(M.columns(3, 148, 8, 100), 1, "a screen narrower than a tile still gets one column")
console.log("window switcher ok")
