// The Quick install window's words and lists, from the catalog
// (default/karchy/quick-install.json) and `karchy-quick-install status`.
// Plain JavaScript: names of icons, never glyphs (docs/architecture.md, Icons).

function parse(text, fallback) {
  try {
    var value = JSON.parse(text)
    return value === null || value === undefined ? fallback : value
  } catch (e) {
    return fallback
  }
}

// The sidebar: All and Installed, then the catalog's categories in its order.
// Each category's icon is named here, where tools/icon-check can see it.
var icons = {
  all: { iconName: "menu.apps" },
  installed: { iconName: "app.installed" },
  karchy: { iconName: "plugin" },
  browsers: { iconName: "app.browser" },
  chat: { iconName: "app.chat" },
  office: { iconName: "app.office" },
  media: { iconName: "app.media" },
  gaming: { iconName: "app.game" },
  languages: { iconName: "dev.language" },
  editors: { iconName: "app.editor" },
  devtools: { iconName: "dev.tools" },
  databases: { iconName: "dev.database" },
  cloud: { iconName: "dev.cloud" },
  ai: { iconName: "app.ai" },
  security: { iconName: "security" },
  network: { iconName: "app.sync" },
  utilities: { iconName: "app.utility" },
  fonts: { iconName: "look.font" },
  system: { iconName: "features" }
}

function categoryIcon(id) {
  return (icons[id] || icons.all).iconName
}

function categories(catalog, installed) {
  var apps = (catalog && catalog.apps) || []
  var counts = {}
  var installedCount = 0
  for (var i = 0; i < apps.length; i++) {
    counts[apps[i].category] = (counts[apps[i].category] || 0) + 1
    if (installed[apps[i].id] !== undefined) installedCount++
  }
  var out = [
    { id: "all", name: "All", count: apps.length, iconName: categoryIcon("all") },
    { id: "installed", name: "Installed", count: installedCount, iconName: categoryIcon("installed") }
  ]
  var cats = (catalog && catalog.categories) || []
  for (var j = 0; j < cats.length; j++)
    out.push({ id: cats[j].id, name: cats[j].name, count: counts[cats[j].id] || 0, iconName: categoryIcon(cats[j].id) })
  return out
}

// The apps a category shows, in the catalog's order (by name within it).
function inCategory(apps, category, installed) {
  if (category === "all") return apps.slice()
  return apps.filter(function(a) {
    return category === "installed" ? installed[a.id] !== undefined : a.category === category
  })
}

function categoryName(catalog, id) {
  if (id === "all") return "All"
  if (id === "installed") return "Installed"
  if (id === "picked") return "Picked"
  var cats = (catalog && catalog.categories) || []
  for (var i = 0; i < cats.length; i++) if (cats[i].id === id) return cats[i].name
  return id
}

function find(apps, id) {
  for (var i = 0; i < apps.length; i++) if (apps[i].id === id) return apps[i]
  return null
}

// --------------------------------------------------------------- wording

function list(words) {
  if (words.length <= 1) return words.join("")
  return words.slice(0, -1).join(", ") + " and " + words[words.length - 1]
}

function capitalized(s) {
  return s.charAt(0).toUpperCase() + s.slice(1)
}

// A karchy entry is a feature (repository packages, set up by karchy's
// script) or one of karchy's add-on packages (D-106), released in [karchy].
// "arch" names the packages' origin, not where pacman takes them from: on
// karchy most come from CachyOS's rebuilds (cachyos-extra-v3 and the like),
// so the wording stays neutral until `info` names the repository.
function sourceText(source, feature) {
  switch (source) {
    case "arch": return "from the package repositories"
    case "cachyos": return "from CachyOS's repository"
    case "omarchy": return "from Omarchy's repository"
    case "aur": return "from the AUR: built on this computer from a community-maintained script"
    case "karchy": return feature ? "from the package repositories, set up by karchy" : "from karchy's repository"
    default: return ""
  }
}

// "firefox from the cachyos-extra-v3 repository", once `karchy-quick-install info` has named
// the repository pacman installs it from (`info.repo`); that is known for the
// first package only, so a list of several keeps the general wording.
function installsText(app, info) {
  var packages = app.packages || []
  // An AUR app that also brings repository packages: say which are which.
  if (app.source === "aur" && packages.length > 1) {
    var built = app.aur || packages.slice(0, 1)
    var rest = packages.filter(function(p) { return built.indexOf(p) < 0 })
    return built.join(", ") + " from the AUR (built on this computer from a community-maintained script)"
      + (rest.length > 0 ? ", with " + rest.join(", ") + " " + sourceText("arch", false) : "")
  }
  var pkgs = packages.join(", ")
  var repo = info && typeof info === "object" ? String(info.repo || "") : ""
  var from = repo !== "" && packages.length === 1 && app.source !== "aur" && !app.feature
    ? "from the " + repo + " repository"
    : sourceText(app.source, !!app.feature)
  return from === "" ? pkgs : pkgs + " " + from
}

