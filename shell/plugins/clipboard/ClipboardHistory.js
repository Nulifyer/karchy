// The clipboard history's rules (D-167), for Service.qml, the picker
// (Clipboard.qml) and the bar panel (Panel.qml).
//
// An entry is one copy, kept as a file (capture.sh writes it):
//   { id, type, mime, path, size, preview, count, capturedAt, time, pinned }
// id is the type and a hash of the content, so the same copy is one entry.
// type is text, image or files (a file manager's copy: the file holds the
// list). preview is the start of a text, or the list of files; the picker
// searches and draws only that, never the whole copy. The history is newest
// first. A pinned entry stays through Clear, the limits and a restart.

// How much is kept. Entries that are not pinned live in memory
// ($XDG_RUNTIME_DIR), so the bytes are RAM.
var defaultLimits = {
  entries: 100,
  bytes: 64 * 1024 * 1024
}

var types = ["text", "image", "files"]

function normalizeEntry(value) {
  if (!value || typeof value !== "object") return null

  var type = String(value.type || "")
  var id = String(value.id || "")
  var path = String(value.path || "")
  if (types.indexOf(type) < 0 || !id || path.charAt(0) !== "/") return null

  var entry = {
    id: id,
    type: type,
    mime: String(value.mime || (type === "image" ? "image/png" : type === "files" ? "text/uri-list" : "text/plain")),
    path: path,
    size: Math.max(0, Number(value.size) || 0),
    preview: String(value.preview || ""),
    time: Math.max(0, Number(value.time) || 0),
    pinned: value.pinned === true
  }
  if (type === "files") entry.count = Math.max(1, Number(value.count) || 1)
  if (value.capturedAt !== undefined && value.capturedAt !== null) entry.capturedAt = String(value.capturedAt)
  return entry
}

function parseEntries(raw) {
  try {
    var parsed = JSON.parse(String(raw || "[]"))
    var next = []
    if (!Array.isArray(parsed)) return next

    for (var i = 0; i < parsed.length; i++) {
      var entry = normalizeEntry(parsed[i])
      if (entry) next.push(entry)
    }
    return next
  } catch (e) {
    return []
  }
}

// One line of capture.sh's output.
function parseEntryJson(line) {
  var raw = String(line || "").trim()
  if (!raw) return null
  try { return normalizeEntry(JSON.parse(raw)) } catch (e) { return null }
}

function indexOfId(history, id) {
  var values = Array.isArray(history) ? history : []
  for (var i = 0; i < values.length; i++) {
    if (values[i] && values[i].id === id) return i
  }
  return -1
}

function limitsOf(limits) {
  var entries = limits && limits.entries !== undefined ? Number(limits.entries) : defaultLimits.entries
  var bytes = limits && limits.bytes !== undefined ? Number(limits.bytes) : defaultLimits.bytes
  return {
    entries: isNaN(entries) ? defaultLimits.entries : Math.max(0, entries),
    bytes: isNaN(bytes) ? defaultLimits.bytes : Math.max(0, bytes)
  }
}

// The history as the two stored lists make it: what was kept this session
// and what is pinned, newest first. A pinned entry wins over a session one
// with the same content.
function merge(session, pinned) {
  var seen = {}
  var next = []
  var lists = [pinned, session]

  for (var l = 0; l < lists.length; l++) {
    var values = Array.isArray(lists[l]) ? lists[l] : []
    for (var i = 0; i < values.length; i++) {
      var entry = normalizeEntry(values[i])
      if (!entry || seen[entry.id]) continue
      entry.pinned = l === 0
      seen[entry.id] = true
      next.push(entry)
    }
  }

  // Array.prototype.sort is stable: entries of one moment keep their order.
  next.sort(function(a, b) { return b.time - a.time })
  return next
}

// Drops the oldest entries that are not pinned until the rest are within the
// limits. Returns { history, dropped }, dropped being the files to delete.
function enforce(history, limits) {
  var max = limitsOf(limits)
  var count = 0
  var bytes = 0
  var next = []
  var dropped = []

  for (var i = 0; i < history.length; i++) {
    var entry = history[i]
    if (entry.pinned) {
      next.push(entry)
      continue
    }
    if (count + 1 > max.entries || bytes + entry.size > max.bytes) {
      dropped.push(entry.path)
      // Nothing older is kept either: the history has no holes.
      count = max.entries
      continue
    }
    count += 1
    bytes += entry.size
    next.push(entry)
  }

  return { history: next, dropped: dropped }
}

