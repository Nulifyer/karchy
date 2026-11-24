function secondsFromConfig(value, fallback) {
  var n = Number(value)
  if (!isFinite(n) || n < 0) return fallback
  return Math.floor(n)
}

// The idle times in effect on one power source, in seconds (0 is never).
// idle.<key> is shared by both sources; idle.battery.<key> and idle.ac.<key>
// set one source apart, "ac" being plugged in or a machine with no battery.
// Sleep differs: the shared idle.suspend counts on battery only, unless
// idle.suspendOnAC is true, so a plugged-in machine sleeps only when asked.
// The screensaver differs too: see screensaverSeconds.
// `dim` is how long before the screen turns off it is dimmed (see dimAfter),
// per source like the others, and `dimBrightness` the percent it is dimmed to.
// bin/karchy-settings-power reads the same keys the same way (Settings ›
// Power); keep the two in step.
function timeouts(config, onBattery, defaults) {
  var idle = config && typeof config === "object" ? config : {}
  var own = idle[onBattery ? "battery" : "ac"]
  if (!own || typeof own !== "object") own = {}

  function set(value) {
    return value !== undefined && value !== null && value !== "" && isFinite(Number(value)) && Number(value) >= 0
  }
  function pick(key) {
    return set(own[key]) ? Math.floor(Number(own[key])) : secondsFromConfig(idle[key], defaults[key])
  }

  var suspend = 0
  if (set(own.suspend)) suspend = Math.floor(Number(own.suspend))
  else if (onBattery || idle.suspendOnAC === true) suspend = secondsFromConfig(idle.suspend, defaults.suspend)

  var screenOff = pick("screenOff")
  var lock = pick("lock")

  return {
    screensaver: screensaverSeconds(set(own.screensaver) ? Math.floor(Number(own.screensaver)) : -1,
      secondsFromConfig(idle.screensaver, defaults.screensaver), defaults.screensaver,
      screenOff > 0 || lock > 0 || suspend > 0),
    screenOff: screenOff,
    lock: lock,
    suspend: suspend,
    dim: pick("dim"),
    dimBrightness: dimBrightness(idle.dimBrightness, defaults.dimBrightness)
  }
}

// The screensaver's time on one power source (0 is never), D-176.
// - `own`, the source's idle.<source>.screensaver (Settings › Power "Start
//   the screensaver"), decides when it is set (-1 when it is not).
// - A shared idle.screensaver that is not karchy's own time was written by
//   hand, for both sources, and decides next.
// - Otherwise karchy's time where something else happens on that source, and
//   never where nothing does: with the screen never turning off, the session
//   never locking and the computer never sleeping, the page says nothing
//   happens when the computer is left alone, and then nothing does.
// A shared time equal to karchy's is karchy's: saving shell.json drops a
// value that repeats a default, so it could not be kept apart anyway.
function screensaverSeconds(own, shared, karchys, somethingHappens) {
  if (own >= 0) return own
  if (shared !== karchys) return shared
  return somethingHappens ? karchys : 0
}

// How long idle until the screensaver starts on these times, 0 for never: its
// time, where that is before the screen turns off, the session locks and the
// computer sleeps. A time at or after the first of those never comes: there
// is nothing to draw on a dark or locked screen. The time itself stays as it
// was chosen, as a screen-off time after the lock's does.
function screensaverAfter(times) {
  if (!(times.screensaver > 0)) return 0
  var first = firstIdleTimeout(times.screenOff, times.lock, times.suspend)
  return first > 0 && times.screensaver >= first ? 0 : times.screensaver
}

// What an idle stretch does on these times: each step in seconds idle from
// its start, 0 where it doesn't happen. The idle service arms its timers
// from this and nothing else.
function plan(times, hasBacklight) {
  return {
    screensaver: screensaverAfter(times),
    dim: dimAfter(times, hasBacklight),
    // A screen-off time at or after the lock's is the lock screen's to keep:
    // it turns the screen off 5 seconds after locking.
    screenOff: times.screenOff > 0 && !(times.lock > 0 && times.lock <= times.screenOff) ? times.screenOff : 0,
    lock: times.lock > 0 ? times.lock : 0,
    suspend: times.suspend > 0 ? times.suspend : 0
  }
}

// The percent a screen is dimmed to: 1 to 99, or the fallback.
function dimBrightness(value, fallback) {
  var n = Number(value)
  if (value === undefined || value === null || value === "" || !isFinite(n) || n < 1 || n > 99) return fallback
  return Math.floor(n)
}

// How long idle until the screen goes dark by itself on these times, 0 for
// never. The screen-off time and the lock both do it (the lock screen turns
// the screen off 5 seconds after it appears), but only where a screen-off
// time is set: with "Never" the lock stays lit. Sleep always does.
function screenDarkAfter(times) {
  var off = times.screenOff > 0 ? firstIdleTimeout(times.screenOff, times.lock) : 0
  return firstIdleTimeout(off, times.suspend)
}

// How long idle until the screen is dimmed, 0 for never: `dim` seconds before
// it goes dark, and no earlier than half way there, so a short screen-off
// time still leaves the screen at its level for most of it. Nothing dims a
// screen that never goes dark, or a machine without a built-in screen.
function dimAfter(times, hasBacklight) {
  if (!hasBacklight || !(times.dim > 0)) return 0
  var dark = screenDarkAfter(times)
  if (!(dark > 0)) return 0
  return Math.max(dark - times.dim, Math.ceil(dark / 2))
}

