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

// A karchy entry is a feature (Arch's packages, set up by karchy's script) or
// one of karchy's add-on packages (D-106), released in [karchy].
function sourceText(source, feature) {
  switch (source) {
    case "arch": return "from Arch's repositories"
    case "cachyos": return "from CachyOS's repository"
    case "omarchy": return "from Omarchy's repository"
    case "aur": return "from the AUR: built on this computer from a community-maintained script"
    case "karchy": return feature ? "from Arch's repositories, set up by karchy" : "from karchy's repository"
    default: return ""
  }
}

// "firefox from Arch's repositories"
function installsText(app) {
  var pkgs = (app.packages || []).join(", ")
  var from = sourceText(app.source, !!app.feature)
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
  if (clauses.length > 0) lines.push(capitalized(list(clauses)) + ".")
  var run = setup.run || []
  for (var i = 0; i < run.length; i++) lines.push("Runs " + run[i] + " as you.")
  return lines
}

// "86.65 MiB download, 306.80 MiB installed", from `karchy-quick-install info`.
function sizeText(info) {
  if (!info) return ""
  var parts = []
  if (info.download) parts.push(info.download + " download")
  if (info.installed) parts.push(info.installed + " installed")
  return parts.join(", ")
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
    setupLines: setupLines,
    sizeText: sizeText,
    tileKeys: tileKeys
  }
}