// A new copy goes to the top. One already in the history moves up instead,
// keeping its pin and its file; the new file is then spare.
function addEntry(history, entry, limits) {
  var values = Array.isArray(history) ? history : []
  var normalized = normalizeEntry(entry)
  if (!normalized) return { history: values.slice(), dropped: [] }

  var dropped = []
  var next = []
  var existingAt = indexOfId(values, normalized.id)

  if (existingAt >= 0) {
    var existing = values[existingAt]
    if (existing.path !== normalized.path) dropped.push(normalized.path)
    normalized = Object.assign({}, existing, { time: normalized.time || existing.time })
  } else {
    normalized.pinned = false
  }

  next.push(normalized)
  for (var i = 0; i < values.length; i++) {
    if (i !== existingAt) next.push(values[i])
  }

  var result = enforce(next, limits)
  return { history: result.history, dropped: dropped.concat(result.dropped) }
}

function removeEntry(history, id) {
  var values = Array.isArray(history) ? history : []
  var at = indexOfId(values, id)
  if (at < 0) return { history: values.slice(), dropped: [] }

  var next = values.slice()
  var removed = next.splice(at, 1)
  return { history: next, dropped: [removed[0].path] }
}

// Clear all, as on Windows: everything but the pinned entries.
function clearUnpinned(history) {
  var values = Array.isArray(history) ? history : []
  var next = []
  var dropped = []

  for (var i = 0; i < values.length; i++) {
    if (values[i].pinned) next.push(values[i])
    else dropped.push(values[i].path)
  }
  return { history: next, dropped: dropped }
}

function unpinnedCount(history) {
  var values = Array.isArray(history) ? history : []
  var count = 0
  for (var i = 0; i < values.length; i++) {
    if (!values[i].pinned) count += 1
  }
  return count
}

// Pinning moves the entry's file between the session folder (memory) and the
// pinned one (the home folder). movedPath says where the file goes;
// setPinned records the move once it is done.
function movedPath(entry, folder) {
  if (!entry) return ""
  return String(folder || "").replace(/\/+$/, "") + "/" + fileName(entry.path)
}

function setPinned(history, id, pinned, path, limits) {
  var values = Array.isArray(history) ? history : []
  var at = indexOfId(values, id)
  if (at < 0) return { history: values.slice(), dropped: [] }

  var next = values.slice()
  next[at] = Object.assign({}, next[at], { pinned: pinned === true, path: String(path || next[at].path) })
  // An unpinned entry counts against the limits again.
  return enforce(next, limits)
}

function storedEntries(history, pinned) {
  var values = Array.isArray(history) ? history : []
  var next = []
  for (var i = 0; i < values.length; i++) {
    if ((values[i].pinned === true) === (pinned === true)) next.push(values[i])
  }
  return next
}

// Only files in the history's own folders are ever deleted or moved.
function ownsPath(path, folders) {
  var value = String(path || "")
  var name = fileName(value)
  if (!name || name === "." || name === "..") return false

  var list = Array.isArray(folders) ? folders : []
  for (var i = 0; i < list.length; i++) {
    var folder = String(list[i] || "").replace(/\/+$/, "")
    if (folder && value === folder + "/" + name) return true
  }
  return false
}

function ownedPaths(paths, folders) {
  var next = []
  var values = Array.isArray(paths) ? paths : []
  for (var i = 0; i < values.length; i++) {
    if (ownsPath(values[i], folders)) next.push(values[i])
  }
  return next
}

function decodeFileUri(uri) {
  var value = String(uri || "").trim()
  if (value.indexOf("file://") !== 0) return ""

  var path = value.substring(7)
  if (path.indexOf("localhost/") === 0) path = path.substring(9)
  if (path.charAt(0) !== "/") return ""

  try { return decodeURIComponent(path) } catch (e) { return path }
}

// The files of a files entry that the preview holds (all of them unless the
// list is very long; count has the real number).
function filePaths(entry) {
  if (!entry || entry.type !== "files") return []

  var lines = String(entry.preview || "").split(/\r?\n/)
  var paths = []
  for (var i = 0; i < lines.length; i++) {
    var path = decodeFileUri(lines[i])
    if (path) paths.push(path)
  }
  return paths
}

function fileName(path) {
  var parts = String(path || "").split("/")
  return parts.length > 0 ? parts[parts.length - 1] : String(path || "")
}

function isImagePath(path) {
  return /\.(png|jpe?g|webp|gif|bmp|tiff?)$/i.test(String(path || ""))
}

// tr is an optional translate(key, english) from the QML side (I18n.t),
// trn its plural form (I18n.tn) and fmt a number formatter
// (I18n.formatNumber); without them the English text and plain digits
// stand, which is what the tests assert.
function translator(tr) {
  return typeof tr === "function" ? tr : function(key, english) { return english }
}

