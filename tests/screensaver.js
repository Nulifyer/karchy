// The shell screensaver's logic (shell/plugins/screensaver/ScreensaverModel.js):
//   node tests/screensaver.js "$PWD"
const assert = require("assert")
const M = require(process.argv[2] + "/shell/plugins/screensaver/ScreensaverModel.js")
const eq = (a, b, msg) => assert.deepStrictEqual(a, b, msg)

// The art's size counts characters, not UTF-16 units or trailing blanks.
eq(M.artSize("█▀▄\n ab  \n\n"), { cols: 3, rows: 2 })
eq(M.artSize(""), { cols: 0, rows: 0 })

// One grid for every screen: the largest's cells, the art fitting the smallest.
const font = { advance: 0.6, height: 1.2 }
const laptop = { width: 1504, height: 1003 }
eq(M.grid([laptop], { cols: 76, rows: 7 }, font, 24), { fontPx: 24, cellW: 14, cellH: 29, cols: 107, rows: 34 },
  "the laptop at 150%: the terminal's 24 px, the name fits")
const small = { width: 800, height: 600 }
const g = M.grid([{ width: 2560, height: 1440 }, small], { cols: 76, rows: 7 }, font, 24)
eq([g.fontPx, g.cols, g.rows], [15, 284, 80], "a small second screen: smaller cells so the name fits there, the large screen's grid")
assert.ok(g.cellW * 76 <= small.width * 0.9, "the name fits nine tenths of the small screen")
eq(M.grid([], { cols: 76, rows: 7 }, font, 24).cols, 0, "no screen, no grid")
eq(M.grid([small], { cols: 2000, rows: 1 }, font, 24).fontPx, 6, "never under 6 px")

// The effects from ttfx's help, without `help`.
const help = "Usage: ttfx [OPTIONS] [COMMAND]\n\nCommands:\n  beams            Create beams\n  matrix           Matrix digital rain effect\n  help             Print this message\n\nOptions:\n  -v, --version\n"
eq(M.effectNames(help), ["beams", "matrix"])
eq(M.effectNames("nothing here"), [])

// Each effect once before any comes again, and no effect twice in a row.
const names = ["a", "b", "c", "d", "e"]
let seed = 1
const random = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646 }
let bag = [], last = "", seen = []
for (let i = 0; i < 500; i++) {
  const next = M.nextEffect(bag, names, last, random)
  assert.notStrictEqual(next.name, last, "never the same effect twice in a row")
  seen.push(next.name)
  bag = next.bag
  last = next.name
}
for (let round = 0; round < 100; round++)
  eq(seen.slice(round * 5, round * 5 + 5).sort(), names, "round " + round + " plays every effect once")
eq(M.nextEffect(["gone", "b"], names, "", random).name, "b", "an effect ttfx no longer has is skipped")
eq(M.nextEffect([], [], "", random).name, "", "no effects, no name")
eq(M.nextEffect([], ["a"], "a", random).name, "a", "one effect plays again and again")

// Reading frames: plain and coloured cells, only the cells that changed.
const state = M.blankState(4, 2)
const red = "\x1b[38;2;255;0;0m"
eq(M.applyFrame(state, "\x1b[?25lab  \n" + red + "x\x1b[0m   "), [0, 1, 4])
eq(state.chars.slice(0, 2).concat(state.chars[4]), ["a", "b", "x"])
eq(state.colors[4], 0xff0000)
eq(M.applyFrame(state, "ab  \n" + red + "x\x1b[0m   "), [], "the same frame changes nothing")
eq(M.applyFrame(state, "a   \n" + red + "x\x1b[0m   "), [1], "one cell back to blank")
eq(M.applyFrame(state, "ab\n"), [1, 4], "a short row is blank to its end")
eq(M.applyFrame(state, "\u{1F600}cd\n"), [0, 1, 2], "a character outside the BMP is one cell")
eq(state.chars[0], "\u{1F600}")
eq(M.applyFrame(state, "abcdefgh\n"), [0, 1, 2, 3], "a row longer than the grid is cut at its edge")

eq([M.block("█"), M.block("▀"), M.block("▄"), M.block("▌"), M.block("▐"), M.block("a")], [1, 2, 3, 4, 5, 0])
console.log("screensaver: ok")
