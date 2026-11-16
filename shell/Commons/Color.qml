pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import "BorderGeometry.js" as Geometry

// Color surfaces for the shell. Foundational palette (foreground, background,
// accent, urgent) comes from theme/colors.toml. Per-surface roles come from
// theme/shell.toml — generated per theme from default/themed/shell.toml.tpl,
// or shipped directly by a theme to replace the generated file. Surfaces that
// don't appear in shell.toml fall back to the foundational palette.
//
// Derived roles (docs/architecture.md, "Shell design foundations"): quieter
// text (`secondaryText`, `disabledText`), the keyboard `focus` ring color and
// the `status` colors are computed from the palette, so every theme gets them
// with a contrast floor and nothing per theme to maintain.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateHome: home + "/.local/state"
  readonly property string currentThemePath: stateHome + "/karchy/current/theme"

  property color foreground: "#cacccc"
  property color background: "#101315"
  property color accent: "#cacccc"
  property color urgent: "#a55555"
  property color muted: "#707880"
  // Every `name = "#rrggbb"` in colors.toml, for roles that look past the
  // fixed keys above (the status colors search red, yellow, green and their
  // bright and ANSI variants).
  property var paletteValues: ({})

  // ---------------------------------------------------------- text roles
  //
  // Quieter text blends the text color toward the surface it sits on, so it
  // fades the same way in dark and light themes (Qt.darker() only fades a
  // light color; on a light theme's dark text it adds contrast instead).
  // The blend then backs off toward the text color until it clears its floor.

  // `c` moved toward `toward` just far enough to reach `ratio` on `surface`;
  // `toward` itself when even that falls short.
  function ensureContrastToward(c, toward, surface, ratio) {
    if (Util.contrast(c, surface) >= ratio) return c
    if (Util.contrast(toward, surface) < ratio) return toward
    var lo = 0, hi = 1
    for (var i = 0; i < 12; i++) {
      var m = (lo + hi) / 2
      if (Util.contrast(Util.mix(toward, c, m), surface) >= ratio) hi = m
      else lo = m
    }
    return Util.mix(toward, c, hi)
  }

  // Secondary text: descriptions, metadata, section headers, placeholders,
  // a dimmed icon that still says something. Readable body text, at least
  // 4.5:1 on its surface (or the text color itself when the theme's own text
  // has less), and clearly quieter than `text`.
  function secondaryText(text, surface) {
    var fg = text === undefined ? root.foreground : text
    var bg = surface === undefined ? root.background : surface
    return ensureContrastToward(Util.mix(fg, bg, 0.72), fg, bg, 4.5)
  }

  // Disabled or out-of-scope content: a control that can't be used now, a day
  // outside the shown month. Visibly present (2:1 floor) but not meant to be
  // read as active content.
  function disabledText(text, surface) {
    var fg = text === undefined ? root.foreground : text
    var bg = surface === undefined ? root.background : surface
    return ensureContrastToward(Util.mix(fg, bg, 0.45), fg, bg, 2.0)
  }

  // On the theme's own text and background, which every surface uses unless
  // its shell.toml section overrides them.
  readonly property color textSecondary: secondaryText(foreground, background)
  readonly property color textDisabled: disabledText(foreground, background)

  // `c` with its HSL lightness pushed away from `surfaces` (lighter on a dark
  // first surface, darker on a light one) until it reaches `ratio` on every
  // one of them. Hue and saturation stay, so a red stays a red.
  function ensureContrastLightness(c, surfaces, ratio) {
    function worst(x) {
      var w = 21
      for (var i = 0; i < surfaces.length; i++) w = Math.min(w, Util.contrast(x, surfaces[i]))
      return w
    }
    if (worst(c) >= ratio) return c
    var h = Math.max(0, c.hslHue), s = c.hslSaturation, l = c.hslLightness
    var up = Util.luminance(surfaces[0]) < 0.18
    var lo = up ? l : 0, hi = up ? 1 : l
    var end = Qt.hsla(h, s, up ? hi : lo, 1)
    if (worst(end) < ratio) return end
    for (var j = 0; j < 14; j++) {
      var m = (lo + hi) / 2
      var ok = worst(Qt.hsla(h, s, m, 1)) >= ratio
      if (up === ok) hi = m
      else lo = m
    }
    return Qt.hsla(h, s, up ? hi : lo, 1)
  }

  // The keyboard focus ring (and the panel/menu keyboard cursor): the theme's
  // accent, kept at 3:1 against the background and against the selected fill
  // it may surround, so it reads as a ring in every theme.
  readonly property color focus: ensureContrastLightness(accent,
    [background, Util.mix(foreground, background, 0.18)], 3.0)

  // Text on a solid accent fill (a primary button): whichever of the theme's
  // background and foreground stands out more on the accent.
  readonly property color onAccent: Util.contrast(background, accent) >= Util.contrast(foreground, accent)
    ? background : foreground

  // ---------------------------------------------------------- status roles
  //
  // error / warning / success start from the theme's red / yellow / green.
  // A theme's slot doesn't always hold that hue (lumon's red is blue,
  // matte-black's yellow is red, the mono themes are grey), and a status
  // color must mean the same thing in every theme, so the first candidate
  // whose hue fits wins, then karchy's default theme's color. A theme can pin
  // one in shell.toml `[status]`. Each is then kept at 4.5:1 on the
  // background, so it works as text, as an icon and as a border; text drawn
  // on a solid status fill uses the paired `on*` color.
  readonly property var statusHues: ({
    error: { ranges: [[340, 360], [0, 25]], keys: ["red", "bright_red", "color1", "color9"], fallback: "#ea6962" },
    warning: { ranges: [[25, 62]], keys: ["yellow", "bright_yellow", "orange", "color3", "color11"], fallback: "#d8a657" },
    success: { ranges: [[62, 175]], keys: ["green", "bright_green", "color2", "color10"], fallback: "#a9b665" }
  })

  function hueFits(c, ranges) {
    if (c.hsvHue < 0 || c.hsvSaturation < 0.25 || c.hsvValue < 0.2) return false
    var deg = c.hsvHue * 360
    for (var i = 0; i < ranges.length; i++)
      if (deg >= ranges[i][0] && deg < ranges[i][1]) return true
    return false
  }

  function statusColor(role) {
    var spec = statusHues[role]
    var base = null
    var pinned = shellValues["status." + role]
    if (typeof pinned === "string" && pinned.length > 0 && !statusHues[pinned.toLowerCase()]) {
      var resolved = flatColor(pinned, null)
      if (resolved) base = Qt.color(resolved)
    }
    for (var i = 0; !base && i < spec.keys.length; i++) {
      var hex = paletteValues[spec.keys[i]]
      if (hex && hueFits(Qt.color(hex), spec.ranges)) base = Qt.color(hex)
    }
    if (!base) base = Qt.color(spec.fallback)
    return ensureContrastLightness(base, [background], 4.5)
  }

  readonly property QtObject status: QtObject {
    readonly property color error: root.statusColor("error")
    readonly property color warning: root.statusColor("warning")
    readonly property color success: root.statusColor("success")
    // Each status color clears 4.5:1 on the background, so the background
    // reads on a solid status fill just as well.
    readonly property color onError: root.background
    readonly property color onWarning: root.background
    readonly property color onSuccess: root.background
  }

  // Flat dictionary of "section.key" -> raw string from shell.toml.
  // Reassigning this whole property is what makes surface bindings below
  // re-evaluate when the theme swaps; mutating it in place would not.
  property var shellValues: ({})

  function pick(key, fallback) {
    var v = shellValues[key]
    return (typeof v === "string" && v.length > 0) ? v : fallback
  }

  function pickAlpha(key, fallback) {
    var v = shellValues[key]
    if (typeof v !== "string" || v.length === 0) return fallback
    var n = Number(v)
    if (!isFinite(n)) return fallback
    return Util.clampAlpha(n)
  }

  function firstColorToken(value) {
    var parts = String(value || "").replace(/^\s+|\s+$/g, "").split(/\s+/)
    for (var i = 0; i < parts.length; i++) {
      if (!parts[i].match(/^-?\d+(?:\.\d+)?deg$/)) return parts[i]
    }
    return value
  }

  function flatColor(value, fallback) {
    var seen = Object.create(null)
    var token = firstColorToken(value)
    var role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    while (root.shellValues[role] && root.shellValues[role] !== token) {
      if (seen[role]) return fallback
      seen[role] = true
      token = firstColorToken(root.shellValues[role])
      role = String(token || "").replace(/^\s+|\s+$/g, "").toLowerCase()
    }
    if (role === "foreground" || role === "text") return root.foreground
    if (role === "accent") return root.accent
    if (role === "urgent") return root.urgent
    if (role === "muted") return root.muted
    if (role === "background") return root.background
    if (role === "focus") return root.focus
    if (role === "error" || role === "warning" || role === "success") return root.status[role]
    if (role === "transparent") return Qt.rgba(0, 0, 0, 0)

    var color = Geometry.canonicalColor(token, 1)
    if (typeof color === "string" && color === token && token.charAt(0) !== "#") return fallback
    return color
  }

  // Compose a color from a base-color key and its `-alpha` companion. If the
  // base token is a gradient, color-only consumers use the first stop.
  function composed(colorKey, alphaKey, colorFallback, alphaFallback) {
    return Util.alpha(flatColor(pick(colorKey, colorFallback), colorFallback), pickAlpha(alphaKey, alphaFallback))
  }

  readonly property QtObject bar: QtObject {
    property color background: root.composed("bar.background", "bar.background-alpha", root.background, 1.0)
    property color text: root.pick("bar.text", root.foreground)
    property color active: root.pick("bar.active", root.urgent)
  }
  readonly property QtObject popups: QtObject {
    property color background: root.composed("popups.background", "popups.background-alpha", root.background, 1.0)
    property color text: root.pick("popups.text", root.foreground)
    property color border: root.composed("popups.border", "popups.border-alpha", root.accent, 1.0)
  }
  readonly property QtObject tooltip: QtObject {
    property color background: root.composed("tooltip.background", "tooltip.background-alpha", root.background, 1.0)
    property color text: root.pick("tooltip.text", root.foreground)
    property color border: root.composed("tooltip.border", "tooltip.border-alpha", root.foreground, 1.0)
  }
  readonly property QtObject notifications: QtObject {
    property color background: root.composed("notifications.background", "notifications.background-alpha", root.background, 1.0)
    property color text: root.pick("notifications.text", root.foreground)
    property color border: root.composed("notifications.border", "notifications.border-alpha", root.accent, 1.0)
    property color countdown: root.pick("notifications.countdown", root.accent)
  }
  readonly property QtObject menu: QtObject {
    property color background: root.composed("menu.background", "menu.background-alpha", root.background, 1.0)
    property color text: root.pick("menu.text", root.foreground)
    property color border: root.composed("menu.border", "menu.border-alpha", root.foreground, 1.0)
    property color scrim: root.composed("menu.scrim", "menu.scrim-alpha", root.background, 0.5)
    property color selectedBackground: root.composed("menu.selected-background", "menu.selected-background-alpha", root.foreground, 0.08)
    property color selectedText: root.pick("menu.selected-text", root.accent)
    property color selectedBorder: root.composed("menu.selected-border", "menu.selected-border-alpha", root.foreground, 0.0)
  }
  // polkit + lock share a single border-alpha across border / border-active /
  // border-error: the three states are mutually exclusive in time, so one
  // companion is enough.
  readonly property QtObject polkit: QtObject {
    property color background: root.composed("polkit.background", "polkit.background-alpha", root.background, 1.0)
    property color text: root.pick("polkit.text", root.foreground)
    property color textError: root.flatColor(root.pick("polkit.text-error", "error"), root.status.error)
    property color border: root.composed("polkit.border", "polkit.border-alpha", root.accent, 1.0)
    property color borderError: root.composed("polkit.border-error", "polkit.border-alpha", root.status.error, 1.0)
    property color accent: root.pick("polkit.accent", root.accent)
    property color scrim: root.composed("polkit.scrim", "polkit.scrim-alpha", root.background, 0.5)
  }
  readonly property QtObject lock: QtObject {
    property color background: root.composed("lock.background", "lock.background-alpha", root.background, 0.8)
    property color text: root.pick("lock.text", root.foreground)
    property color placeholder: root.shellValues["lock.placeholder"] ? root.flatColor(root.shellValues["lock.placeholder"], Util.alpha(root.foreground, 0.66)) : Util.alpha(root.foreground, 0.66)
    property color textError: root.flatColor(root.pick("lock.text-error", "error"), root.status.error)
    property color border: root.composed("lock.border", "lock.border-alpha", root.foreground, 1.0)
    property color borderActive: root.composed("lock.border-active", "lock.border-alpha", root.accent, 1.0)
    property color borderError: root.composed("lock.border-error", "lock.border-alpha", root.status.error, 1.0)
    property color selection: root.composed("lock.selection", "lock.selection-alpha", root.accent, 0.45)
  }
  // The image picker has no card surface or backdrop; per-slice dim
  // overlays / text outlines use the foundational `background` color directly.
  readonly property QtObject imagePicker: QtObject {
    property color text: root.pick("image-picker.text", root.foreground)
    property color selectedBorder: root.composed("image-picker.selected-border", "image-picker.selected-border-alpha", root.accent, 1.0)
    property color unselectedBorder: root.composed("image-picker.unselected-border", "image-picker.unselected-border-alpha", root.foreground, 0.28)
  }

  function loadColors(raw) {
    var lines = String(raw || "").split("\n")
    var foundAccent = false
    var foundMuted = false
    var loadedForeground = false
    var loadedBackground = false
    var color0Value = ""
    var color4Value = ""
    var color7Value = ""
    var color8Value = ""
    var nextPalette = {}
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      if (nextPalette[match[1]] === undefined) nextPalette[match[1]] = match[2]
      if (match[1] === "foreground") { foreground = match[2]; loadedForeground = true }
      else if (match[1] === "background") { background = match[2]; loadedBackground = true }
      // Prefer the explicit `accent` key; only fall back to color4 when the
      // theme doesn't define a separate accent. color4 appears later in the
      // file so the old single-property approach clobbered accent with it.
      else if (match[1] === "accent") { accent = match[2]; foundAccent = true }
      else if (match[1] === "muted") { muted = match[2]; foundMuted = true }
      else if (match[1] === "color0") color0Value = match[2]
      else if (match[1] === "color4") color4Value = match[2]
      else if (match[1] === "color7") color7Value = match[2]
      else if (match[1] === "color8") color8Value = match[2]
      else if (match[1] === "red" || match[1] === "color1") urgent = match[2]
    }
    if (!loadedBackground && color0Value.length > 0) background = color0Value
    if (!loadedForeground && color7Value.length > 0) foreground = color7Value
    if (!foundAccent && color4Value.length > 0) accent = color4Value
    if (!foundMuted) muted = color8Value.length > 0 ? color8Value : foreground
    paletteValues = nextPalette
  }

  // Last theme-supplied and user-supplied shell.toml dicts, kept separate so
  // either can be reloaded without re-reading the other. `shellValues` is
  // always the merge of theme (base) and user (override) — see mergeShell.
  property var themeShellValues: ({})
  property var userShellValues: ({})

  // Single TOML walker for shell.toml. Both Color (surface roles) and Style
  // (typography, spacing, bar, control states) consume the resulting dict.
  // Accepts quoted strings, bare numeric values, bare width lists, and bare
  // role names; tolerates inline comments. Numbers are kept as strings here —
  // readers coerce when they pull a value.
  function parseShell(raw) {
    var parsed = {}
    var text = String(raw || "")
    if (text) {
      var lines = text.split("\n")
      var section = ""
      for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/^\s+|\s+$/g, "")
        if (!line || line.charAt(0) === "#") continue
        var sectionMatch = line.match(/^\[([A-Za-z0-9_-]+)\]\s*(#.*)?$/)
        if (sectionMatch) { section = sectionMatch[1]; continue }
        var stringKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*["']([^"']+)["']\s*(#.*)?$/)
        var numKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?)\s*(#.*)?$/)
        var widthKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*(-?\d+(?:\.\d+)?(?:\s+-?\d+(?:\.\d+)?){1,3})\s*(#.*)?$/)
        var bareKv = line.match(/^([A-Za-z0-9_-]+)\s*=\s*([A-Za-z][A-Za-z0-9_-]*)\s*(#.*)?$/)
        var kv = stringKv || numKv || widthKv || bareKv
        if (!kv || !section) continue
        parsed[section + "." + kv[1]] = kv[2]
      }
    }
    return parsed
  }

  // Re-derive `shellValues` from theme base + user override and push it to
  // Style. User keys win, so a machine-level `~/.config/karchy/shell.toml`
  // survives theme switches (which replace only themeShellValues).
  function mergeShell() {
    var merged = {}
    for (var tk in themeShellValues) merged[tk] = themeShellValues[tk]
    for (var uk in userShellValues) merged[uk] = userShellValues[uk]
    shellValues = merged
    Style.applyShellValues(merged)
  }

  function loadShell(raw) {
    themeShellValues = parseShell(raw)
    mergeShell()
  }

  function loadUserShell(raw) {
    userShellValues = parseShell(raw)
    mergeShell()
  }

  // Startup load only. Runtime theme switches push the payload explicitly
  // through shell IPC.
  property FileView colorsFile: FileView {
    id: colorsFile
    path: root.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadColors(text())
  }
  property FileView shellFile: FileView {
    id: shellFile
    path: root.currentThemePath + "/shell.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.loadShell(text())
    onLoadFailed: root.loadShell("")
  }
  // Machine-level override, layered on top of whatever theme is active. This
  // is where `karchy display text size` writes `[font] base-size`. Watched so the
  // CLI takes effect live without restarting the shell; absent by default.
  property FileView userShellFile: FileView {
    id: userShellFile
    path: root.home + "/.config/karchy/shell.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadUserShell(text())
    // Re-read on change (including first creation) before loading — `text()`
    // is stale in the change signal itself, so route both paths through reload
    // → onLoaded to always parse fresh content.
    onFileChanged: reload()
    onLoadFailed: root.loadUserShell("")
  }
}
