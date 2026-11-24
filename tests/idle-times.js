const assert = require("assert")
const M = require(process.argv[2] + "/shell/plugins/services/idle/IdleModel.js")
const d = { screensaver: 150, screenOff: 300, lock: 300, suspend: 900, dim: 30, dimBrightness: 10 }
const eq = (a, b, msg) => assert.deepStrictEqual(a, b, msg)
const times = (config, onBattery) => { const t = M.timeouts(config, onBattery, d); delete t.dim; delete t.dimBrightness; return t }
eq(times({}, true), { screensaver: 150, screenOff: 300, lock: 300, suspend: 900 })
eq(times({}, false), { screensaver: 150, screenOff: 300, lock: 300, suspend: 0 })
eq(M.timeouts({ suspendOnAC: true, suspend: 600 }, false, d).suspend, 600)
eq(times({ lock: 600, ac: { lock: 120, suspend: 1800 } }, false), { screensaver: 150, screenOff: 300, lock: 120, suspend: 1800 })
eq(times({ lock: 600, ac: { lock: 120, suspend: 1800 } }, true), { screensaver: 150, screenOff: 300, lock: 600, suspend: 900 })
eq(times({ battery: { suspend: 0, screenOff: 0, lock: "x" } }, true), { screensaver: 150, screenOff: 0, lock: 300, suspend: 0 })
eq(M.timeouts({ ac: 5, battery: null }, true, d).lock, 300)
eq(M.firstIdleTimeout(150, 300), 150); eq(M.firstIdleTimeout(0, 0), 0); eq(M.firstIdleTimeout(0, 300, 60, 0), 60); eq(M.firstIdleTimeout(), 0)

// Dimming: how long before the screen turns off, per power source.
const dim = (config, onBattery) => M.timeouts(config, onBattery, d).dim
eq(dim({}, true), 30); eq(dim({}, false), 30)
eq(dim({ dim: 60 }, true), 60, "idle.dim is shared")
eq([dim({ dim: 60, battery: { dim: 10 } }, true), dim({ dim: 60, battery: { dim: 10 } }, false)], [10, 60], "idle.battery.dim sets battery apart")
eq([dim({ ac: { dim: 0 } }, true), dim({ ac: { dim: 0 } }, false)], [30, 0], "0 is never, on that source only")
eq(dim({ dim: "x", battery: { dim: -5 } }, true), 30, "junk falls back")
eq(M.timeouts({}, true, d).dimBrightness, 10)
eq(M.timeouts({ dimBrightness: 25 }, true, d).dimBrightness, 25)
for (const junk of [0, 100, -3, "x", null, ""]) eq(M.timeouts({ dimBrightness: junk }, true, d).dimBrightness, 10, "dimBrightness " + junk)

// karchy's defaults: 30 seconds before on battery, never plugged in. They are
// karchy/shell.json's idle block (merged under the user's, as the shell does)
// and, without that file, the idle service's own fallback per source.
const karchyIdle = JSON.parse(require("fs").readFileSync(process.argv[2] + "/karchy/shell.json", "utf8")).idle
const merged = (user) => { const out = JSON.parse(JSON.stringify(karchyIdle)); for (const k in user) out[k] = (typeof user[k] === "object" && typeof out[k] === "object") ? Object.assign(out[k], user[k]) : user[k]; return out }
const fallback = (onBattery) => Object.assign({}, d, { dim: onBattery ? 30 : 0 })
eq([M.timeouts(karchyIdle, true, d).dim, M.timeouts(karchyIdle, false, d).dim], [30, 0], "karchy's shell.json: 30 s on battery, never plugged in")
eq([M.timeouts({}, true, fallback(true)).dim, M.timeouts({}, false, fallback(false)).dim], [30, 0], "the service's fallback, without shell.json")
eq([M.timeouts(merged({ dim: 60 }), true, d).dim, M.timeouts(merged({ dim: 60 }), false, d).dim], [60, 0], "a shared idle.dim by hand: battery only, plugged in keeps never")
eq(M.timeouts(merged({ ac: { dim: 10 } }), false, d).dim, 10, "idle.ac.dim turns it on plugged in")

