// The clipboard history's rules (D-167): bun tests/clipboard-history.js "$PWD"
const assert = require("assert")
const root = process.argv[2]
const H = require(root + "/shell/plugins/clipboard/ClipboardHistory.js")

const SESSION = "/run/user/1000/karchy/clipboard"
const PINNED = "/home/me/.local/state/karchy/clipboard"
const text = (name, preview, extra) => Object.assign({
  id: "text:" + name, type: "text", mime: "text/plain", path: SESSION + "/" + name + ".txt", size: preview.length, preview
}, extra || {})
const image = (name, extra) => Object.assign({
  id: "image:" + name, type: "image", mime: "image/png", path: SESSION + "/" + name + ".png", size: 1000, capturedAt: "Tuesday 14:02"
}, extra || {})
const files = (name, uris, extra) => Object.assign({
  id: "files:" + name, type: "files", mime: "text/uri-list", path: SESSION + "/" + name + ".uris", size: 40,
  preview: uris.join("\n"), count: uris.length
}, extra || {})
const ids = history => history.map(e => e.id)

// ---- what counts as an entry
assert.strictEqual(H.normalizeEntry(null), null)
assert.strictEqual(H.normalizeEntry("hello"), null)
assert.strictEqual(H.normalizeEntry({ type: "text", id: "text:a", path: "relative.txt" }), null)
assert.strictEqual(H.normalizeEntry({ type: "html", id: "html:a", path: "/x" }), null)
assert.strictEqual(H.normalizeEntry({ type: "text", path: "/x" }), null)
assert.deepStrictEqual(H.normalizeEntry(text("a", "hello")), {
  id: "text:a", type: "text", mime: "text/plain", path: SESSION + "/a.txt", size: 5, preview: "hello", time: 0, pinned: false
})
assert.strictEqual(H.normalizeEntry(files("f", ["file:///a", "file:///b"])).count, 2)
assert.strictEqual(H.normalizeEntry(image("i")).capturedAt, "Tuesday 14:02")
assert.strictEqual(H.parseEntryJson(JSON.stringify(text("a", "hello")) + "\n").id, "text:a")
assert.strictEqual(H.parseEntryJson("not json"), null)
assert.strictEqual(H.parseEntryJson(""), null)
assert.deepStrictEqual(H.parseEntries("{"), [])
assert.deepStrictEqual(H.parseEntries('{"a":1}'), [])
assert.deepStrictEqual(ids(H.parseEntries(JSON.stringify([text("a", "x"), { type: "nope" }, image("i")]))), ["text:a", "image:i"])

// ---- a copy goes to the top; the same copy again moves up and is one entry
let r = H.addEntry([], text("a", "first", { time: 1 }))
assert.deepStrictEqual(ids(r.history), ["text:a"])
assert.deepStrictEqual(r.dropped, [])
r = H.addEntry(r.history, text("b", "second", { time: 2 }))
r = H.addEntry(r.history, image("i", { time: 3 }))
assert.deepStrictEqual(ids(r.history), ["image:i", "text:b", "text:a"])
r = H.addEntry(r.history, text("a", "first", { time: 4 }))
assert.deepStrictEqual(ids(r.history), ["text:a", "image:i", "text:b"])
assert.strictEqual(r.history[0].time, 4)
assert.deepStrictEqual(r.dropped, [], "the same file is not deleted")
// A copy nobody can use changes nothing.
assert.deepStrictEqual(ids(H.addEntry(r.history, { type: "text" }).history), ids(r.history))

