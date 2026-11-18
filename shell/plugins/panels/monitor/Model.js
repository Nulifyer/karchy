// The scale presets offered everywhere a monitor scale is picked: the display
// panel and Settings › Displays. karchy-hyprland-monitor-scaling's SCALES
// (keyboard up/down) is the same list.
var SCALE_PRESETS = ["1", "1.25", "1.6", "2", "3", "4"]

function clampBrightness(value) {
  var n = Number(value)
  if (!isFinite(n)) return 1
  return Math.max(1, Math.min(100, Math.round(n)))
}

function normalizeScale(scale) {
  var n = parseFloat(String(scale || ""))
  if (!isFinite(n)) return ""
  return String(Math.round(n * 100) / 100)
}

function gcd(a, b) {
  while (b) {
    var remainder = a % b
    a = b
    b = remainder
  }
  return a
}

function cleanScale(scale, width, height) {
  var requested = Number(scale)
  var modeWidth = Number(width)
  var modeHeight = Number(height)
  if (!isFinite(requested) || !isFinite(modeWidth) || !isFinite(modeHeight)
      || requested <= 0 || modeWidth <= 0 || modeHeight <= 0) return ""

  var divisor = gcd(Math.round(modeWidth * 120), Math.round(modeHeight * 120))
  var scaleUnits = Math.round(requested * 120)
  if (scaleUnits > divisor) scaleUnits = divisor
  while (divisor % scaleUnits !== 0) scaleUnits++
  return normalizeScale(scaleUnits / 120)
}

function matchingScaleIndex(scales, currentScale, width, height) {
  var current = Number(currentScale)
  if (!Array.isArray(scales) || !isFinite(current)) return -1

  var bestIndex = -1
  var bestDistance = Infinity
  var normalizedCurrent = normalizeScale(current)
  for (var i = 0; i < scales.length; i++) {
    if (cleanScale(scales[i], width, height) !== normalizedCurrent) continue

    var distance = Math.abs(Number(scales[i]) - current)
    if (distance < bestDistance) {
      bestIndex = i
      bestDistance = distance
    }
  }
  return bestIndex
}

function availableScales(scales, width, height) {
  if (!Array.isArray(scales) || Number(width) <= 0 || Number(height) <= 0) return scales || []

  var byEffectiveScale = {}
  for (var i = 0; i < scales.length; i++) {
    var requested = Number(scales[i])
    var effective = Number(cleanScale(requested, width, height))

    if (!isFinite(requested) || !isFinite(effective)) continue

    var key = normalizeScale(effective)
    var existing = byEffectiveScale[key]
    if (!existing || Math.abs(requested - effective) < existing.distance) {
      byEffectiveScale[key] = {
        value: String(scales[i]),
        index: i,
        distance: Math.abs(requested - effective)
      }
    }
  }

  return Object.keys(byEffectiveScale)
    .map(function(key) { return byEffectiveScale[key] })
    .sort(function(a, b) { return a.index - b.index })
    .map(function(candidate) { return candidate.value })
}

// tr is an optional translate(key, english) from the QML side (I18n.t);
// without it the English text stands, which is what the Node tests assert.
function brightnessName(percent, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var p = Math.round(percent)
  if (p >= 95) return t("monitor.level.sunBlast", "Sun blast")
  if (p >= 80) return t("monitor.level.solarFlare", "Solar flare")
  if (p >= 65) return t("monitor.level.goldenHour", "Golden hour")
  if (p >= 45) return t("monitor.level.evenDay", "Even day")
  if (p >= 30) return t("monitor.level.softGlow", "Soft glow")
  if (p >= 20) return t("monitor.level.lampLight", "Lamp light")
  if (p >= 10) return t("monitor.level.candlelit", "Candlelit")
  return t("monitor.level.nightOwl", "Night owl")
}

function parseDisplays(raw) {
  var displays = []
  try {
    displays = raw ? JSON.parse(String(raw)) : []
  } catch (e) {
    displays = []
  }
  if (!Array.isArray(displays)) displays = []

  var count = 0
  for (var i = 0; i < displays.length; i++) {
    if (displays[i] && displays[i].enabled) count++
  }

  return {
    displays: displays,
    enabledDisplayCount: count
  }
}

// karchy-settings-nightlight's status, or null when the text isn't one (the
// command is missing, or failed).
function parseNightLight(raw) {
  var status = null
  try {
    status = JSON.parse(String(raw || "").trim())
  } catch (e) {
    return null
  }
  if (!status || typeof status !== "object") return null
  return {
    installed: status.installed === true,
    on: status.on === true,
    until: String(status.until || "")
  }
}

// The line under the night light's name. The switch already shows on or off,
// so this says what a schedule will do next ("On until 07:00"), or with no
// schedule what the night light is.
function nightLightLabel(on, until, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (!until) return t("monitor.nightLightHint", "Warmer colors for the evening")
  return on
    ? t("monitor.nightLightOnUntil", "On until %1").replace("%1", until)
    : t("monitor.nightLightOffUntil", "Off until %1").replace("%1", until)
}

if (typeof module !== "undefined") {
  module.exports = {
    clampBrightness: clampBrightness,
    normalizeScale: normalizeScale,
    cleanScale: cleanScale,
    matchingScaleIndex: matchingScaleIndex,
    availableScales: availableScales,
    brightnessName: brightnessName,
    parseDisplays: parseDisplays,
    parseNightLight: parseNightLight,
    nightLightLabel: nightLightLabel
  }
}
