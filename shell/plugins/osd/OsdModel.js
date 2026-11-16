function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value))
}

// Icons are names from default/karchy/icons.json; Osd.qml draws them with
// Icons.resolve, which also passes through a glyph a caller sent as is.
//
// The widest icon `iconFor` can return. The progress OSD sizes its icon
// column to it so the bar keeps its place as the icon changes.
var widestIcon = "audio.volume.high"

function iconFor(name, percent) {
  var n = String(name || "").toLowerCase()
  if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return "audio.volume.muted"
  if (n === "volume-low") return "audio.volume.low"
  if (n === "volume-medium") return "audio.volume.medium"
  if (n === "volume-high" || n === "volume") return "audio.volume.high"
  if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "audio.mic.muted"
  if (n === "microphone" || n === "mic") return "audio.mic"
  if (n === "keyboard") return "input.keyboard"
  if (n === "brightness" || n === "display") return "display"
  if (n === "touchpad") return "input.trackpad"
  if (n === "touch" || n === "touchscreen") return "input.touch"
  if (n === "reboot" || n === "restart") return "system.reboot"
  if (n === "shutdown" || n === "power" || n === "poweroff") return "system.power"
  if (n === "logout" || n === "sign-out" || n === "leave") return "system.logout"
  if (n === "media" || n === "player") return "media.music"
  if (n === "media-source" || n === "player-source") return "media.music"
  if (n === "media-play" || n === "player-play") return "media.play"
  if (n === "media-pause" || n === "player-pause") return "media.pause"
  if (n === "media-next" || n === "player-next") return "media.next"
  if (n === "media-previous" || n === "player-previous") return "media.previous"
  if (n.length > 0) return name
  if (percent <= 0) return "audio.volume.muted"
  if (percent <= 33) return "audio.volume.low"
  if (percent <= 66) return "audio.volume.medium"
  return "audio.volume.high"
}

// fmt(value) writes the percentage in the display language; QML passes
// I18n.formatNumber, and without it the digits stay as they are.
function stateForShow(iconName, rawMessage, rawValue, rawMax, rawProgressText, rawDuration, fmt) {
  var number = typeof fmt === "function" ? fmt : function(v) { return String(v) }
  var maxValue = Math.max(1, parseInt(rawMax || "100", 10))
  var parsedValue = parseInt(rawValue || "0", 10)
  var hasProgress = rawValue !== "" && !isNaN(parsedValue) && rawMessage === ""
  var value = hasProgress ? clamp(parsedValue, 0, maxValue) : 0
  var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
  var parsedDuration = parseInt(rawDuration || "1200", 10)

  return {
    iconKey: String(iconName || "").toLowerCase(),
    maxValue: maxValue,
    hasProgress: hasProgress,
    value: value,
    message: String(rawMessage || (hasProgress ? (rawProgressText || number(percent) + "%") : "")),
    icon: iconFor(iconName, percent),
    duration: isNaN(parsedDuration) ? 1200 : Math.max(0, parsedDuration)
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    widestIcon: widestIcon,
    iconFor: iconFor,
    stateForShow: stateForShow
  }
}