// The idle service's side of a dimming: when karchy-brightness-display is
// asked to dim and to undim. `state` is { dimmed, undimWanted, dimRunning,
// undimRunning }; `event` is "dim" (the dim timer, with `allowed` false when
// the screen is already off), "undim" (activity, the charger, stay-awake, an
// inhibitor), "dimExited" or "undimExited" (the commands ending). The result
// carries the new state and the command to start now: "dim", "undim" or "".
//
// The rules: one undim follows every dim, and never overtakes it. An undim
// asked for while the dim command still runs waits for it to end: started at
// once it could finish first, find nothing to undo, and leave the screen dim
// with nobody left to ask. A dim asked for while an undim is still owed or
// running is dropped, for the same reason turned round; that stretch is not
// dimmed.
function dimStep(state, event, allowed) {
  var next = {
    dimmed: !!(state && state.dimmed),
    undimWanted: !!(state && state.undimWanted),
    dimRunning: !!(state && state.dimRunning),
    undimRunning: !!(state && state.undimRunning)
  }
  var run = ""

  if (event === "dim") {
    if (allowed !== false && !next.dimmed && !next.undimWanted && !next.dimRunning && !next.undimRunning) {
      next.dimmed = true
      next.dimRunning = true
      run = "dim"
    }
  } else if (event === "undim") {
    if (next.dimmed) {
      next.dimmed = false
      next.undimWanted = true
    }
  } else if (event === "dimExited") {
    next.dimRunning = false
  } else if (event === "undimExited") {
    next.undimRunning = false
  }

  if (run === "" && next.undimWanted && !next.dimRunning && !next.undimRunning) {
    next.undimWanted = false
    next.undimRunning = true
    run = "undim"
  }
  return { state: next, run: run }
}

// A dimming is in place or being undone.
function dimPending(state) {
  return !!(state && (state.dimmed || state.undimWanted || state.dimRunning || state.undimRunning))
}

// The soonest of the given idle times. 0 means the action is disabled, not
// "fire immediately": min(0, 300) would otherwise make IdleMonitor report idle
// as soon as an inhibitor is released.
function firstIdleTimeout() {
  var min = 0
  for (var i = 0; i < arguments.length; i++) {
    var seconds = arguments[i]
    if (seconds > 0 && (min === 0 || seconds < min)) min = seconds
  }
  return min
}

function delayAfterFirstIdle(timeoutSeconds, firstIdleSeconds) {
  if (!(timeoutSeconds > 0)) return 0
  var delay = timeoutSeconds - firstIdleSeconds
  return delay > 0 ? delay : 0
}

function eventParts(event, count) {
  try {
    if (event && event.parse) return event.parse(count)
  } catch (error) {
  }
  return String(event && event.data ? event.data : "").split(",")
}

function screensaverWindowsAfter(windows, address, visible) {
  var key = String(address || "")
  if (!key) {
    var current = windows || {}
    var existingCount = 0
    for (var currentKey in current) {
      if (current[currentKey]) existingCount++
    }
    return { windows: current, count: existingCount }
  }

  var next = {}
  var count = 0
  for (var existing in windows || {}) {
    if (existing !== key && windows[existing]) {
      next[existing] = true
      count++
    }
  }

  if (visible) {
    next[key] = true
    count++
  }

  return {
    windows: next,
    count: count
  }
}

// One line from `karchy-system-idle-inhibit watch`: {"inhibitors": [...]}.
// Returns the list, or null for a line that is not one (which changes nothing).
function parseInhibitors(line) {
  var text = String(line || "").trim()
  if (!text) return null
  try {
    var parsed = JSON.parse(text)
    var list = Array.isArray(parsed) ? parsed : (parsed && parsed.inhibitors)
    if (!Array.isArray(list)) return null
    var out = []
    for (var i = 0; i < list.length; i++) {
      if (list[i] && typeof list[i] === "object") out.push(list[i])
    }
    return out
  } catch (error) {
    return null
  }
}

// Whether any inhibitor holds `kind` ("idle" or "sleep"). logind joins the
// kinds it holds with colons: "idle:sleep".
function inhibits(inhibitors, kind) {
  var list = inhibitors || []
  for (var i = 0; i < list.length; i++) {
    if (String(list[i].what || "").split(":").indexOf(kind) !== -1) return true
  }
  return false
}

function describeInhibitors(inhibitors) {
  var list = inhibitors || []
  var parts = []
  for (var i = 0; i < list.length; i++) {
    var held = list[i]
    var name = String(held.who || held.process || "?")
    var process = held.process && held.process !== name ? " " + held.process : ""
    parts.push(name + " (" + String(held.source || "?") + " " + String(held.what || "?") + process
      + " pid " + String(held.pid || 0) + ")")
  }
  return parts.join("; ")
}

if (typeof module !== "undefined") {
  module.exports = {
    parseInhibitors: parseInhibitors,
    inhibits: inhibits,
    describeInhibitors: describeInhibitors,
    secondsFromConfig: secondsFromConfig,
    timeouts: timeouts,
    dimBrightness: dimBrightness,
    screenDarkAfter: screenDarkAfter,
    dimAfter: dimAfter,
    screensaverSeconds: screensaverSeconds,
    screensaverAfter: screensaverAfter,
    plan: plan,
    dimStep: dimStep,
    dimPending: dimPending,
    firstIdleTimeout: firstIdleTimeout,
    delayAfterFirstIdle: delayAfterFirstIdle,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