// ---- the limits drop the oldest that are not pinned, and say which files go
const three = [text("c", "3", { time: 3 }), text("b", "2", { time: 2, pinned: true, path: PINNED + "/b.txt" }), text("a", "1", { time: 1 })]
r = H.addEntry(three, text("d", "4", { time: 4 }), { entries: 2 })
assert.deepStrictEqual(ids(r.history), ["text:d", "text:c", "text:b"], "pinned entries don't count and are never dropped")
assert.deepStrictEqual(r.dropped, [SESSION + "/a.txt"])
r = H.addEntry([image("x", { size: 600, time: 1 }), image("y", { size: 600, time: 0 })], image("z", { size: 600, time: 2 }), { bytes: 1300 })
assert.deepStrictEqual(ids(r.history), ["image:z", "image:x"])
assert.deepStrictEqual(r.dropped, [SESSION + "/y.png"])
// Past the first one dropped nothing older is kept, however small.
r = H.addEntry([image("big", { size: 900, time: 2 }), text("small", "s", { time: 1 })], image("new", { size: 900, time: 3 }), { bytes: 1000 })
assert.deepStrictEqual(ids(r.history), ["image:new"])
assert.deepStrictEqual(r.dropped, [SESSION + "/big.png", SESSION + "/small.txt"])
assert.deepStrictEqual(H.addEntry([], text("a", "x"), { entries: 0 }).history, [])
assert.strictEqual(H.defaultLimits.entries, 100)
assert.strictEqual(H.defaultLimits.bytes, 64 * 1024 * 1024)

// ---- a pinned entry copied again keeps its pin and its file; the new file is spare
r = H.addEntry(three, text("b", "2", { time: 9 }))
assert.deepStrictEqual(ids(r.history), ["text:b", "text:c", "text:a"])
assert.strictEqual(r.history[0].pinned, true)
assert.strictEqual(r.history[0].path, PINNED + "/b.txt")
assert.deepStrictEqual(r.dropped, [SESSION + "/b.txt"])
// A new copy is never pinned, whatever it says.
assert.strictEqual(H.addEntry([], text("p", "x", { pinned: true })).history[0].pinned, false)

// ---- delete one, clear all (the pinned ones stay)
r = H.removeEntry(three, "text:c")
assert.deepStrictEqual(ids(r.history), ["text:b", "text:a"])
assert.deepStrictEqual(r.dropped, [SESSION + "/c.txt"])
assert.deepStrictEqual(H.removeEntry(three, "text:nope"), { history: three, dropped: [] })
r = H.removeEntry(three, "text:b")
assert.deepStrictEqual(r.dropped, [PINNED + "/b.txt"], "deleting a pinned entry deletes it")
r = H.clearUnpinned(three)
assert.deepStrictEqual(ids(r.history), ["text:b"])
assert.deepStrictEqual(r.dropped, [SESSION + "/c.txt", SESSION + "/a.txt"])
assert.strictEqual(H.unpinnedCount(three), 2)
assert.strictEqual(H.unpinnedCount(r.history), 0)

// ---- pinning moves the file and records where it went
assert.strictEqual(H.movedPath(three[0], PINNED), PINNED + "/c.txt")
assert.strictEqual(H.movedPath(three[1], SESSION + "/"), SESSION + "/b.txt")
r = H.setPinned(three, "text:c", true, PINNED + "/c.txt")
assert.strictEqual(r.history[0].pinned, true)
assert.strictEqual(r.history[0].path, PINNED + "/c.txt")
assert.strictEqual(three[0].pinned, undefined, "the old list is left alone")
// Unpinned, an entry counts against the limits again.
r = H.setPinned(three, "text:b", false, SESSION + "/b.txt", { entries: 2 })
assert.deepStrictEqual(ids(r.history), ["text:c", "text:b"])
assert.deepStrictEqual(r.dropped, [SESSION + "/a.txt"])
assert.deepStrictEqual(ids(H.storedEntries(three, true)), ["text:b"])
assert.deepStrictEqual(ids(H.storedEntries(three, false)), ["text:c", "text:a"])

// ---- what a session starts with: the pinned entries and this session's, by time
const merged = H.merge([text("s2", "x", { time: 20 }), text("s1", "x", { time: 5 })], [text("p", "x", { time: 10, path: PINNED + "/p.txt" })])
assert.deepStrictEqual(ids(merged), ["text:s2", "text:p", "text:s1"])
assert.deepStrictEqual(merged.map(e => e.pinned), [false, true, false])
// After a restart the session list is gone: only the pinned are left.
assert.deepStrictEqual(ids(H.merge([], [text("p", "x", { time: 10 })])), ["text:p"])
// The same content in both: the pinned one stands.
const both = H.merge([text("p", "x", { time: 30 })], [text("p", "x", { time: 10, path: PINNED + "/p.txt" })])
assert.strictEqual(both.length, 1)
assert.strictEqual(both[0].path, PINNED + "/p.txt")
assert.strictEqual(both[0].pinned, true)

