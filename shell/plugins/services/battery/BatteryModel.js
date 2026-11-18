function batteryPercentage(device) {
  if (!device || !device.isPresent) return -1
  return Math.round(Number(device.percentage || 0) * 100)
}

function isDischarging(device, onBattery, dischargingState) {
  return !!(device && device.isPresent && onBattery && device.state === dischargingState)
}

// The levels (percent) for the low and the critical warning, from the
// `battery` block of shell.json. 0 turns a warning off. A critical level at or
// above the low one leaves only the critical warning.
function warningThresholds(config, fallbackLow, fallbackCritical) {
  function percent(value, fallback) {
    var n = Number(value)
    if (value === undefined || value === null || value === "" || !isFinite(n)) return fallback
    return Math.max(0, Math.min(100, Math.floor(n)))
  }
  var source = config && typeof config === "object" ? config : {}
  var low = percent(source.low, fallbackLow)
  var critical = percent(source.critical, fallbackCritical)
  if (critical >= low) low = 0
  return { low: low, critical: critical }
}

// One step of the battery warnings. `warned` is the highest warning already
// shown in this discharge ("", "low" or "critical"); the result carries the
// new value, the warning to show now, if any, and whether the warnings shown
// are to be taken off the screen (`clear`).
//
// Each warning shows once per discharge: a level that wobbles around a
// threshold does not repeat it, and the critical one is not followed by the
// low one. Plugging in the charger clears both, so the next discharge warns
// again, and what they said no longer holds, so they leave the screen. On
// battery without a "discharging" state (some firmware reports unknown for a
// while) nothing is shown and nothing is forgotten.
function warningStep(warned, sample, thresholds) {
  var level = sample ? Number(sample.level) : -1
  if (!sample || !(level >= 0) || !sample.onBattery) return { warned: "", notify: "", clear: !!warned }
  if (!sample.discharging) return { warned: warned, notify: "" }

  if (thresholds.critical > 0 && level <= thresholds.critical) {
    return { warned: "critical", notify: warned === "critical" ? "" : "critical" }
  }
  if (thresholds.low > 0 && level <= thresholds.low) {
    return warned ? { warned: warned, notify: "" } : { warned: "low", notify: "low" }
  }
  return { warned: warned, notify: "" }
}

function parseActiveProfile(text) {
  // busctl --json=short prints {"type":"s","data":"balanced"}; an empty or
  // malformed reply (daemon not running) reads as no active profile.
  try {
    return String(JSON.parse(text).data || "").trim()
  } catch (e) {
    return ""
  }
}

function profileAfterRead(current, replyText, signalsAtStart, signalsNow) {
  // A change signal that arrived during the read is newer than its reply.
  return signalsAtStart === signalsNow ? parseActiveProfile(replyText) : current
}

if (typeof module !== "undefined") {
  module.exports = {
    batteryPercentage: batteryPercentage,
    isDischarging: isDischarging,
    warningThresholds: warningThresholds,
    warningStep: warningStep,
    parseActiveProfile: parseActiveProfile,
    profileAfterRead: profileAfterRead
  }
}
