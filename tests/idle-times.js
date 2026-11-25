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

// The screensaver, per power source (D-176). Its default follows the other
// times: karchy's 150 seconds where something else happens on that source,
// never where nothing does.
const saver = (user, onBattery) => M.timeouts(merged(user), onBattery, d).screensaver
eq(karchyIdle.screensaver, d.screensaver, "karchy's shell.json and the service's fallback name the same time")
eq([saver({}, true), saver({}, false)], [150, 150], "the defaults: the screen turns off and locks on both sources")
// The report this is for: plugged in, screen-off and lock at Never (sleep is
// Never there by default); on battery the defaults.
const reported = { ac: { lock: 0, screenOff: 0 } }
eq([saver(reported, true), saver(reported, false)], [150, 0], "nothing else happens plugged in: no screensaver there")
eq(M.plan(M.timeouts(merged(reported), false, d), true), { screensaver: 0, dim: 0, screenOff: 0, lock: 0, suspend: 0 }, "…and so nothing at all")
eq(saver({ ac: { lock: 0, screenOff: 0, suspend: 1800 } }, false), 150, "sleep alone is something happening")
eq(saver({ ac: { lock: 0 } }, false), 150, "so is the screen turning off")
eq(saver({ ac: { screenOff: 0 } }, false), 150, "and the lock")
eq(saver({ screenOff: 0, lock: 0, suspendOnAC: true }, false), 150, "sleep plugged in through idle.suspendOnAC")
eq([saver({ screenOff: 0, lock: 0, suspend: 0 }, true), saver({ screenOff: 0, lock: 0 }, true)], [0, 150], "on battery the same rule; sleep counts there by default")
eq(saver({ battery: { screenOff: 0, lock: 0, suspend: 0 } }, false), 150, "one source's Never leaves the other alone")
// A choice in the row wins over the default, in both directions.
eq(saver({ ac: { lock: 0, screenOff: 0, screensaver: 300 } }, false), 300, "chosen where nothing else happens: it starts")
eq([saver({ ac: { screensaver: 0 } }, false), saver({ ac: { screensaver: 0 } }, true)], [0, 150], "Never chosen where something does: that source only")
eq([saver({ battery: { screensaver: 600 } }, true), saver({ battery: { screensaver: 600 } }, false)], [600, 150], "a time of its own on battery")
eq(saver({ ac: { screensaver: 150, lock: 0, screenOff: 0 } }, false), 150, "karchy's time, chosen: a choice like any other")
eq(saver({ ac: { screensaver: "x" } }, false), 150, "junk falls back")
eq(saver({ ac: { screensaver: -5, lock: 0, screenOff: 0 } }, false), 0, "…to the rule")
// A shared idle.screensaver written by hand keeps working, on both sources,
// when it is not karchy's own time; that one follows the rule.
eq([saver({ screensaver: 600 }, true), saver({ screensaver: 600 }, false)], [600, 600], "a shared time by hand: both sources")
eq(saver({ screensaver: 600, ac: { lock: 0, screenOff: 0 } }, false), 600, "…also where nothing else happens")
eq([saver({ screensaver: 0 }, true), saver({ screensaver: 0 }, false)], [0, 0], "a shared 0 by hand: never, as before")
eq(saver({ screensaver: 0, ac: { screensaver: 120 } }, false), 120, "the source's own wins over the shared one")
eq(saver({ screensaver: 150, ac: { lock: 0, screenOff: 0 } }, false), 0, "a shared 150 is karchy's default and follows the rule")
eq(saver({ screensaver: "150" }, true), 150, "a number written as text")
// Without shell.json's idle block at all (the shell's built-in fallback).
eq([M.timeouts({}, true, d).screensaver, M.timeouts({ ac: { lock: 0, screenOff: 0 } }, false, d).screensaver], [150, 0])

