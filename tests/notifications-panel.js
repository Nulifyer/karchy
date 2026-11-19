const assert = require("assert")
const root = process.argv[2]
const M = require(root + "/shell/plugins/notifications/PanelModel.js")

// Delivery.js is a QML library (.pragma, .import): load its functions with
// the one thing it imports stubbed.
const fs = require("fs")
const src = fs.readFileSync(root + "/shell/plugins/notifications/Delivery.js", "utf8").replace(/^\.(pragma|import).*$/gm, "")
const D = new Function("Security", src + "\nreturn { verdict: verdict, waits: waits, silent: silent, isSystem: isSystem }")({})

// ---- what pops up (Delivery.verdict) and what waits in the panel (Delivery.waits)
const LOW = 0, NORMAL = 1, CRITICAL = 2
const n = (app, urgency, extra) => Object.assign({ app, urgency }, extra || {})
// Allow: a popup. Low urgency from an app goes silently; karchy's own low toasts still show.
assert.strictEqual(D.verdict(n("Signal", NORMAL), false, undefined), "")
assert.strictEqual(D.verdict(n("Signal", LOW), false, undefined), "low")
assert.strictEqual(D.verdict(n("karchy-action", LOW), false, undefined), "")
assert.strictEqual(D.verdict(n("notify-send", LOW), false, undefined), "")
// Silent: no popup, except critical. Off: dropped, whatever it is.
assert.strictEqual(D.verdict(n("Signal", NORMAL), false, "silent"), "muted")
assert.strictEqual(D.verdict(n("Signal", CRITICAL), false, "silent"), "")
assert.strictEqual(D.verdict(n("Signal", CRITICAL), false, "off"), "blocked")
assert.strictEqual(D.verdict(n("Signal", NORMAL, { code: "123456" }), false, "off"), "blocked")
// Do Not Disturb: everything but sign-in codes, karchy's own toasts and bare critical notify-send.
assert.strictEqual(D.verdict(n("Signal", NORMAL), true, undefined), "silenced")
assert.strictEqual(D.verdict(n("Signal", CRITICAL), true, undefined), "silenced")
assert.strictEqual(D.verdict(n("Signal", NORMAL, { code: "123456" }), true, "silent"), "")
assert.strictEqual(D.verdict(n("karchy-action", NORMAL), true, undefined), "")
assert.strictEqual(D.verdict(n("notify-send", CRITICAL), true, undefined), "")
assert.strictEqual(D.verdict(n("notify-send", NORMAL), true, undefined), "silenced")
// Unanswered ones wait; answered, transient and karchy's low-urgency feedback don't.
for (const reason of ["expired", "silenced", "muted", "low"]) assert.strictEqual(D.waits(n("Signal", NORMAL), reason), true)
for (const reason of ["dismissed", "activated", "closed", ""]) assert.strictEqual(D.waits(n("Signal", NORMAL), reason), false)
assert.strictEqual(D.waits(n("Signal", NORMAL, { transient: true }), "expired"), false)
assert.strictEqual(D.waits(n("karchy-action", LOW), "expired"), false)
assert.strictEqual(D.waits(n("karchy-action", NORMAL), "expired"), true)
assert.deepStrictEqual(["muted", "low", "silenced", "expired"].map(D.silent), [true, true, false, false])

// ---- the panel's rows
const e = (key, app, ts, extra) => Object.assign({ key, app, ts, closed_ts: ts + 8, waiting: true, silent: false,
  groupKey: "app:" + app.toLowerCase() }, extra || {})
const show = (rows) => rows.map((r) => r.kind === "entry" ? r.entry.key
  : r.kind === "header" ? "[" + r.section + "]" : (r.open ? "less" : "more:" + r.count))

