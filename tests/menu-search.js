// The shipped menu's search (D-133): every Settings page and every row that
// left the menu is found by the words people type for it, and the row comes
// first. Run: bun tests/menu-search.js "$PWD"
const assert = require("assert")
const fs = require("fs")
const root = process.argv[2] || "."
const M = require(root + "/shell/plugins/menu/MenuModel.js")

const merged = M.mergeMenuSources(M.parseMenuJsonc(fs.readFileSync(root + "/default/karchy/karchy-menu.jsonc", "utf8")), [], "Search")
const items = merged.items, order = merged.itemOrder

// The menu's own search from the root (Menu.qml rebuildDisplay): rows of this
// level and deeper rows, each sorted by score, the better tier first.
function search(query) {
  const current = [], deeper = []
  for (const id of order) {
    const entry = items[id]
    if (id === "root" || !M.matchesQuery(entry, query, true)) continue
    const row = { id: id, label: entry.label, score: M.searchScore(items, entry, query), path: M.pathFor(items, id) }
    ;(entry.parent === "root" ? current : deeper).push(row)
  }
  const sort = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path)
  current.sort(sort); deeper.sort(sort)
  const tier = rows => rows.length ? Math.floor(rows[0].score / 1000) : Infinity
  return tier(deeper) < tier(current) ? deeper.concat(current) : current.concat(deeper)
}
const first = query => { const rows = search(query); return rows.length ? rows[0].id : "" }

// The root: ten rows, Power last.
const rootRows = order.filter(id => items[id].parent === "root").map(id => items[id].label)
assert.deepStrictEqual(rootRows, ["Apps", "Packages", "Record Screen", "Theme", "Background", "Settings", "Update System", "Keybindings", "Restart", "Power"])

// Nothing is left of the dissolved submenus.
for (const id of order) assert.ok(!/^(appearance|setup|about)(\.|$)|^update\.(restart|password|time|timezone|system)/.test(id), id + " should be gone")

// A Settings page reads as where it goes, and needs no subtitle for it.
for (const id of order) if (id.indexOf("settings.") === 0) assert.ok(items[id].label.indexOf("Settings › ") === 0, id)

const finds = {
  "settings.security": ["security", "fingerprint", "fido2", "yubikey", "security key", "password", "passwd", "change password", "drive password", "luks", "encryption"],
  "settings.datetime": ["timezone", "time", "clock", "date", "ntp"],
  "settings.ssh": ["ssh", "git", "github"],
  "settings.storage": ["disk", "storage", "space", "bees", "smart", "nas", "smb", "samba", "share", "mount"],
  "settings.power": ["battery", "sleep", "lid", "idle"],
  "settings.about": ["about", "version", "system info", "fastfetch", "hyprland config"],
  "settings.displays": ["displays", "monitors", "resolution", "scale"],
  "settings.network": ["network", "wifi", "vpn", "dns"],
  "settings.input": ["mouse", "touchpad", "input config", "edit keybindings"],
  "settings.notifications": ["notifications", "do not disturb"],
  "settings.appearance": ["appearance", "workspace layout", "bar style"],
  "settings.fonts": ["font", "fonts", "text size"],
  "settings.apps": ["default apps", "default browser"],
  "update.firmware": ["firmware", "fwupd", "bios"],
  // Rows of the menu itself keep winning their own names.
  "settings": ["settings"],
  "system": ["power"],
  "keybindings": ["keybindings", "shortcuts"],
  "update": ["update", "updates", "upgrade"],
  "restart": ["restart"],
  "theme": ["theme"],
  "background": ["background", "wallpaper"],
  "packages.install": ["install package"],
  "restart.wifi": ["restart wifi"],
  "system.suspend": ["suspend"],
  "system.hibernate": ["hibernate"]
}
const problems = []
for (const id in finds) for (const query of finds[id]) {
  const got = first(query)
  if (got !== id) problems.push(JSON.stringify(query) + " found " + (got || "nothing") + ", not " + id + " (" + search(query).slice(0, 4).map(r => r.id).join(", ") + ")")
}
assert.deepStrictEqual(problems, [])

// An action keeps its own name, and the page that sets it up comes right after.
for (const query of ["power", "suspend", "hibernate"])
  assert.ok(search(query).slice(0, 2).some(r => r.id === "settings.power"), query + " offers Settings › Power")

// D-77's rule holds: a name match comes before a row matched only by an alias.
assert.strictEqual(first("install package"), "packages.install")
// "settings" lists the window, then every page.
assert.ok(search("settings").length >= 14)

// The English catalog names every row as the menu does.
const catalog = JSON.parse(fs.readFileSync(root + "/default/i18n/en/menu.json", "utf8"))
for (const id of order) if (id !== "root") assert.strictEqual((catalog[id] || {}).label, items[id].label, "en/menu.json: " + id)
for (const id in catalog) assert.ok(items[id], "en/menu.json names a row the menu lacks: " + id)
console.log("menu-search: ok")