// When the screensaver starts: its time, where that is before the screen
// turns off and the computer sleeps. The lock comes under it (D-184).
const S = (screensaver, screenOff, lock, suspend) => ({ screensaver, screenOff, lock, suspend, dim: 30 })
eq(M.screensaverAfter(S(150, 300, 300, 900)), 150, "the defaults")
eq(M.screensaverAfter(S(0, 300, 300, 900)), 0, "Never")
eq(M.screensaverAfter(S(300, 0, 0, 0)), 300, "alone: it starts and stays")
eq(M.screensaverAfter(S(600, 300, 0, 0)), 0, "after the screen has turned off: never")
eq(M.screensaverAfter(S(300, 300, 0, 0)), 0, "at the screen-off time: never")
eq(M.screensaverAfter(S(600, 0, 300, 0)), 600, "after the lock: it starts, on the lock screen")
eq(M.screensaverAfter(S(600, 0, 0, 300)), 0, "after the computer sleeps: never")
eq(M.screensaverAfter(S(150, 600, 120, 0)), 150, "a lock before it does not stop it")
eq(M.screensaverAfter(S(299, 300, 300, 900)), 299)
// The order holds for every combination: the screensaver, where it starts,
// is before the screen-off time and sleep; the dimming is before the screen
// goes dark; this service turns the screen off at its own time, locked or not.
{
  const values = [0, 10, 60, 150, 300, 600, 900]
  for (const screensaver of values) for (const screenOff of values) for (const lock of values) for (const suspend of values)
    for (const lead of [0, 30, 120]) {
      const times = { screensaver, screenOff, lock, suspend, dim: lead }
      const plan = M.plan(times, true), name = JSON.stringify(times)
      for (const other of [screenOff, suspend])
        assert.ok(plan.screensaver === 0 || other === 0 || plan.screensaver < other, "screensaver before the rest: " + name)
      assert.ok(plan.screensaver === 0 || plan.screensaver === screensaver, "its own time or never: " + name)
      const dark = M.screenDarkAfter(times)
      assert.ok(plan.dim === 0 || (plan.dim > 0 && plan.dim < dark), "dimmed before dark: " + name)
      eq(plan.screenOff, screenOff, "the screen-off time as it is: " + name)
      eq([plan.lock, plan.suspend], [lock, suspend], name)
      // What starts the idle cycle is the first step of the plan.
      eq(M.firstIdleTimeout(plan.screensaver, screenOff, lock, suspend, plan.dim),
        M.firstIdleTimeout(plan.screensaver, plan.screenOff, plan.lock, plan.suspend, plan.dim), "first step: " + name)
    }
}

// The times change under an idle stretch: the charger goes in or out, the
// power fails, or shell.json is edited. What has not happened follows the
// new times, counted from when the stretch began.
eq([M.dueIn(300, 100000), M.dueIn(300, 299500), M.dueIn(300, 400000), M.dueIn(0, 5000)], [200000, 1000, 1000, 0])
const P = (user, onBattery) => M.plan(M.timeouts(merged(user), onBattery, d), true)
const ms = (s) => s * 1000
// On battery with the defaults, 100 seconds in, the charger goes in.
eq(M.retimed(P(reported, false), {}, ms(100)), { endScreensaver: false, screensaver: 0, dim: 0, screenOff: 0, lock: 0 },
  "plugged in where nothing happens, the screensaver about to start: it doesn't")
eq(M.retimed(P(reported, false), { screensaver: true }, ms(200)), { endScreensaver: true, screensaver: 0, dim: 0, screenOff: 0, lock: 0 },
  "…and one already running ends")
// Plugged in with a screensaver of its own and nothing else; the power fails.
const savingOnly = { ac: { lock: 0, screenOff: 0, screensaver: 150 } }
eq(M.retimed(P(savingOnly, true), { screensaver: true }, ms(200)), { endScreensaver: false, screensaver: 0, dim: ms(70), screenOff: ms(100), lock: ms(100) },
  "on battery after a power cut: the screensaver stays, and the battery's dimming, lock and screen-off are armed")