// One kind of notification: just a list. One from an app stands alone; two or more fold under the newest.
const list = [e("a", "Signal", 100), e("b", "Mail", 300), e("c", "Signal", 200), e("held", "Signal", 400, { closed_ts: 400 })]
assert.deepStrictEqual(show(M.rows(list, {}, {})), ["held", "more:2", "b"])
assert.deepStrictEqual(show(M.rows(list, {}, { "alerting/app:signal": true })), ["held", "c", "a", "less", "b"])
// Only what waits is listed; the rest is history, newest first, unfolded.
const done = e("done", "Mail", 500, { waiting: false })
assert.deepStrictEqual(show(M.rows(list.concat([done]), {}, {})), ["held", "more:2", "b"])
assert.deepStrictEqual(show(M.historyRows(list.concat([done, e("old", "Mail", 50, { waiting: false })]))), ["done", "old"])
// Sections: ongoing, then alerting, then silent; headers only with more than one section,
// and none over the alerting section when it comes first.
const quiet = e("q", "Sync", 600, { silent: true })
const going = e("dl", "Transmission", 50)
const ongoing = {}; ongoing[M.entryId(going)] = true
assert.deepStrictEqual(show(M.rows([quiet], {}, {})), ["q"])
assert.deepStrictEqual(show(M.rows([going], ongoing, {})), ["dl"])
assert.deepStrictEqual(show(M.rows(list.concat([quiet]), {}, {})), ["held", "more:2", "b", "[silent]", "q"])
assert.deepStrictEqual(show(M.rows(list.concat([quiet, going]), ongoing, {})),
  ["[ongoing]", "dl", "[alerting]", "held", "more:2", "b", "[silent]", "q"])
// An app with one ongoing and one alerting notification has one row in each section, not a group.
assert.deepStrictEqual(show(M.rows([going, e("t2", "Transmission", 60)], ongoing, {})), ["[ongoing]", "dl", "[alerting]", "t2"])
// Karchy's own toasts and bare notify-send have no app to name: one System group, with no rule key.
const sys = M.rows([e("x", "notify-send", 2), e("y", "karchy-action", 1, { groupKey: "toast:y" })], {}, {})
assert.deepStrictEqual(show(sys), ["x", "more:1"])
assert.strictEqual(sys[0].system, true)
assert.strictEqual(sys[0].app, "system")
// A browser's notification is grouped, named and ruled by its site.
assert.deepStrictEqual(M.groupOf({ app: "Firefox", groupKey: "web:mail.example.org" }), { id: "web:mail.example.org", label: "mail.example.org", system: false })
assert.strictEqual(M.rows([e("s", "Signal", 1)], {}, {})[0].app, "app:signal")
// An app with an internal name is listed under the name karchy uses; its rule key is still its own.
assert.deepStrictEqual(M.groupOf({ app: "omasnap", groupKey: "app:omasnap" }), { id: "app:omasnap", label: "Screenshot", system: false })
assert.strictEqual(M.groupOf({ app: "udiskie", groupKey: "app:udiskie" }).label, "Drives")
assert.strictEqual(M.appLabel("Signal"), "Signal")
// The same key closed twice is two rows.
const twice = M.historyRows([e("k", "Chat", 1, { waiting: false }), e("k", "Chat", 1, { waiting: false, closed_ts: 50 })])
assert.notStrictEqual(twice[0].id, twice[1].id)
// When a row leaves, the cursor takes the next row, else the one before, never a header.
const rows = M.rows(list.concat([quiet]), {}, {})
assert.strictEqual(M.neighbour(rows, 0), rows[1].id)
assert.strictEqual(M.neighbour(rows, 2), rows[4].id)
assert.strictEqual(M.neighbour(rows, 4), rows[2].id)
assert.strictEqual(M.neighbour([rows[0]], 0), "")
assert.strictEqual(M.indexOfId(rows, rows[4].id), 4)
// Ages: now, minutes, the clock time today, yesterday, then the day.
const midnight = 1000 * 86400000, now = midnight + 10 * 3600000
const age = (secondsAgo) => M.age((now - secondsAgo * 1000) / 1000, now, midnight).kind
assert.strictEqual(age(30), "now")
assert.deepStrictEqual(M.age((now - 600000) / 1000, now, midnight), { kind: "minutes", value: 10 })
assert.strictEqual(age(2 * 3600), "time")
assert.strictEqual(age(11 * 3600), "yesterday")
assert.strictEqual(age(40 * 3600), "day")
assert.strictEqual(M.age(0, now, midnight).kind, "")
console.log("notifications panel model ok")
