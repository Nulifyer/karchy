// fzf-style search for the Quick install window. Plain JavaScript so
// tools/quick-install-search-check can run it under node; the window imports
// it as a QML JS resource.
//
// The results rank in tiers, best first:
//   5    the name starts with the query          "obs"  OBS Studio, Obsidian
//   4.5  a keyword, a package or the id is it    "adb"  Android platform tools,
//        "vm"  Virtual machines before ScummVM
//   4    a word in the name starts with it       "studio"  OBS Studio
//   3    the name contains it                    "fox"  Firefox
//   2.7  its letters are the name's word starts  "kpx"  KeePassXC
//   2.5  every word of it is a word, or starts one, in the name, keywords,
//        description or packages                 "ssh"  PuTTY, "video edit"
//   2    the name holds its letters in order     "ff"  Firefox
//   1    the name and the rest contain every word of it somewhere
//   0.5  four letters or more scattered through the name with no word start
//        or run to hold them: almost always chance ("excel" in Sched-ext
//        schedulers), so they come after everything that says the word
// A word found in the text (2.5) ranks above letters in order (2) because
// that is what people type when they don't know the name: "dj" is Mixxx,
// not Deja Dup. Within a tier, letters on word starts and in runs rank
// higher, then the shorter name, then the name alphabetically. Case is
// ignored; spaces in the query are ignored for the letters-in-order tiers.

function lower(value) {
  return String(value || "").toLowerCase()
}

// For each letter of a name, whether a word starts there: after a space or
// punctuation, at a digit after a letter, at a capital after a lower-case
// letter (KeePassXC: K, P, X) and at the last capital of a run before
// lower-case letters (VSCodium: V, C).
function wordStarts(name) {
  var out = []
  for (var i = 0; i < name.length; i++) {
    var c = name.charAt(i)
    var p = i > 0 ? name.charAt(i - 1) : ""
    var nx = name.charAt(i + 1)
    out.push(/[A-Za-z0-9]/.test(c) && (i === 0
      || !/[A-Za-z0-9]/.test(p)
      || (/[a-z]/.test(p) && /[A-Z]/.test(c))
      || (/[A-Z]/.test(p) && /[A-Z]/.test(c) && /[a-z]/.test(nx))
      || (/[A-Za-z]/.test(p) && /[0-9]/.test(c))))
  }
  return out
}

function range(from, count) {
  var out = []
  for (var i = 0; i < count; i++) out.push(from + i)
  return out
}

// The best placement of `q`'s letters in `name`, in order, as
// { score, positions } or null. Letters on a word start score 8, a letter
// right after the previous one 5, any letter 1; each skipped letter costs a
// little. A small dynamic program: names and queries are short.
function subsequence(name, q) {
  var text = lower(name)
  var n = text.length
  var m = q.length
  if (m === 0 || m > n) return null
  var starts = wordStarts(name)
  var NONE = -1e9
  // best[i][j]: the best score with q[0..i] placed and q[i] at j.
  var best = []
  var from = []
  for (var i = 0; i < m; i++) {
    best.push([])
    from.push([])
    for (var j = 0; j < n; j++) {
      best[i].push(NONE)
      from[i].push(-1)
      if (text.charAt(j) !== q.charAt(i)) continue
      var own = 1 + (starts[j] ? 8 : 0)
      if (i === 0) {
        best[i][j] = own - j * 0.1
        continue
      }
      for (var k = i - 1; k < j; k++) {
        if (best[i - 1][k] === NONE) continue
        var s = best[i - 1][k] + own + (k === j - 1 ? 5 : -(j - k - 1) * 0.2)
        if (s > best[i][j]) { best[i][j] = s; from[i][j] = k }
      }
    }
  }
  var end = -1
  var top = NONE
  for (var e = 0; e < n; e++) if (best[m - 1][e] > top) { top = best[m - 1][e]; end = e }
  if (end < 0) return null
  var positions = []
  for (var r = m - 1, at = end; r >= 0; r--) {
    positions.unshift(at)
    at = from[r][at]
  }
  return { score: top, positions: positions }
}

// What else an app is known by.
function otherText(app) {
  return lower([
    (app.keywords || []).join(" "),
    app.description,
    (app.packages || []).join(" "),
    app.id
  ].join(" "))
}

