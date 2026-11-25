// The screensaver's logic that needs no screen: the size of its grid, the
// order of its effects and reading what ttfx writes (tests/screensaver.js).

// The art's size in cells: its widest line in characters (not UTF-16 units)
// and its lines, trailing blank ones left out.
function artSize(text) {
  var lines = String(text || "").replace(/\s+$/, "").split("\n")
  var cols = 0
  for (var i = 0; i < lines.length; i++) cols = Math.max(cols, Array.from(lines[i].replace(/\s+$/, "")).length)
  return { cols: cols, rows: cols > 0 ? lines.length : 0 }
}

// One grid for every screen, as Omarchy's native screensaver has: the cells
// of the largest screen, at the size of a terminal's 18 pt font (24 px) or
// smaller where the art would not fit nine tenths of the smallest screen.
// Each screen shows the grid centred, so a smaller one shows its middle.
// `font` is a monospace cell per pixel of font size: { advance, height }.
function grid(screens, art, font, wantedPx) {
  var list = screens || []
  var largest = null
  var smallest = null
  for (var i = 0; i < list.length; i++) {
    var s = list[i]
    if (!s || !(s.width > 0) || !(s.height > 0)) continue
    if (!largest || s.width * s.height > largest.width * largest.height) largest = s
    if (!smallest || s.width * s.height < smallest.width * smallest.height) smallest = s
  }
  if (!largest || !font || !(font.advance > 0) || !(font.height > 0)) return { fontPx: 0, cellW: 0, cellH: 0, cols: 0, rows: 0 }

  var px = wantedPx || 24
  if (art && art.cols > 0) px = Math.min(px, Math.floor(smallest.width * 0.9 / art.cols / font.advance))
  if (art && art.rows > 0) px = Math.min(px, Math.floor(smallest.height * 0.9 / art.rows / font.height))
  px = Math.max(6, px)
  var cellW = Math.max(1, Math.round(px * font.advance))
  var cellH = Math.max(1, Math.round(px * font.height))
  return {
    fontPx: px,
    cellW: cellW,
    cellH: cellH,
    cols: Math.floor(largest.width / cellW),
    rows: Math.floor(largest.height / cellH)
  }
}

// ttfx's effects, from the Commands section of `ttfx --help`.
function effectNames(help) {
  var names = []
  var inCommands = false
  var lines = String(help || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (/^Commands:/.test(line)) { inCommands = true; continue }
    if (!inCommands) continue
    var m = /^ {2}([a-z0-9]+) {2,}\S/.exec(line)
    if (!m) { if (/^\S/.test(line)) break; continue }
    if (m[1] !== "help") names.push(m[1])
  }
  return names
}

// The next effect: each one once, in a shuffled order, before any comes
// again; and a new round never opens with the effect that just played.
// `random` returns [0, 1). Returns { name, bag } with what is left to play.
function nextEffect(bag, names, last, random) {
  var left = (bag || []).filter(function(name) { return names.indexOf(name) !== -1 })
  if (left.length === 0) {
    left = names.slice()
    for (var i = left.length - 1; i > 0; i--) {
      var j = Math.floor(random() * (i + 1))
      var t = left[i]; left[i] = left[j]; left[j] = t
    }
    if (left.length > 1 && left[0] === last) {
      var k = 1 + Math.floor(random() * (left.length - 1))
      var u = left[0]; left[0] = left[k]; left[k] = u
    }
  }
  if (left.length === 0) return { name: "", bag: [] }
  return { name: left[0], bag: left.slice(1) }
}

// What the grid shows: a character and a colour (0xRRGGBB) per cell, and the
// last text of each row, so a row that did not change costs one comparison.
function blankState(cols, rows) {
  var n = Math.max(0, cols * rows)
  var chars = new Array(n)
  var colors = new Array(n)
  for (var i = 0; i < n; i++) { chars[i] = " "; colors[i] = WHITE }
  var lines = new Array(Math.max(0, rows))
  for (var r = 0; r < rows; r++) lines[r] = ""
  return { cols: cols, rows: rows, chars: chars, colors: colors, lines: lines }
}

var WHITE = 0xffffff

function put(state, at, ch, color, changed) {
  if (state.chars[at] === ch && state.colors[at] === color) return
  state.chars[at] = ch
  state.colors[at] = color
  changed.push(at)
}

// One row of a frame. ttfx writes each cell as its character, or as
// ESC[38;2;R;G;Bm <character> ESC[0m when it has a colour; any other escape
// is passed over.
function applyLine(state, row, s, changed) {
  var cols = state.cols
  var at = row * cols
  var end = at + cols
  var i = 0
  var n = s.length
  while (i < n && at < end) {
    var code = s.charCodeAt(i)
    var color = WHITE
    if (code === 27) {
      var num = 0, field = 0, r = 0, g = 0, b = 0
      i += 2
      for (; i < n; i++) {
        code = s.charCodeAt(i)
        if (code >= 48 && code <= 57) { num = num * 10 + code - 48; continue }
        if (field === 2) r = num; else if (field === 3) g = num; else if (field === 4) b = num
        field++
        num = 0
        if (code !== 59) break
      }
      i++
      if (field < 5) continue
      color = (r << 16) | (g << 8) | b
      if (i >= n) break
      code = s.charCodeAt(i)
    }
    if (code === 13) { i++; continue }
    var size = code >= 0xD800 && code <= 0xDBFF ? 2 : 1
    put(state, at++, size === 1 ? s.charAt(i) : s.substr(i, 2), color, changed)
    i += size
  }
  while (at < end) put(state, at++, " ", WHITE, changed)
}

// One frame: `rows` lines joined by newlines, the first of a run led by
// ESC[?25l (hide the cursor). Returns the cells that changed.
function applyFrame(state, data) {
  var changed = []
  var text = String(data || "")
  if (text.charCodeAt(0) === 27 && text.charAt(2) === "?") text = text.substring(text.indexOf("l") + 1)
  var all = text.split("\n")
  for (var row = 0; row < state.rows && row < all.length; row++) {
    if (all[row] === state.lines[row]) continue
    state.lines[row] = all[row]
    applyLine(state, row, all[row], changed)
  }
  return changed
}

// A block element that a terminal draws as part of its cell rather than as a
// glyph, so that blocks meet without a seam in any font: 0 for none, else
// which part (1 full, 2 upper half, 3 lower half, 4 left half, 5 right half).
function block(ch) {
  switch (ch) {
  case "█": return 1
  case "▀": return 2
  case "▄": return 3
  case "▌": return 4
  case "▐": return 5
  }
  return 0
}

if (typeof module !== "undefined") {
  module.exports = {
    artSize: artSize,
    grid: grid,
    effectNames: effectNames,
    nextEffect: nextEffect,
    blankState: blankState,
    applyLine: applyLine,
    applyFrame: applyFrame,
    block: block,
    WHITE: WHITE
  }
}
