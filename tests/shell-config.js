const assert = require("assert")
const fs = require("fs")
const M = require(process.argv[2] + "/shell/Commons/ShellConfigModel.js")
const defaults = JSON.parse(fs.readFileSync(process.argv[2] + "/karchy/shell.json"))
const eq = (a, b, msg) => assert.deepStrictEqual(a, b, msg)

// no user keys: defaults
eq(M.merge(defaults, { version: 1 }), defaults)
// one scalar: the rest follows defaults
let m = M.merge(defaults, { version: 1, bar: { style: "docked" } })
eq(m.bar.style, "docked"); eq(m.bar.layout, defaults.bar.layout); eq(m.idle, defaults.idle)
// arrays replace whole
m = M.merge(defaults, { version: 1, bar: { layout: { right: [{ id: "karchy.audio" }] } } })
eq(m.bar.layout.right, [{ id: "karchy.audio" }]); eq(m.bar.layout.left, defaults.bar.layout.left)
// unknown keys are kept; null and scalar replace an object
m = M.merge(defaults, { version: 1, dock: { pinned: ["a"] }, lock: null, idle: 5 })
eq(m.dock, { pinned: ["a"] }); eq(m.lock, null); eq(m.idle, 5)
// merge does not alias its inputs
m = M.merge(defaults, { version: 1 }); m.bar.layout.left.push("x")
assert.notDeepStrictEqual(m.bar.layout.left, defaults.bar.layout.left)

// saving: unchanged config saves only the version
eq(M.userFileFor(defaults, JSON.parse(JSON.stringify(defaults))), { version: 1 })
// a changed scalar saves just that
let c = JSON.parse(JSON.stringify(defaults)); c.lock.clock = false
eq(M.userFileFor(defaults, c), { version: 1, lock: { clock: false } })
// back to the default: nothing left
c.lock.clock = true
eq(M.userFileFor(defaults, c), { version: 1 })
// a changed list saves that list whole, its siblings not at all
c = JSON.parse(JSON.stringify(defaults)); c.bar.layout.center[0].format = "HH:mm"
eq(M.userFileFor(defaults, c), { version: 1, bar: { layout: { center: c.bar.layout.center } } })
// keys the defaults lack are saved; removed default keys are not
c = JSON.parse(JSON.stringify(defaults)); c.bar.id = "local.x"; delete c.idle.suspend; delete c.lock
eq(M.userFileFor(defaults, c), { version: 1, bar: { id: "local.x" } })
// round trip for a mix of changes
c = JSON.parse(JSON.stringify(defaults)); c.idle.lock = 600; c.plugins = [{ id: "p" }]; c.bar.position = "left"; c.extra = { a: { b: 1 } }
eq(M.merge(defaults, M.userFileFor(defaults, c)), c)

// an old full copy: defaults changed since (lock 300 -> 240, new widget, new key)
const old = JSON.parse(JSON.stringify(defaults))
const next = JSON.parse(JSON.stringify(defaults))
next.idle.lock = 240; next.bar.layout.right.push({ id: "karchy.new" }); next.battery = { low: 15, critical: 5 }
m = M.merge(next, old)
eq(m.idle.lock, 300, "the copy's value wins")
eq(m.bar.layout.right, old.bar.layout.right, "the copy's list wins")
eq(m.battery, { low: 15, critical: 5 }, "a key newer than the copy arrives")
// its next save keeps only what differs from today's defaults
eq(M.userFileFor(next, m), { version: 1, idle: { lock: 300 }, bar: { layout: { right: old.bar.layout.right } } })
// a full copy equal to today's defaults shrinks to nothing
eq(M.userFileFor(defaults, M.merge(defaults, JSON.parse(JSON.stringify(defaults)))), { version: 1 })
console.log("config model: ok")
