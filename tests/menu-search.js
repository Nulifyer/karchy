// The shipped menu (D-133, D-135): the root, the rows that are found by
// search only, and what each word people type finds, in the menu's own
// ranking. Run: bun tests/menu-search.js "$PWD"
const assert = require("assert")
const fs = require("fs")
const root = process.argv[2] || "."
const M = require(root + "/shell/plugins/menu/MenuModel.js")

const merged = M.mergeMenuSources(M.parseMenuJsonc(fs.readFileSync(root + "/default/karchy/karchy-menu.jsonc", "utf8")), [], "Search")
const items = merged.items, order = merged.itemOrder

// The menu's own search from the root (Menu.qml rebuildDisplay): rows of this
// level and deeper rows, each sorted by score, the better tier first. A
// result reads as its path.
function search(query) {
  const current = [], deeper = []
  for (const id of order) {
    const entry = items[id]
    if (id === "root" || !M.matchesQuery(entry, query, true, M.parentPathFor(items, id))) continue
    const row = { id: id, reads: M.pathFor(items, id), score: M.searchScore(items, entry, query), path: M.pathFor(items, id) }
    ;(entry.parent === "root" ? current : deeper).push(row)
  }
  const sort = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path)
  current.sort(sort); deeper.sort(sort)
  const tier = rows => rows.length ? Math.floor(rows[0].score / 1000) : Infinity
  return tier(deeper) < tier(current) ? deeper.concat(current) : current.concat(deeper)
}
const first = query => { const rows = search(query); return rows.length ? rows[0].reads : "" }
const top = (query, n) => search(query).slice(0, n).map(r => r.reads)

// The root as it lists: eight rows, Power last. Theme and Background are
// found, not listed.
const listed = parent => order.filter(id => items[id].parent === parent && !items[id].searchOnly).map(id => items[id].label)
assert.deepStrictEqual(listed("root"), ["Apps", "Packages", "Recording", "Keybinds", "Update", "Settings", "Reload", "Power"])
assert.deepStrictEqual(listed("packages"), ["Quick Install", "Install Package", "Remove Package", "Install Web App", "Remove Web App"])
assert.deepStrictEqual(listed("reload"), ["Shell", "Hyprland", "Audio", "Wi-Fi", "Bluetooth", "Trackpad"])
assert.deepStrictEqual(listed("system"), ["Lock", "Suspend", "Hibernate", "Log Out", "Reboot", "Shutdown"])
assert.deepStrictEqual(order.filter(id => items[id].searchOnly).map(id => items[id].label), ["Theme", "Background"])
// Rows under a row that runs an action never list: Settings' pages, in the window's order.
assert.strictEqual(items.settings.kind, "action")
assert.strictEqual(items.update.kind, "action")
assert.deepStrictEqual(listed("settings"), ["Network", "Displays", "Input", "Appearance", "Fonts", "Notifications", "Default Apps", "Power", "Storage", "Date & Time", "Security", "SSH & Git", "About"])
const sections = fs.readFileSync(root + "/bin/karchy-settings", "utf8").match(/^sections=\(([^)]*)\)/m)[1].split(" ")
assert.deepStrictEqual(order.filter(id => items[id].parent === "settings").map(id => id.split(".")[1]), sections.filter(id => id !== "keybindings"), "the search rows follow karchy-settings' order")
for (const id of order) assert.ok(!/^(appearance|setup|about|restart)(\.|$)|^packages\.aur$|^update\.(restart|password|time|timezone|system)/.test(id), id + " should be gone")
// No label repeats its parent: the menu draws the path.
for (const id of order) assert.ok(items[id].label.indexOf("›") < 0, id)

const finds = {
  "Settings › Security": ["security", "fingerprint", "fido2", "yubikey", "security key", "password", "passwd", "change password", "drive password", "luks", "encryption"],
  "Settings › Date & Time": ["timezone", "time", "clock", "date", "ntp"],
  "Settings › SSH & Git": ["ssh", "git", "github"],
  "Settings › Storage": ["disk", "storage", "space", "bees", "smart", "nas", "smb", "samba", "share", "mount"],
  "Settings › Power": ["battery", "sleep", "lid", "idle"],
  "Settings › About": ["about", "version", "system info", "fastfetch", "hyprland config"],
  "Settings › Displays": ["displays", "monitors", "resolution", "scale", "settings displays"],
  "Settings › Network": ["network", "wifi", "vpn", "dns"],
  "Settings › Input": ["mouse", "touchpad", "input config", "input"],
  "Settings › Notifications": ["notifications", "do not disturb"],
  "Settings › Appearance": ["appearance", "workspace layout", "bar style"],
  "Settings › Fonts": ["font", "fonts", "text size"],
  "Settings › Default Apps": ["default apps", "default browser"],
  "Update › Firmware": ["firmware", "fwupd", "bios", "update firmware"],
  // The menu's own rows win their names.
  "Settings": ["settings", "preferences"],
  "Power": ["power"],
  "Keybinds": ["keybinds", "keybindings", "shortcuts", "keys"],
  "Update": ["update", "updates", "upgrade", "channel"],
  "Reload": ["reload"],
  "Recording": ["recording", "record screen", "screenrecord"],
  "Theme": ["theme", "themes"],
  "Background": ["background", "wallpaper"],
  "Packages › Install Package": ["install package", "aur", "pacman"],
  "Packages › Quick Install": ["quick install"],
  "Reload › Hyprland": ["hyprland", "reload hyprland"],
  "Reload › Shell": ["shell", "restart shell", "quickshell"],
  "Reload › Audio": ["restart audio", "pipewire"],
  "Power › Reboot": ["reboot", "restart", "power restart", "power reboot"],
  "Power › Suspend": ["suspend"],
  "Power › Hibernate": ["hibernate"],
  "Power › Lock": ["lock"],
  "Power › Shutdown": ["shutdown", "power off"]
}
const problems = []
for (const reads in finds) for (const query of finds[reads]) {
  const got = first(query)
  if (got !== reads) problems.push(JSON.stringify(query) + " found " + (got || "nothing") + ", not " + reads + " (" + top(query, 4).join(", ") + ")")
}
assert.deepStrictEqual(problems, [])

// "update" offers the window, then the Settings page that shows the version
// and channel, then the firmware part.
assert.deepStrictEqual(top("update", 3), ["Update", "Settings › About", "Update › Firmware"])
// An action keeps its own name, and the page that sets it up comes right after.
for (const query of ["power", "suspend", "hibernate"])
  assert.ok(top(query, 2).indexOf("Settings › Power") >= 0, query + " offers Settings › Power")
// "restart" is the computer's first, then the parts of the desktop.
assert.ok(top("restart", 8).indexOf("Reload › Shell") > 0 && search("restart").some(r => r.reads === "Reload"))
// "settings" lists the window, then every page.
assert.strictEqual(search("settings").length, 14)
// D-77's rule holds: a name match comes before a row matched only by an alias.
assert.deepStrictEqual(top("install package", 1), ["Packages › Install Package"])

// The English catalog names every row as the menu does.
const catalog = JSON.parse(fs.readFileSync(root + "/default/i18n/en/menu.json", "utf8"))
for (const id of order) if (id !== "root") assert.strictEqual((catalog[id] || {}).label, items[id].label, "en/menu.json: " + id)
for (const id in catalog) assert.ok(items[id], "en/menu.json names a row the menu lacks: " + id)
console.log("menu-search: ok")
