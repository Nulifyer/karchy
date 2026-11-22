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
assert.deepStrictEqual(listed("settings"), ["Network", "Bluetooth", "Displays", "Sound", "Input", "Appearance", "Fonts", "Notifications", "Default Apps", "Power", "Storage", "Date & Time", "Users", "Security", "SSH & Git", "About"])
const sections = fs.readFileSync(root + "/bin/karchy-settings", "utf8").match(/^sections=\(([^)]*)\)/m)[1].split(" ")
assert.deepStrictEqual(order.filter(id => items[id].parent === "settings").map(id => id.split(".")[1]), sections.filter(id => id !== "keybindings"), "the search rows follow karchy-settings' order")
for (const id of order) assert.ok(!/^(appearance|setup|about|restart)(\.|$)|^packages\.aur$|^update\.(restart|password|time|timezone|system)/.test(id), id + " should be gone")
// No label repeats its parent: the menu draws the path.
for (const id of order) assert.ok(items[id].label.indexOf("›") < 0, id)

const finds = {
  "Settings › Security": ["security", "fingerprint", "fido2", "yubikey", "security key", "password", "passwd", "change password", "drive password", "luks", "encryption", "keyring", "saved passwords"],
  "Settings › Users": ["user", "users", "account", "accounts", "add user", "login", "auto-login"],
  "Settings › Date & Time": ["timezone", "time", "clock", "date", "ntp"],
  "Settings › SSH & Git": ["ssh", "git", "github"],
  "Settings › Storage": ["disk", "storage", "space", "bees", "smart", "nas", "smb", "samba", "share", "mount"],
  "Settings › Power": ["battery", "sleep", "lid", "idle"],
  "Settings › About": ["about", "version", "system info", "fastfetch", "hyprland config"],
  "Settings › Displays": ["displays", "monitors", "resolution", "scale", "settings displays"],
  // "sound" and "bluetooth" are the pages, with the Reload rows after them.
  "Settings › Sound": ["sound", "volume", "speaker", "microphone", "headphones", "output", "input device", "settings sound"],
  "Settings › Bluetooth": ["bluetooth", "pair", "headset", "bt"],
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
// "sound" and "bluetooth" offer the page, then the restart of that part; "audio" is Reload › Audio's own name.
assert.deepStrictEqual(top("sound", 2), ["Settings › Sound", "Reload › Audio"])
assert.deepStrictEqual(top("bluetooth", 2), ["Settings › Bluetooth", "Reload › Bluetooth"])
assert.deepStrictEqual(top("audio", 2), ["Reload › Audio", "Settings › Sound"])
// "restart" is the computer's first, then the parts of the desktop.
assert.ok(top("restart", 8).indexOf("Reload › Shell") > 0 && search("restart").some(r => r.reads === "Reload"))
// "settings" lists the window, then every page.
assert.strictEqual(search("settings").length, 17)
// D-77's rule holds: a name match comes before a row matched only by an alias.
assert.deepStrictEqual(top("install package", 1), ["Packages › Install Package"])

// Loose matches are gone: a word typed is found at the start of a word (of a
// name or a path; of an alias from two letters on), and inside a word only
// from three letters on and only in a row's own name. Checked with apps in the list, as the menu has
// them (Menu.qml mergeAppRows: the generic name and the keywords are aliases).
const app = (id, label, generic, keywords) => ({ id: "apps." + id, parent: "apps", kind: "app", label: label,
  description: generic, aliases: (generic ? [generic] : []).concat(keywords ? keywords.split(";").filter(k => k) : []),
  searchTerms: [], when: "", order: 0 })
const withApps = M.mergeAppRows(items, order, [
  app("org.gnome.DiskUtility", "Disks", "", "disk;drive;volume;harddisk;hdd;disc;cdrom;dvd;partition;iso;image;backup;restore;benchmark;raid;luks;encryption;S.M.A.R.T.;smart;"),
  app("io.missioncenter.MissionCenter", "Mission Center", "", "Task manager;Resource monitor;System monitor;Processor;Processes;Performance monitor;CPU;GPU;Disc;Disk;Memory;Network;Utilisation;Utilization;Service;Services;systemd;systemctl"),
  app("disktree", "disktree", "Disk space treemap", "disk;space;usage;du;treemap;cleanup;"),
  app("firefox", "Firefox", "Web Browser", "Internet;WWW;Browser;Web;Explorer"),
  app("thunar", "Thunar File Manager", "File Manager", "file manager;explorer;finder;browser;folders;network;devices;"),
  app("btop", "btop++", "System Monitor", "system;process;task"),
  app("localsend", "LocalSend", "An open source cross-platform alternative to AirDrop", "Sharing;LAN;Files;")
])
function searchAll(query) {
  const rows = []
  for (const id of withApps.itemOrder) {
    const entry = withApps.items[id]
    if (id === "root" || !M.matchesQuery(entry, query, true, M.parentPathFor(withApps.items, id))) continue
    rows.push({ reads: M.pathFor(withApps.items, id), score: M.searchScore(withApps.items, entry, query) })
  }
  return rows.sort((a, b) => a.score - b.score || a.reads.localeCompare(b.reads)).map(r => r.reads)
}
const found = (query, reads) => searchAll(query).indexOf(reads) >= 0
// The reported ones: "sc" gave Disks and Mission Center (the keyword "disc"),
// "b" gave About and Hibernate, "up" gave Disks and disktree ("backup",
// "cleanup"), "the" gave Settings › Network ("ethernet").
for (const [query, reads] of [["sc", "Apps › Disks"], ["sc", "Apps › Mission Center"], ["b", "Settings › About"],
  ["b", "Power › Hibernate"], ["up", "Apps › Disks"], ["up", "Apps › disktree"], ["the", "Settings › Network"],
  ["a", "Power › Shutdown"], ["he", "Settings › Network"], ["in", "Apps › Thunar File Manager"]])
  assert.ok(!found(query, reads), JSON.stringify(query) + " should not find " + reads + " (" + searchAll(query).join(", ") + ")")
// What they give now, best first.
assert.deepStrictEqual(searchAll("sc"), ["Recording", "Settings › Displays", "Settings › Appearance"])
assert.deepStrictEqual(searchAll("up").slice(0, 3), ["Update", "Update › Firmware", "Settings › About"])
assert.deepStrictEqual(searchAll("the"), ["Theme"])
// One letter finds names only: no Disks for "backup", no Settings › Power for "battery".
assert.deepStrictEqual(searchAll("b"), ["Apps › btop++", "Background", "Settings › Bluetooth", "Reload › Bluetooth"])
assert.ok(found("ba", "Settings › Power") && found("ba", "Apps › Disks") && searchAll("ba")[0] === "Background")
// An exact alias, then names, then other aliases; a word start before the inside of a word.
assert.deepStrictEqual(searchAll("disk").slice(0, 3), ["Settings › Storage", "Apps › Disks", "Apps › disktree"])
assert.deepStrictEqual(searchAll("pack").slice(0, 3), ["Packages", "Packages › Install Package", "Packages › Remove Package"])
assert.strictEqual(searchAll("net")[0], "Settings › Network")
assert.strictEqual(searchAll("ethernet")[0], "Settings › Network")
assert.strictEqual(searchAll("browser")[0], "Apps › Firefox")
assert.strictEqual(searchAll("file")[0], "Apps › Thunar File Manager")
assert.strictEqual(searchAll("wall")[0], "Background")
// Inside a word of a name from three letters on ("fox", "send"), never of an alias ("ernet").
assert.deepStrictEqual(searchAll("fox"), ["Apps › Firefox"])
assert.deepStrictEqual(searchAll("send"), ["Apps › LocalSend"])
assert.deepStrictEqual(searchAll("ox"), [])
assert.deepStrictEqual(searchAll("ernet"), [])
// Several words, in any order, each at a word's start; a hyphen in an alias or in what is typed.
assert.strictEqual(searchAll("manager file")[0], "Apps › Thunar File Manager")
assert.ok(found("wi fi", "Reload › Wi-Fi") && found("wi-fi", "Settings › Network"))
assert.ok(found("quick-install", "Packages › Quick Install") && found("screen record", "Recording"))

// The English catalog names every row as the menu does.
const catalog = JSON.parse(fs.readFileSync(root + "/default/i18n/en/menu.json", "utf8"))
for (const id of order) if (id !== "root") assert.strictEqual((catalog[id] || {}).label, items[id].label, "en/menu.json: " + id)
for (const id in catalog) assert.ok(items[id], "en/menu.json names a row the menu lacks: " + id)
console.log("menu-search: ok")
