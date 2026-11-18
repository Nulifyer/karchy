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

  return {
    screensaver: secondsFromConfig(idle.screensaver, defaults.screensaver),
    screenOff: pick("screenOff"),
    lock: pick("lock"),
    suspend: suspend
  }
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
    firstIdleTimeout: firstIdleTimeout,
    delayAfterFirstIdle: delayAfterFirstIdle,
    eventParts: eventParts,
    screensaverWindowsAfter: screensaverWindowsAfter
  }
}