eq(M.retimed(P(savingOnly, true), {}, ms(100)), { endScreensaver: false, screensaver: ms(50), dim: ms(170), screenOff: ms(200), lock: ms(200) },
  "before it started: at the battery's time, counted from the stretch's start")
// A later time on the new source: a running one stays, a pending one waits.
const later = { ac: { screensaver: 240 } }
eq(M.retimed(P(later, false), { screensaver: true }, ms(200)).endScreensaver, false, "a running screensaver stays where the new source has one")
eq(M.retimed(P(later, false), {}, ms(100)).screensaver, ms(140), "a pending one moves to the new time")
// Times already past on the new source.
const quick = { battery: { screensaver: 60, screenOff: 120, lock: 0, suspend: 0 } }
eq(M.retimed(P(quick, true), {}, ms(90)), { endScreensaver: false, screensaver: 1000, dim: 0, screenOff: ms(30), lock: 0 },
  "its time has passed: it starts now; the dimming's time has passed too and is not made up")
eq(M.retimed(P(quick, true), {}, ms(130)), { endScreensaver: false, screensaver: 0, dim: 0, screenOff: 1000, lock: 0 },
  "…but not only to be ended by the screen turning off at once")
eq(M.retimed(P({ battery: { lock: 60 } }, true), { screensaver: true }, ms(200)), { endScreensaver: false, screensaver: 0, dim: ms(70), screenOff: ms(100), lock: 1000 },
  "a lock whose time has passed locks now, under the screensaver, which goes on")
eq(M.retimed(P({ battery: { lock: 60 } }, true), {}, ms(100)).screensaver, ms(50), "a lock already due does not keep a screensaver from starting")
eq(M.retimed(P({}, true), { screensaver: true, screenOff: true }, ms(400)), { endScreensaver: false, screensaver: 0, dim: 0, screenOff: 0, lock: 1000 },
  "a screen already off stays off and is not dimmed")
eq(M.retimed(P({ battery: { screensaver: 0 } }, true), { screensaver: true }, ms(200)).endScreensaver, true, "Never chosen on the new source ends it")
// Every combination: nothing is armed that the new times don't have, and
// the screensaver never starts at or after the screen going off.
{
  const values = [0, 60, 150, 300, 600]
  for (const screensaver of values) for (const screenOff of values) for (const lock of values) for (const suspend of values)
    for (const elapsed of [ms(30), ms(100), ms(200), ms(700)]) for (const started of [false, true]) {
      const plan = M.plan({ screensaver, screenOff, lock, suspend, dim: 30 }, true)
      const next = M.retimed(plan, { screensaver: started }, elapsed), name = JSON.stringify([plan, elapsed, started])
      eq(next.endScreensaver, started && plan.screensaver === 0, name)
      for (const step of ["screensaver", "dim", "screenOff", "lock"]) assert.ok(plan[step] > 0 || next[step] === 0, step + " not armed: " + name)
      if (next.screensaver > 0) for (const step of ["screenOff"])
        assert.ok(next[step] === 0 || next.screensaver < next[step], "screensaver before " + step + ": " + name)
      assert.ok(!started || next.screensaver === 0, "not started twice: " + name)
    }
}

// When the screen goes dark by itself, and when it is dimmed before that.
// T has no screensaver, as on a source where it is Never: the lock screen
// then turns the screen off itself. With one, the lock screen shows it.
const T = (screenOff, lock, suspend, dimSeconds) => ({ screensaver: 0, screenOff, lock, suspend, dim: dimSeconds })
eq(M.screenDarkAfter(T(300, 300, 900)), 300)
eq(M.screenDarkAfter(T(300, 120, 900)), 120, "an earlier lock turns the screen off (5 seconds after it)")
eq(M.screenDarkAfter(Object.assign(T(300, 120, 900), { screensaver: 150 })), 300, "…unless it shows the screensaver: dark at the screen-off time")
eq(M.dimAfter(Object.assign(T(300, 120, 0, 30), { screensaver: 150 }), true), 270, "and dimmed before that")
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