function fileEntryText(entry, tr, trn, fmt) {
  var tn = typeof trn === "function" ? trn : function(key, count, english) { return count === 1 ? english.one : english.other }
  var number = typeof fmt === "function" ? fmt : function(v) { return String(v) }
  var paths = filePaths(entry)
  var count = Math.max(paths.length, entry && entry.count || 0)
  if (count === 0) return ""
  if (count === 1 && paths.length === 1) return fileName(paths[0])
  return tn("clipboard.files", count, { one: "%1 file", other: "%1 files" }).replace("%1", number(count))
}

function imagePreviewText(entry, tr) {
  var t = translator(tr)
  var timestamp = String(entry && entry.capturedAt || "")
  if (!timestamp) return t("clipboard.image", "Image")

  var screenshot = String(entry && entry.mime || "") === "image/png"
  var pattern = screenshot
    ? t("clipboard.screenshotFrom", "Screenshot from %1")
    : t("clipboard.imageFrom", "Image from %1")
  return pattern.replace("%1", timestamp)
}

// One line that names the entry in a list.
function previewText(entry, tr, trn, fmt) {
  if (!entry) return ""
  if (entry.type === "image") return imagePreviewText(entry, tr)
  if (entry.type === "files") return fileEntryText(entry, tr, trn, fmt)
  return String(entry.preview || "").replace(/\s+/g, " ").trim()
}

// What the picker shows beside the list for the entry under the cursor.
function fullText(entry) {
  if (!entry || entry.type === "image") return ""
  if (entry.type === "files") return filePaths(entry).join("\n")
  return String(entry.preview || "")
}

function searchableText(entry, tr, trn, fmt) {
  if (!entry) return ""
  if (entry.type === "image") return "image screenshot " + String(entry.mime || "") + " " + String(entry.capturedAt || "")
  if (entry.type === "files") return "file " + fullText(entry) + " " + fileEntryText(entry, tr, trn, fmt)
  return String(entry.preview || "")
}

function row(entry, tr, trn, fmt) {
  var paths = filePaths(entry)
  var isImage = entry.type === "image"
  var oneFile = entry.type === "files" && paths.length === 1 && (entry.count || 1) === 1
  return {
    id: entry.id,
    entryType: entry.type === "files" ? "file" : entry.type,
    pinned: entry.pinned === true,
    fullText: fullText(entry),
    previewText: previewText(entry, tr, trn, fmt),
    previewImage: isImage ? entry.path : (oneFile && isImagePath(paths[0]) ? paths[0] : ""),
    path: entry.path,
    mime: entry.mime
  }
}

// The picker's rows: the history, newest first, that the search matches.
function displayRows(history, query, limit, tr, trn, fmt) {
  var values = Array.isArray(history) ? history : []
  var needle = String(query || "").trim().toLowerCase()
  var max = limit === undefined || limit === null ? 50 : Number(limit)
  if (isNaN(max)) max = 50
  max = Math.max(0, max)

  var rows = []
  for (var i = 0; i < values.length && rows.length < max; i++) {
    var entry = normalizeEntry(values[i])
    if (!entry) continue
    if (needle && searchableText(entry, tr, trn, fmt).toLowerCase().indexOf(needle) < 0) continue
    rows.push(row(entry, tr, trn, fmt))
  }
  return rows
}

// The bar panel's rows: the pinned entries, then the newest of the rest, a
// few of each. more counts what only the picker shows.
function panelRows(history, limit, tr, trn, fmt) {
  var values = Array.isArray(history) ? history : []
  var max = Math.max(0, Number(limit) || 0)
  var pinned = []
  var recent = []
  var total = 0

  for (var i = 0; i < values.length; i++) {
    var entry = normalizeEntry(values[i])
    if (!entry) continue
    total += 1
    var list = entry.pinned ? pinned : recent
    if (list.length < max) list.push(row(entry, tr, trn, fmt))
  }

  return { pinned: pinned, recent: recent, more: total - pinned.length - recent.length }
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultLimits: defaultLimits,
    normalizeEntry: normalizeEntry,
    parseEntries: parseEntries,
    parseEntryJson: parseEntryJson,
    merge: merge,
    addEntry: addEntry,
    removeEntry: removeEntry,
    clearUnpinned: clearUnpinned,
    unpinnedCount: unpinnedCount,
    movedPath: movedPath,
    setPinned: setPinned,
    storedEntries: storedEntries,
    ownsPath: ownsPath,
    ownedPaths: ownedPaths,
    filePaths: filePaths,
    fileEntryText: fileEntryText,
    imagePreviewText: imagePreviewText,
    previewText: previewText,
    fullText: fullText,
    searchableText: searchableText,
    displayRows: displayRows,
    panelRows: panelRows
  }
}
