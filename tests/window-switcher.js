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
const M = new Function(src + "\nreturn { parse: parse, label: label, initial: initial, ownIcon: ownIcon, OWN_ICONS: OWN_ICONS, columns: columns, EVENT: EVENT, HOLD_MS: HOLD_MS }")()
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

// karchy's own windows share the shell's class, so the title names them: each
// has an icon of the map, and each title is the name of the plugin whose
// window it is and the title that window gives itself (windowTitle), which a
// floating window's titlebar shows.
eq(M.ownIcon("Settings"), "settings")
eq(M.ownIcon(" Updates "), "update")
eq(M.ownIcon("Settings — Firefox"), "", "another window's title is not one of them")
eq(M.ownIcon("constructor"), "")
const icons = JSON.parse(fs.readFileSync(root + "/default/karchy/icons.json", "utf8"))
const pluginOf = { "Settings": "settings", "Quick install": "quick-install", "Updates": "updates", "Virtual machines": "vms", "Containers": "containers" }
eq(Object.keys(M.OWN_ICONS).sort(), Object.keys(pluginOf).sort(), "the five windows of karchy's own")
for (const [title, icon] of Object.entries(M.OWN_ICONS)) {
  assert.ok(icons[icon], title + ": the icon map has " + icon)
  const dir = root + "/shell/plugins/" + pluginOf[title] + "/"
  const manifest = JSON.parse(fs.readFileSync(dir + "manifest.json", "utf8"))
  eq(manifest.name, title, "the plugin's name")
  const qml = fs.readFileSync(dir + manifest.entryPoints.panel, "utf8")
  assert.ok(qml.includes('readonly property string windowTitle: "' + title + '"'), title + " is that window's title")
}

// The shell's app id is the class Hyprland's rules name for those windows. It
// is no terminal's (org.karchy.<name> is tagged a terminal) and no desktop
// entry's: an entry of that name would put its Name in every titlebar.
const appId = /^\/\/@ pragma AppId (\S+)$/m.exec(fs.readFileSync(root + "/shell/shell.qml", "utf8"))[1]
assert.ok(!/^org\.karchy\./.test(appId), "the shell's app id is outside the terminals' classes")
let ruled = 0
for (const file of ["system.lua", "vms.lua"]) {
  for (const line of fs.readFileSync(root + "/default/hypr/apps/" + file, "utf8").split("\n")) {
    if (!line.startsWith("o.own_size_window(")) continue
    ruled++
    assert.ok(line.includes('class = "^' + appId + '$"'), "a rule for the shell's class: " + line)
    const title = /title = "\^(.*?)\$"/.exec(line)[1]
    assert.ok(M.ownIcon(title) !== "", title + " has a rule and an icon")
  }
}
eq(ruled, Object.keys(M.OWN_ICONS).length, "a rule for each of the five")
const { execFileSync } = require("child_process")
const entries = execFileSync("git", ["-C", root, "ls-files", "*.desktop"], { encoding: "utf8" }).split("\n").filter(Boolean)
assert.ok(entries.length > 0 && !entries.some(e => e.toLowerCase().endsWith("/" + appId.toLowerCase() + ".desktop")), "no desktop entry is named after the shell's app id")

// All tiles in one row while they fit; otherwise rows of equal length.
eq(M.columns(4, 148, 8, 1100), 4)
eq(M.columns(7, 148, 8, 1100), 7)
eq(M.columns(8, 148, 8, 1100), 4, "eight windows where seven fit: two rows of four")
eq(M.columns(15, 148, 8, 1100), 5)
eq(M.columns(0, 148, 8, 1100), 1)
eq(M.columns(3, 148, 8, 100), 1, "a screen narrower than a tile still gets one column")
console.log("window switcher ok")