// The words of a text: letters and digits, with "+" and "#" kept (c++, c#).
function words(text) {
  return lower(text).split(/[^a-z0-9+#]+/).filter(function(w) { return w !== "" })
}

// Whether `word` is one of `list`, or starts one (from three letters on, so
// "rec" finds "recorder" and "r" finds only R). 2 for the whole word, 1 for
// a start, 0 for neither.
function wordIn(list, word) {
  var best = 0
  for (var i = 0; i < list.length; i++) {
    if (list[i] === word) return 2
    if (word.length >= 3 && list[i].indexOf(word) === 0) best = 1
  }
  return best
}

// Tier 2.5: every word of the query is a word of the app, or starts one.
// A whole word counts more than the start of one ("java" is Java before
// javascript); then keywords, the name, the description and packages.
function wordScore(app, queryWords) {
  var keywords = words((app.keywords || []).join(" "))
  var name = words(app.name)
  var rest = words([app.description, (app.packages || []).join(" "), app.id].join(" "))
  var score = 0
  for (var i = 0; i < queryWords.length; i++) {
    var k = wordIn(keywords, queryWords[i]), n = wordIn(name, queryWords[i]), r = wordIn(rest, queryWords[i])
    if (k + n + r === 0) return -1
    score += Math.max(k === 2 ? 6 : k * 3, n === 2 ? 5 : n * 2, r === 2 ? 4 : r)
  }
  return score
}

// How well `app` matches `query`: { tier, score, positions } (positions are
// the matched letters of the name, for highlighting), or null for no match.
function match(app, query) {
  var q = lower(query).trim()
  if (q === "") return { tier: 0, score: 0, positions: [] }
  var name = String(app.name || "")
  var text = lower(name)

  if (text.indexOf(q) === 0) return { tier: 5, score: 0, positions: range(0, q.length) }

  var starts = wordStarts(name)
  var at = text.indexOf(q)
  var firstAt = at
  // The whole of a keyword, a package name or the id: what the app is called
  // by people who don't know its name here ("adb", "npm", "vm").
  var known = (app.keywords || []).concat(app.packages || [], [app.id])
  for (var k = 0; k < known.length; k++)
    if (lower(known[k]) === q) return { tier: 4.5, score: 0, positions: firstAt >= 0 ? range(firstAt, q.length) : [] }
  while (at > 0) {
    if (starts[at]) return { tier: 4, score: -at, positions: range(at, q.length) }
    at = text.indexOf(q, at + 1)
  }
  if (firstAt >= 0) return { tier: 3, score: -firstAt, positions: range(firstAt, q.length) }

  // Letters in order: on word starts only (an abbreviation), held together
  // by word starts and runs, or scattered.
  var letters = q.replace(/\s+/g, "")
  var sub = subsequence(name, letters)
  var acronym = !!sub, tight = !!sub
  if (sub) {
    for (var p = 0; p < sub.positions.length; p++) {
      var onStart = starts[sub.positions[p]]
      if (!onStart) acronym = false
      if (!onStart && !(p > 0 && sub.positions[p] === sub.positions[p - 1] + 1)) tight = false
    }
  }
  if (sub && acronym) return { tier: 2.7, score: sub.score, positions: sub.positions }

  var queryWords = words(q)
  var worded = queryWords.length > 0 ? wordScore(app, queryWords) : -1
  if (worded >= 0) return { tier: 2.5, score: worded, positions: [] }

  if (sub && (letters.length <= 3 || tight)) return { tier: 2, score: sub.score, positions: sub.positions }

  var all = text + " " + otherText(app)
  var parts = q.split(/\s+/)
  var everywhere = true
  for (var i = 0; i < parts.length; i++) if (all.indexOf(parts[i]) < 0) { everywhere = false; break }
  if (everywhere) {
    // A keyword hit before one in the description.
    var keywords = lower((app.keywords || []).join(" "))
    return { tier: 1, score: keywords.indexOf(parts[0]) >= 0 ? 1 : 0, positions: [] }
  }
  if (sub) return { tier: 0.5, score: sub.score, positions: sub.positions }
  return null
}

// The apps that match, best first, each as { app, positions }.
function search(apps, query) {
  var found = []
  for (var i = 0; i < apps.length; i++) {
    var m = match(apps[i], query)
    if (m) found.push({ app: apps[i], tier: m.tier, score: m.score, positions: m.positions })
  }
  found.sort(function(a, b) {
    if (a.tier !== b.tier) return b.tier - a.tier
    if (a.score !== b.score) return b.score - a.score
    var la = String(a.app.name).length
    var lb = String(b.app.name).length
    if (la !== lb) return la - lb
    return lower(a.app.name) < lower(b.app.name) ? -1 : 1
  })
  return found.map(function(f) { return { app: f.app, positions: f.positions } })
}

function escapeHtml(s) {
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;")
}

// The name as StyledText with the matched letters underlined in `color`.
function highlighted(name, positions, color) {
  var text = String(name || "")
  if (!positions || positions.length === 0) return escapeHtml(text)
  var marked = {}
  for (var i = 0; i < positions.length; i++) marked[positions[i]] = true
  var out = ""
  var open = false
  for (var j = 0; j < text.length; j++) {
    if (marked[j] && !open) { out += "<u><font color=\"" + color + "\">"; open = true }
    if (!marked[j] && open) { out += "</font></u>"; open = false }
    out += escapeHtml(text.charAt(j))
  }
  if (open) out += "</font></u>"
  return out
}

if (typeof module !== "undefined") {
  module.exports = {
    wordStarts: wordStarts,
    subsequence: subsequence,
    match: match,
    search: search,
    highlighted: highlighted
  }
}
