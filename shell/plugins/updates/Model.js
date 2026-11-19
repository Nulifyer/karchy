.pragma library

// The Updates window's reading of `karchy-update --plan` (bin/karchy-update):
// { checked, channel, release: { installed, available, notes }, size, error,
//   restart, news: [{ date, title }],
//   changes: [{ name, old, new, kind, app, restart, label }] }
// kind is "karchy", "app", "system" or "aur".

function parse(text) {
  try {
    var plan = JSON.parse(text)
    if (!plan || typeof plan !== "object") throw new Error("not an object")
    plan.changes = Array.isArray(plan.changes) ? plan.changes : []
    plan.news = Array.isArray(plan.news) ? plan.news : []
    plan.release = plan.release || {}
    return plan
  } catch (e) {
    return { error: "The update check gave an answer the window can't read.", details: String(text || ""), changes: [], news: [], release: {} }
  }
}

function ofKind(plan, kind) {
  if (!plan) return []
  return plan.changes.filter(function(c) { return c.kind === kind })
}

// Apps by their launcher name; one package can be one app.
function apps(plan) {
  var seen = {}
  return ofKind(plan, "app").filter(function(c) {
    if (seen[c.app]) return false
    seen[c.app] = true
    return true
  }).sort(function(a, b) { return a.app.toLowerCase() < b.app.toLowerCase() ? -1 : 1 })
}

// System components: the ones that need a restart first, by the names people
// know ("Linux kernel"), then the rest by package name.
function system(plan) {
  return ofKind(plan, "system").sort(function(a, b) {
    if (a.restart !== b.restart) return a.restart ? -1 : 1
    return a.name < b.name ? -1 : 1
  })
}

function restartParts(plan) {
  var names = []
  if (!plan) return names
  plan.changes.forEach(function(c) {
    if (c.restart && names.indexOf(c.label) < 0) names.push(c.label)
  })
  return names
}

// Core packages karchy retired (karchy-package-retire): ones the update
// removes, and ones kept because you installed them yourself.
function retired(plan, which) {
  var r = plan && plan.retired
  return r && Array.isArray(r[which]) ? r[which] : []
}

// A removal is a change too: an update can consist of nothing else.
function count(plan) {
  return plan ? plan.changes.length + retired(plan, "remove").length : 0
}

function plural(n, one, many) {
  return n + " " + (n === 1 ? one : many)
}

function installLabel(plan) {
  return "Install " + plural(count(plan), "update", "updates")
}

// The header's line under the title: its parts with a dot between them. A
// part never breaks inside (no-break spaces), so where the line is too long
// for the header it wraps between parts.
function statusLine(parts) {
  return parts.map(function(part) { return String(part).replace(/ /g, "\u00a0") }).join("\u00a0· ")
}

// "just now", "5 min ago", "3 h ago", or the date.
function ago(iso, now) {
  var t = Date.parse(iso || "")
  if (isNaN(t)) return ""
  var minutes = Math.round((now - t) / 60000)
  if (minutes < 1) return "just now"
  if (minutes < 60) return minutes + " min ago"
  if (minutes < 24 * 60) return Math.round(minutes / 60) + " h ago"
  return new Date(t).toLocaleDateString()
}

var channelText = {
  stable: "Releases",
  rc: "Release candidates, a few days ahead of releases",
  nightly: "Every change to karchy's main branch, for testing"
}

// The switch question: what it installs, and that it can go back in time.
function switchMessage(from, to) {
  return "Switch karchy to the " + to + " channel? Its packages are installed now"
    + (from === "nightly" ? ", replacing newer nightly ones with older releases." : ".")
    + " The desktop reloads when it's done."
}

// A version as shown: a dev build's stamp (".l<unix time>", added by
// packaging/build so a rebuild of the same commit counts as newer) says
// nothing a reader needs and makes the version too long for its place.
function shortVersion(version) {
  return String(version || "").replace(/\.l\d{9,}(?=-|$)/, "")
}

// A pair of versions as shown, without the stamp. It stays when it is the
// only difference, so old and new never read the same; `tails` then says the
// difference is at the end, which is the end to keep.
function versionPair(oldVersion, newVersion) {
  var a = shortVersion(oldVersion), b = shortVersion(newVersion)
  if (a === b) return { old: String(oldVersion || ""), next: String(newVersion || ""), tails: true }
  return { old: a, next: b, tails: false }
}