// ---- only files in the history's two folders are deleted or moved
const folders = [SESSION, PINNED + "/"]
assert.strictEqual(H.ownsPath(SESSION + "/abc.txt", folders), true)
assert.strictEqual(H.ownsPath(PINNED + "/abc.png", folders), true)
assert.strictEqual(H.ownsPath("/home/me/notes.txt", folders), false)
assert.strictEqual(H.ownsPath(SESSION + "/sub/abc.txt", folders), false)
assert.strictEqual(H.ownsPath(SESSION + "/../../etc/passwd", folders), false)
assert.strictEqual(H.ownsPath(SESSION + "/..", folders), false)
assert.strictEqual(H.ownsPath(SESSION + "/", folders), false)
assert.strictEqual(H.ownsPath("", folders), false)
assert.deepStrictEqual(H.ownedPaths([SESSION + "/a.txt", "/etc/passwd", PINNED + "/b.txt"], folders), [SESSION + "/a.txt", PINNED + "/b.txt"])

// ---- the words for an entry
const one = files("one", ["file:///home/me/My%20Photo.png"])
const two = files("two", ["file:///home/me/a.txt", "file://localhost/home/me/b.txt"])
assert.deepStrictEqual(H.filePaths(two), ["/home/me/a.txt", "/home/me/b.txt"])
assert.deepStrictEqual(H.filePaths(text("t", "file:///home/me/a.txt")), [], "text that looks like a file is text")
assert.strictEqual(H.previewText(one), "My Photo.png")
assert.strictEqual(H.previewText(two), "2 files")
// A list longer than its preview still says how many files it is.
assert.strictEqual(H.previewText(files("many", ["file:///a"], { count: 300 })), "300 files")
assert.strictEqual(H.fullText(two), "/home/me/a.txt\n/home/me/b.txt")
assert.strictEqual(H.previewText(text("t", "  two\n\tlines  ")), "two lines")
assert.strictEqual(H.fullText(text("t", "two\nlines")), "two\nlines")
assert.strictEqual(H.previewText(image("i")), "Screenshot from Tuesday 14:02")
assert.strictEqual(H.previewText(image("i", { mime: "image/jpeg" })), "Image from Tuesday 14:02")
assert.strictEqual(H.previewText(image("i", { capturedAt: undefined })), "Image")
assert.strictEqual(H.fullText(image("i")), "")
assert.strictEqual(H.previewText(two, k => k, (k, n, english) => "%1 Dateien", n => "<" + n + ">"), "<2> Dateien")

// ---- the picker's rows
const history = [text("new", "Hello World", { time: 4 }), one, image("shot", { time: 2 }), text("old", "second thing", { time: 1, pinned: true, path: PINNED + "/old.txt" })]
let rows = H.displayRows(history, "")
assert.deepStrictEqual(rows.map(row => row.id), ["text:new", "files:one", "image:shot", "text:old"])
assert.deepStrictEqual(rows.map(row => row.entryType), ["text", "file", "image", "text"])
assert.deepStrictEqual(rows.map(row => row.pinned), [false, false, false, true])
assert.strictEqual(rows[1].previewImage, "/home/me/My Photo.png", "one image file shows as a picture")
assert.strictEqual(rows[1].path, SESSION + "/one.uris", "and pastes as the file list")
assert.strictEqual(rows[1].mime, "text/uri-list")
assert.strictEqual(rows[2].previewImage, SESSION + "/shot.png")
assert.strictEqual(H.displayRows([two], "")[0].previewImage, "")
assert.deepStrictEqual(H.displayRows(history, "WORLD").map(row => row.id), ["text:new"])
assert.deepStrictEqual(H.displayRows(history, "photo").map(row => row.id), ["files:one"])
assert.deepStrictEqual(H.displayRows(history, "screenshot").map(row => row.id), ["image:shot"])
assert.deepStrictEqual(H.displayRows(history, "nothing like it"), [])
assert.strictEqual(H.displayRows(history, "", 2).length, 2)
assert.deepStrictEqual(H.displayRows(history, "", 0), [])

console.log("clipboard-history: ok")