// When the screen goes dark by itself, and when it is dimmed before that.
const T = (screenOff, lock, suspend, dimSeconds) => ({ screenOff, lock, suspend, dim: dimSeconds })
eq(M.screenDarkAfter(T(300, 300, 900)), 300)
eq(M.screenDarkAfter(T(300, 120, 900)), 120, "an earlier lock turns the screen off (5 seconds after it)")
eq(M.screenDarkAfter(T(300, 0, 0)), 300, "no lock")
eq(M.screenDarkAfter(T(0, 300, 0)), 0, "screen-off at Never: the lock stays lit")
eq(M.screenDarkAfter(T(0, 300, 900)), 900, "…until the computer sleeps")
eq(M.screenDarkAfter(T(600, 900, 300)), 300, "sleep first")
eq(M.screenDarkAfter(T(0, 0, 0)), 0)
eq(M.dimAfter(T(300, 300, 900, 30), true), 270, "the defaults: 30 seconds before the lock at 5 minutes")
eq(M.dimAfter(T(300, 300, 900, 30), false), 0, "no built-in screen: never")
eq(M.dimAfter(T(300, 300, 900, 0), true), 0, "dim at Never")
eq(M.dimAfter(T(0, 300, 0, 30), true), 0, "a screen that never turns off is never dimmed")
eq(M.dimAfter(T(0, 300, 900, 30), true), 870, "before sleep where only sleep darkens it")
eq(M.dimAfter(T(60, 0, 0, 30), true), 30)
eq(M.dimAfter(T(60, 0, 0, 120), true), 30, "no earlier than half way")
eq(M.dimAfter(T(10, 0, 0, 30), true), 5)
eq(M.dimAfter(T(15, 0, 0, 10), true), 8, "half way, rounded up")
eq(M.dimAfter(T(600, 120, 0, 10), true), 110, "counts back from the lock when that is first")
// The dimming is always before the dark, so it starts the idle cycle or follows the screensaver.
for (const [off, lock, sleep] of [[300, 300, 900], [60, 0, 0], [10, 10, 10], [0, 0, 20], [86400, 0, 0]])
  for (const lead of [5, 10, 30, 60, 120, 600]) {
    const at = M.dimAfter(T(off, lock, sleep, lead), true), dark = M.screenDarkAfter(T(off, lock, sleep))
    assert.ok(at > 0 && at < dark, `dim at ${at} before dark at ${dark}`)
  }

// The order of the dim and undim commands. Walk events and collect what is
// started; a command "exits" when the walk says so.
function walk(events, start) {
  let state = start || {}, started = []
  for (const event of events) {
    const [name, allowed] = Array.isArray(event) ? event : [event, undefined]
    const step = M.dimStep(state, name, allowed)
    state = step.state
    if (step.run) started.push(step.run)
  }
  return started.join(",") + "|" + (M.dimPending(state) ? "pending" : "clear")
}
eq(walk([]), "|clear")
// The service's start runs an undim of a dimming it doesn't know of (D-172):
// a dim timer that fires before it ends is not started over it.
const starting = { undimRunning: true }
eq(walk(["undimExited"], starting), "|clear", "the start's undim ends: nothing owed")
eq(walk(["dim", "undimExited"], starting), "|clear", "a dim while the start's undim runs is not started")
eq(walk(["undimExited", "dim"], starting), "dim|pending", "…and the next one is")
eq(walk(["undim"]), "|clear", "activity without a dimming: nothing to run")
eq(walk(["dim"]), "dim|pending")
eq(walk(["dim", "dimExited"]), "dim|pending", "dimmed until somebody comes back")
eq(walk(["dim", "dimExited", "undim"]), "dim,undim|pending", "activity: undim")
eq(walk(["dim", "dimExited", "undim", "undimExited"]), "dim,undim|clear")
eq(walk(["dim", "undim"]), "dim|pending", "activity while the dim command still runs: the undim waits")
eq(walk(["dim", "undim", "dimExited"]), "dim,undim|pending", "…and follows it")
eq(walk(["dim", "undim", "dimExited", "undimExited"]), "dim,undim|clear")
eq(walk(["dim", "dim", "dimExited", "dim"]), "dim|pending", "dimmed once per stretch")
eq(walk(["dim", "dimExited", "undim", "undim", "undimExited", "undim"]), "dim,undim|clear", "one undim for one dim")
eq(walk(["dim", "dimExited", "undim", "dim"]), "dim,undim|pending", "a dim while the undim runs is dropped")
eq(walk(["dim", "dimExited", "undim", "dim", "undimExited"]), "dim,undim|clear", "…so the screen is not left dim")
eq(walk(["dim", "undim", "dim", "dimExited", "undimExited"]), "dim,undim|clear", "a dim while an undim is owed is dropped")
eq(walk([["dim", false]]), "|clear", "the screen is already off: nothing to dim")
eq(walk(["dim", "dimExited", "undim", "undimExited", "dim", "dimExited", "undim", "undimExited"]), "dim,undim,dim,undim|clear", "the next stretch dims again")
// Whatever the order of events, every dim is followed by exactly one undim once activity came.
{
  const names = ["dim", "undim", "dimExited", "undimExited"]
  let seed = 7
  const pick = () => names[(seed = (seed * 1103515245 + 12345) >>> 0) % names.length]
  for (let run = 0; run < 2000; run++) {
    let state = {}, dims = 0, undims = 0, dimRunning = false, undimRunning = false
    const feed = (name) => {
      // A command can only exit while it runs.
      if (name === "dimExited" && !dimRunning) return
      if (name === "undimExited" && !undimRunning) return
      if (name === "dimExited") dimRunning = false
      if (name === "undimExited") undimRunning = false
      const step = M.dimStep(state, name)
      state = step.state
      if (step.run === "dim") { assert.ok(!dimRunning && !undimRunning, "dim never overlaps a command"); dims++; dimRunning = true }
      if (step.run === "undim") { assert.ok(!dimRunning && !undimRunning, "undim never overlaps a command"); undims++; undimRunning = true }
      assert.ok(undims <= dims, "no undim before its dim")
    }
    for (let i = 0; i < 12; i++) feed(pick())
    for (const name of ["undim", "dimExited", "undimExited", "dimExited", "undimExited"]) feed(name)
    eq([dims - undims, M.dimPending(state)], [0, false], "settles with every dim undone")
  }
}
console.log("idle model ok")