// What else installing does, as sentences. `multilibOn`: Arch's 32-bit
// repository is already on, so turning it on isn't news.
function setupLines(app, multilibOn) {
  var setup = app.setup || {}
  var lines = []
  if (app.multilib && !multilibOn)
    lines.push("Turns on Arch's 32-bit repository ([multilib]) and updates the system in the same step.")
  if (setup.gpu32) lines.push("Adds the 32-bit graphics driver for this computer's graphics card.")
  var clauses = []
  var services = setup.services || []
  if (services.length > 0) clauses.push("turns on " + list(services))
  var userServices = setup.userServices || []
  if (userServices.length > 0) clauses.push("turns on " + list(userServices) + " for you")
  var groups = setup.groups || []
  if (groups.length > 0)
    clauses.push("adds you to the " + list(groups) + " group" + (groups.length > 1 ? "s" : "") + " (from your next sign-in)")
  var modules = setup.modules || []
  if (modules.length > 0)
    clauses.push("loads the " + list(modules) + " kernel module" + (modules.length > 1 ? "s" : ""))
  if (clauses.length > 0) lines.push(capitalized(list(clauses)) + ".")
  var run = setup.run || []
  for (var i = 0; i < run.length; i++) lines.push("Runs " + run[i] + " as you.")
  return lines
}

// The Size line, from `karchy-quick-install info`: for an app that isn't
// installed, everything pacman would add for it ("412 MiB download, 1.9 GiB
// installed, 37 packages with what it needs"); for an installed one, what its
// own packages take. An AUR app's figure covers only what comes from the
// repositories. `multilibPending`: the app needs Arch's 32-bit repository
// and it is still off.
function sizeText(info, aur, multilibPending) {
  if (!info) return ""
  var parts = []
  if (info.download) parts.push(info.download + " download")
  if (info.installed) parts.push(info.installed + " installed")
  // An app that needs Arch's 32-bit repository, while that is off: pacman
  // can't say yet what the install comes to.
  var later = "counted once Arch's 32-bit repository is on, which installing turns on"
  if (parts.length === 0) return multilibPending ? capitalized(later) + "." : ""
  if (info.alone)
    return parts.join(", ") + " for " + info.alone + " alone" + (multilibPending ? "; the 32-bit packages it needs are " + later : "")
  if (info.count > 1) parts.push(info.count + " packages with what it needs")
  var text = parts.join(", ")
  if (aur) text += " from the repositories; the AUR build comes on top"
  return text
}

// The theme colors a letter tile (an app without an icon) may take, by the
// names themes give them in colors.toml, then the terminal's numbers.
var tileHues = [["red", "color1"], ["yellow", "color3"], ["green", "color2"], ["cyan", "color6"], ["blue", "color4"], ["magenta", "color5"]]

// The same hue for the same name every time: its palette keys, best first.
function tileKeys(name) {
  var s = String(name || "")
  var h = 0
  for (var i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) % 9973
  return tileHues[h % tileHues.length]
}

if (typeof module !== "undefined") {
  module.exports = {
    categories: categories,
    inCategory: inCategory,
    installsText: installsText,
    runText: runText,
    selectionText: selectionText,
    setupLines: setupLines,
    sizeText: sizeText,
    tileKeys: tileKeys
  }
}

// "Firefox", "Firefox and mpv", "Firefox, mpv and GIMP".
function namesText(names) {
  var n = (names || []).length
  if (n === 0) return ""
  if (n === 1) return names[0]
  return names.slice(0, n - 1).join(", ") + " and " + names[n - 1]
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

// One app's line in the list while it installs or after (D-109).
function progressText(p, verb) {
  switch (p.state) {
    case "queued": return "Waiting…"
    case "working": return verb === "remove" ? "Removing…" : "Installing…"
    case "done": return verb === "remove" ? "Removed" : "Installed"
    case "terminal": return "Continues in a terminal" + (verb === "remove" ? "" : ": it builds from the AUR or runs karchy's setup there")
    // Stopped by the person (the password prompt closed) or in the terminal,
    // which showed why: said plainly, not as an error.
    case "cancelled": return (verb === "remove" ? "Not removed" : "Not installed") + (p.reason ? ": " + p.reason : "")
    case "failed": return "Failed: " + (p.reason || "see the log")
  }
  return ""
}

// The last install or removal in a sentence, for the bar under the list:
// `entries` are its apps as { name, state }. "Hyperfine installed.",
// "2 installed and 1 failed. The log has every step.", "Nothing was changed."
function runText(entries, verb) {
  var n = { done: 0, failed: 0, cancelled: 0, terminal: 0 }
  for (var i = 0; i < entries.length; i++) if (n[entries[i].state] !== undefined) n[entries[i].state]++
  var total = n.done + n.failed + n.cancelled + n.terminal
  if (total === 0) return ""
  var did = verb === "remove" ? "removed" : "installed"
  if (n.cancelled === total) return "Nothing was changed."
  var one = entries.length === 1 ? entries[0].name : ""
  var parts = []
  if (n.done > 0) parts.push((one || n.done) + " " + did)
  if (n.failed > 0) parts.push((one || n.failed) + " failed")
  if (n.terminal > 0) parts.push((one || n.terminal) + (one || n.terminal === 1 ? " continues" : " continue") + " in a terminal")
  if (n.cancelled > 0) parts.push(n.cancelled + " not " + did)
  return capitalized(list(parts)) + "." + (n.failed > 0 ? " The log has every step." : "")
}

// The selection bar's words.
function selectionText(count, inTerminal, applying, verb, lastRun) {
  if (applying) return verb === "remove" ? "Removing…" : "Installing… the password prompt comes first."
  if (count === 0) return lastRun || ""
  var text = plural(count, "app", "apps") + " picked."
  if (inTerminal > 0) text += " " + (inTerminal === 1 ? "One" : inTerminal) + " of them " + (inTerminal === 1 ? "opens" : "open") + " in a terminal after the rest, to show the AUR's build files or karchy's setup."
  return text
}

