// Whether a notification reaches the screen, and where the deck sits. Pure
// functions over a snapshot row (Store.snapshot).
.pragma library
.import "Security.js" as Security

var CRITICAL = 2

// Karchy's own action toasts and bare notify-send critical alerts get through
// Do Not Disturb. Critical alone is not enough: chat apps send
// critical to force visibility, under their own app name.
function bypassesQuiet(row) {
  var app = String((row && row.app) || "")
  if (app === "karchy-action") return true
  return app === "notify-send" && Number(row.urgency) === CRITICAL
}

// The buttons a card offers, in the order it draws them and the number keys
// count them: copying each code it found, then an Karchy sender's --action
// buttons, then the sender's own actions. A code's label is left to the card,
// which translates it.
function deeds(row, senderActions) {
  var out = []
  var codes = String((row && (row.codes || row.code)) || "").split(" ")
  for (var c = 0; c < codes.length; c++)
    if (codes[c]) out.push({ kind: "code", value: codes[c], label: "" })
  var exec = Security.parseExecActions(row && row.execActions) || []
  for (var e = 0; e < exec.length; e++)
    out.push({ kind: "exec", value: e, label: exec[e].label })
  var actions = senderActions || []
  for (var i = 0; i < actions.length; i++)
    out.push({ kind: "action", value: String(actions[i].id), label: String(actions[i].text || "") })
  return out
}

// Nobody looks back at these (the `transient` hint, or an unnamed sender), so
// quiet drops them rather than holding them.
function isEphemeral(row) {
  if (row && row.transient === true) return true
  var app = String((row && row.app) || "")
  return app === "notify-send" || app === "karchy-action"
}

var LOW = 0

// Karchy's own toasts and bare notify-send: no app to name or to set a rule for.
function isSystem(row) {
  var app = String((row && row.app) || "")
  return app === "" || app === "notify-send" || app === "karchy-action"
}

// Why a notification gets no popup, or "" when it gets one. `mode` is the
// sender's setting: "silent", "off", or anything else for Allow.
//   blocked   its app is turned off: it is dropped
//   silenced  Do Not Disturb is on
//   muted     its app is set to Silent
//   low       it came with a low urgency (an app's own "no need to look")
// A verification code always shows: it was asked for a moment ago and expires
// in minutes. Critical gets past an app's Silent setting and its own low
// urgency, but not past Do Not Disturb: chat apps send critical to force
// visibility (bypassesQuiet has the ones that do pass).
function verdict(row, doNotDisturb, mode) {
  if (mode === "off") return "blocked"
  if (String((row && row.code) || "")) return ""
  if (bypassesQuiet(row)) return ""
  if (doNotDisturb) return "silenced"
  if (Number(row && row.urgency) === CRITICAL) return ""
  if (mode === "silent") return "muted"
  // Karchy's own low-urgency toasts are feedback for something just done.
  if (Number(row && row.urgency) === LOW && !isSystem(row)) return "low"
  return ""
}

// Whether a notification that closed for `reason` waits in the notifications
// panel: nobody answered it (its popup timed out, or it got none), and it is
// worth looking back at.
var UNANSWERED = ["expired", "silenced", "muted", "low"]
function waits(row, reason) {
  if (UNANSWERED.indexOf(String(reason)) < 0) return false
  if (!row || row.transient === true) return false
  if (isSystem(row) && Number(row.urgency) === LOW) return false
  return true
}

// The panel's Silent section: no popup by the app's choice or the user's.
function silent(reason) {
  return reason === "muted" || reason === "low"
}

// A summary that opens with its own glyph (one code point, then two spaces,
// as in "<bell>  Silenced") already carries its mark, so the card drops the
// icon slot.

function summaryStartsWithGlyph(summary) {
  var text = String(summary || "").replace(/^\s+/, "")
  if (!text) return false
  var offset = 1
  var first = text.charCodeAt(0)
  if (first >= 0xd800 && first <= 0xdbff && text.length > 1) offset = 2
  var spaces = 0
  while (offset < text.length && text.charAt(offset) === " ") {
    spaces++
    offset++
  }
  return spaces >= 2
}

// The bar's thickness on one screen (a notch can thicken it on one only), 0
// when hidden, the default when there is no bar.
function barThickness(bar, screenName, defaultBarSize) {
  if (!bar) return Number(defaultBarSize) || 0
  if (bar.barHidden) return 0
  var size = Number(typeof bar.barSizeFor === "function" ? bar.barSizeFor(screenName) : bar.barSize)
  if (!isFinite(size) || size <= 0) size = Number(defaultBarSize) || 0
  return Math.max(0, size)
}

// The deck hangs from the top-right corner, so it clears the bar only on the
// two edges it touches.
function deckMargins(barPosition, thickness, gap) {
  var position = String(barPosition || "top")
  var edge = Number(gap)
  if (!isFinite(edge)) edge = 0
  var bar = Number(thickness)
  if (!isFinite(bar)) bar = 0
  return {
    top: (position === "top" ? bar : 0) + edge,
    right: (position === "right" ? bar : 0) + edge
  }
}
