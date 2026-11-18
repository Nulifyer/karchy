// Which indicators a karchy.indicators widget shows, in what order.
//
// With no settings it shows every indicator karchy ships, in karchy's order.
// `hidden` leaves indicators out; indicators karchy adds later still show.
// `items` is the older way: the indicators to show, in order. A list like
// that names only the indicators that existed when it was written, so an
// indicator karchy added since (one the list's `known` doesn't name) is put
// in at its place in karchy's order, unless `hidden` names it. Without
// `known`, a list is taken to know the indicators that existed before the
// first ones were added (2026-11-17, Dnd and StayAwake): every list written
// until then, by hand or as a copy of karchy's defaults, knew only those.

var knownBeforeLists = ["Updates", "ScreenRecording", "Reminder", "Minimized"]

function entryId(entry) {
  if (typeof entry === "string") return entry
  if (entry !== null && typeof entry === "object" && !isList(entry)) {
    var id = entry["id"]
    if (id !== undefined && id !== null && String(id) !== "") return String(id)
  }
  return ""
}

// A list from the settings: a JS array, or a list QML hands over as one.
function isList(value) {
  return value !== null && typeof value === "object" && typeof value.length === "number"
}

function idList(value) {
  var out = []
  if (!isList(value)) return out
  for (var i = 0; i < value.length; i++) {
    var id = entryId(value[i])
    if (id !== "") out.push(id)
  }
  return out
}

function copy(entry) {
  if (entry === null || typeof entry !== "object") return entry
  try {
    return JSON.parse(JSON.stringify(entry))
  } catch (error) {
    return entry
  }
}

// `settings`: the widget's entry in the bar layout. `shipped`: karchy's
// indicator ids in order. Returns the entries to show (strings or objects
// with an id, as the settings give them).
function entries(settings, shipped) {
  settings = settings || {}
  var hidden = idList(settings.hidden)
  var listed = isList(settings.items) && settings.items.length > 0 ? settings.items
    : isList(settings.indicators) && settings.indicators.length > 0 ? settings.indicators
    : null

  var result = []
  var ids = []
  function add(entry, at) {
    var id = entryId(entry)
    if (id === "" || ids.indexOf(id) !== -1 || hidden.indexOf(id) !== -1) return
    if (at === undefined || at >= result.length) {
      result.push(copy(entry))
      ids.push(id)
    } else {
      result.splice(at, 0, copy(entry))
      ids.splice(at, 0, id)
    }
  }

  if (!listed) {
    for (var i = 0; i < shipped.length; i++) add(shipped[i])
    return result
  }

  for (var j = 0; j < listed.length; j++) add(listed[j])
  var known = isList(settings.known) ? idList(settings.known) : knownBeforeLists
  for (var k = 0; k < shipped.length; k++) {
    var id = shipped[k]
    if (known.indexOf(id) !== -1 || ids.indexOf(id) !== -1) continue
    // After the nearest indicator that comes before it in karchy's order.
    var at = 0
    for (var p = k - 1; p >= 0; p--) {
      var before = ids.indexOf(shipped[p])
      if (before !== -1) {
        at = before + 1
        break
      }
    }
    add(id, at)
  }
  return result
}

if (typeof module !== "undefined") {
  module.exports = {
    knownBeforeLists: knownBeforeLists,
    entries: entries
  }
}
