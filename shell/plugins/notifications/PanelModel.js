// What the notifications panel lists (D-112). The behaviour follows Android's
// notification shade: ongoing ones first, then the alerting ones, then a
// Silent section; several from one app fold into a group that shows the
// newest and opens to show them all. Pure functions over history entries
// (Store.closedEntry); Service.qml says which are waiting and ongoing.

// Who it is from, as the toast decides it (Markup.regroup): the site for a
// browser's notification, otherwise the app. `id` is the key a per-app rule
// is kept under; Karchy's own toasts and bare notify-send have no app to
// name or set a rule for.
function groupOf(entry) {
  var key = String((entry && entry.groupKey) || "")
  var app = String((entry && entry.app) || "")
  if (key.indexOf("web:") === 0) return { id: key, label: key.slice(4), system: false }
  if (key.indexOf("app:") !== 0 || key === "app:" || app === "karchy-action" || app === "notify-send")
    return { id: "system", label: "", system: true }
  return { id: key, label: app, system: false }
}

function entryId(entry) {
  return String(entry.key) + "@" + String(entry.closed_ts)
}

// Newest first by when it arrived. History is kept in the order things
// closed, and one that got no popup closed the moment it came, ahead of
// older ones that were still on screen.
function byArrival(entries) {
  return (entries || []).slice().sort(function(a, b) {
    return (Number(b && b.ts) || 0) - (Number(a && a.ts) || 0)
  })
}

var SECTIONS = ["ongoing", "alerting", "silent"]

// `ongoing` maps an entry id to true (Service.isOngoing).
function sectionOf(entry, ongoing) {
  if (ongoing && ongoing[entryId(entry)]) return "ongoing"
  return entry.silent === true ? "silent" : "alerting"
}

// The waiting entries as sections of groups: [{ section, groups: [{ id,
// app, label, system, entries }] }], empty sections left out. Groups come in
// the order of their newest entry; entries newest first.
function sections(entries, ongoing) {
  var bySection = {}
  var sorted = byArrival(entries)
  for (var i = 0; i < sorted.length; i++) {
    var entry = sorted[i]
    if (!entry || !entry.key || entry.waiting !== true) continue
    var name = sectionOf(entry, ongoing)
    var who = groupOf(entry)
    var section = bySection[name] || (bySection[name] = { section: name, groups: [], byId: {} })
    var group = section.byId[who.id]
    if (!group) {
      group = { id: name + "/" + who.id, app: who.id, label: who.label, system: who.system, entries: [] }
      section.byId[who.id] = group
      section.groups.push(group)
    }
    group.entries.push(entry)
  }
  var out = []
  for (var s = 0; s < SECTIONS.length; s++) {
    var found = bySection[SECTIONS[s]]
    if (found) out.push({ section: found.section, groups: found.groups })
  }
  return out
}

// The rows the panel draws, top to bottom:
//   header  a section's name; only when there is more than one section, and
//           not for the alerting section when it comes first
//   entry   one notification; `folded` is how many more its group holds
//           while it stands for a closed group
//   fold    opens or closes a group of two or more ("3 more", "Show less")
// `opened` maps a group id to true once it was opened.
function rows(entries, ongoing, opened) {
  var out = []
  var list = sections(entries, ongoing)
  for (var s = 0; s < list.length; s++) {
    var section = list[s]
    if (list.length > 1 && !(s === 0 && section.section === "alerting"))
      out.push({ kind: "header", id: "header:" + section.section, section: section.section })
    for (var g = 0; g < section.groups.length; g++) {
      var group = section.groups[g]
      var open = group.entries.length < 2 || !!(opened && opened[group.id])
      var shown = open ? group.entries.length : 1
      for (var i = 0; i < shown; i++)
        out.push({ kind: "entry", id: entryId(group.entries[i]), group: group.id, app: group.app,
                   label: group.label, system: group.system, entry: group.entries[i],
                   section: section.section })
      if (group.entries.length > 1)
        out.push({ kind: "fold", id: "fold:" + group.id, group: group.id, label: group.label,
                   system: group.system, open: open, count: group.entries.length - 1 })
    }
  }
  return out
}

// The history view: everything of the last day that is no longer waiting,
// newest first, one row each.
function historyRows(entries) {
  var out = []
  var sorted = byArrival(entries)
  for (var i = 0; i < sorted.length; i++) {
    var entry = sorted[i]
    if (!entry || !entry.key || entry.waiting === true) continue
    var who = groupOf(entry)
    out.push({ kind: "entry", id: entryId(entry), group: "", app: who.id, label: who.label,
               system: who.system, entry: entry, section: "history" })
  }
  return out
}

function indexOfId(list, id) {
  for (var i = 0; i < list.length; i++) if (list[i].id === id) return i
  return -1
}

// The row the cursor goes to when row `index` leaves: the next one a cursor
// can stand on, else the one before, else "".
function neighbour(list, index) {
  for (var i = index + 1; i < list.length; i++) if (list[i].kind !== "header") return list[i].id
  for (var j = index - 1; j >= 0; j--) if (list[j].kind !== "header") return list[j].id
  return ""
}

// How long ago, as the panel says it: { kind: "now" }, { kind: "minutes",
// value }, { kind: "time" } (today, by the clock), { kind: "yesterday" } or
// { kind: "day" }. `ts` in seconds, `now` and `midnight` (today's) in ms.
function age(ts, now, midnight) {
  var t = Number(ts || 0) * 1000
  if (!t) return { kind: "" }
  var s = Math.max(0, (now - t) / 1000)
  if (s < 60) return { kind: "now" }
  if (s < 3600) return { kind: "minutes", value: Math.floor(s / 60) }
  if (t >= midnight) return { kind: "time" }
  if (t >= midnight - 86400000) return { kind: "yesterday" }
  return { kind: "day" }
}

if (typeof module !== "undefined") {
  module.exports = {
    groupOf: groupOf,
    entryId: entryId,
    byArrival: byArrival,
    sectionOf: sectionOf,
    sections: sections,
    rows: rows,
    historyRows: historyRows,
    indexOfId: indexOfId,
    neighbour: neighbour,
    age: age
  }
}
