// Display numbers go through the shell's I18n.formatNumber when QML passes
// it; Node tests leave it out and get plain English digits.
function formatter(fmt) {
  return typeof fmt === "function" ? fmt : function(v, d) { return d === undefined ? String(v) : Number(v).toFixed(d) }
}

function parseNetworkStatus(raw) {
  var parts = String(raw || "disconnected\t\t\t\t").replace(/\r?\n+$/, "").split("\t")
  return {
    kind: parts[0] || "disconnected",
    label: parts[1] || "",
    signalStrength: parts[2] ? parseInt(parts[2], 10) : -1,
    frequency: parts[3] || "",
    vpn: parts[4] || ""
  }
}

// Icon names from default/karchy/icons.json; the QML draws them with Icons.glyph.
// NetworkManager turns dBm into its 0-100 strength with two formulas: scan
// results map -100..-40 dBm linearly onto 0..100, and the connected access
// point's station refresh uses dBm + 120 (floor 30 at -90 dBm). The same link
// reads 83 after a scan and 70 between scans at -50 dBm. The two only meet at
// -70 dBm, so every cut-off leaves a few dB where they disagree; these keep
// those bands to about 4 dB: full from -60 dBm (-64 for scan results), three
// from -70, two from -80 (-76), one down to about -90.
function wifiIconFor(strength) {
  var index = strength >= 60 ? 4 : strength >= 50 ? 3 : strength >= 40 ? 2 : strength >= 15 ? 1 : 0
  return "net.wifi." + index
}

// The connected network's own strength comes from the access points
// Quickshell grouped under its SSID. When it has none (an OWE transition-mode
// network between scans files the in-use access point under its hidden
// "_owetm_" twin), fall back to the strength NetworkManager reports for the
// access point in use.
function connectedSignalStrength(networkStrength, activeApSignal) {
  var strength = Math.round((networkStrength || 0) * 100)
  if (strength > 0) return strength
  return activeApSignal > 0 ? activeApSignal : strength
}

// Reads `nmcli -t -f IN-USE,SIGNAL device wifi list` output, where the in-use
// access point is the row marked "*".
function parseActiveApSignal(raw) {
  var lines = String(raw || "").split(/\r?\n/)
  for (var i = 0; i < lines.length; i++) {
    var match = /^\*:(\d+)$/.exec(lines[i].trim())
    if (match) return parseInt(match[1], 10)
  }
  return -1
}

// The page "Sign in to network" opens, on an explicit click only. It has to be
// plain HTTP so the portal can redirect it to its login page. NetworkManager
// keeps detecting portals with Arch's own check, but archlinux.org is
// HSTS-preloaded, so a browser forces HTTPS there and the portal can't
// intercept it. neverssl.com exists for exactly this. The floating-window rule
// (default/hypr/apps/captive-portal.lua) matches its host. Never execute or
// automatically open an untrusted Location header.
var captivePortalUrl = "http://neverssl.com"

function connectivityState(kind, connectivity, states, checksEnabled, limitedSettled) {
  if (kind === "disconnected") return "none"
  // Ignore stale cached results when the operator has disabled probing.
  if (!checksEnabled) return "unknown"
  if (connectivity === states.Portal) return "portal"
  // NetworkManager reports Limited for every fresh link until its first probe
  // answers, so it is only an outage once it has held.
  if (connectivity === states.Limited) return limitedSettled ? "limited" : "unknown"
  if (connectivity === states.Full) return "full"
  if (connectivity === states.None) return "none"
  return "unknown"
}

// The bar's one network icon. While the VPN protects the connection it gets
// the VPN variant of the same glyph (a lock on the Wi-Fi strength, a shield on
// Ethernet), so a protected link reads as such at a glance. With nothing
// connected in airplane mode it is the airplane.
function connectionIcon(kind, signalStrength, connectivity, vpnState, airplane) {
  if (kind === "disconnected" && airplane) return "net.airplane"
  var restricted = connectivity === "portal" || connectivity === "limited"
  var vpn = vpnState === "protecting" && !restricted ? ".vpn" : ""
  if (kind === "wifi") return restricted ? "net.wifi.restricted" : wifiIconFor(signalStrength) + vpn
  if (kind === "ethernet") return restricted ? "net.ethernet.restricted" : "net.ethernet" + vpn
  return "net.wifi.off"
}

// ---- The VPN (nulifyer-vpn, D-68) -------------------------------------------
// The VPN package publishes /run/nulifyer-vpn/status (JSON, rewritten
// atomically on every change): mode off|auto|on; state standing-by,
// connecting, protecting, failed, paused or off; reason; network (the link
// it applies to, with trust); until (a sign-in pause's end, epoch seconds).
// The panel watches the file; this adapter is all it knows of the format.
var vpnStates = ["off", "standing-by", "connecting", "protecting", "failed", "paused"]

function parseVpnStatus(raw) {
  var none = { present: false, mode: "", state: "", reason: "", network: null, until: 0 }
  var text = String(raw || "").trim()
  if (text === "") return none
  try {
    var value = JSON.parse(text)
    if (!value || vpnStates.indexOf(value.state) < 0) return none
    return {
      present: true,
      mode: ["off", "auto", "on"].indexOf(value.mode) >= 0 ? value.mode : "auto",
      state: value.state,
      reason: String(value.reason || ""),
      network: value.network || null,
      until: Number(value.until) || 0
    }
  } catch (error) {
    return none
  }
}

// The internet is blocked on purpose: the guard holds traffic until the
// tunnel is up.
function vpnBlocksInternet(vpn) {
  return !!(vpn && vpn.present && (vpn.state === "connecting" || vpn.state === "failed"))
}

// "error" while it failed, "warning" while it connects or is paused for a
// sign-in, "" otherwise. The bar icon and the status line take this color.
function vpnTone(vpn) {
  if (!vpn || !vpn.present) return ""
  if (vpn.state === "failed") return "error"
  if (vpn.state === "connecting" || vpn.state === "paused") return "warning"
  return ""
}

// One line under the VPN controls saying what the VPN does right now.
// formatTime turns epoch seconds into the clock time ("7:12 PM").
function vpnStatusLine(vpn, tr, formatTime) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (!vpn || !vpn.present) return ""
  switch (vpn.state) {
  case "protecting":
    if (vpn.network && vpn.network.trusted) return t("network.vpnProtectingHome", "Protecting this connection. Local devices stay reachable.")
    return t("network.vpnProtecting", "Protecting this connection")
  case "connecting": return t("network.vpnConnecting", "Connecting. The internet is blocked until it's up.")
  case "failed": return t("network.vpnFailed", "Can't connect. The internet is blocked.")
  case "paused":
    var until = vpn.until && typeof formatTime === "function" ? formatTime(vpn.until) : ""
    return until !== ""
      ? t("network.vpnPausedUntil", "Paused while you sign in, until %1").replace("%1", until)
      : t("network.vpnPaused", "Paused while you sign in")
  case "standing-by":
    if (vpn.reason === "trusted") return t("network.vpnStandingBy", "Standing by on a trusted network")
    return t("network.vpnWaiting", "Waiting for a network")
  case "off": return t("network.vpnOff", "Not protecting this connection")
  }
  return ""
}

// The bar's tooltip while the VPN needs attention; "" when it doesn't.
function vpnTooltip(vpn, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (!vpn || !vpn.present) return ""
  if (vpn.state === "connecting") return t("network.vpnConnectingTooltip", "VPN connecting: internet blocked")
  if (vpn.state === "failed") return t("network.vpnFailedTooltip", "VPN can't connect: internet blocked")
  if (vpn.state === "paused") return t("network.vpnPausedTooltip", "VPN paused while you sign in")
  return ""
}

// ---- Radios and airplane mode (rfkill) --------------------------------------
// `rfkill event` prints every radio once when it starts, then each change:
// "2026-11-14 10:00:00,1+01:00: idx 0 type 1 op 0 soft 0 hard 0". op 0 adds a
// radio, 1 removes it, 2 and 3 change it; type 1 is Wi-Fi. `radios` maps idx to
// { type, soft, hard }; this returns the next map.
function applyRfkillEvent(radios, line) {
  var match = /idx (\d+) type (\d+) op (\d+) soft (\d+) hard (\d+)/.exec(String(line || ""))
  var next = {}
  var key
  for (key in radios || {}) next[key] = radios[key]
  if (!match) return next
  if (match[3] === "1") delete next[match[1]]
  else next[match[1]] = { type: parseInt(match[2], 10), soft: match[4] === "1", hard: match[5] === "1" }
  return next
}

// Whether every radio, or any, is blocked in software. Airplane mode is
// karchy-airplane's remembered choice while every radio is still blocked:
// turning Wi-Fi off blocks its radio too, and with Bluetooth already off that
// would otherwise read as airplane mode.
function radioState(radios) {
  var keys = Object.keys(radios || {})
  var allSoft = keys.length > 0
  var anySoft = false
  var wifiHard = false
  for (var i = 0; i < keys.length; i++) {
    var radio = radios[keys[i]]
    if (!radio.soft) allSoft = false
    else anySoft = true
    if (radio.type === 1 && radio.hard) wifiHard = true
  }
  return { allBlocked: allSoft, anyBlocked: anySoft, radios: keys.length, wifiHardBlocked: wifiHard }
}

// ---- What the panel says: hero and attention row ----------------------------
// `s` is the combined state the panel knows:
//   nm          NetworkManager answers on D-Bus
//   networking  NetworkManager's networking is on (`nmcli networking`)
//   adapter     a Wi-Fi or Ethernet device exists
//   airplane    every radio is blocked (karchy-airplane)
//   hardwareBlocked  the Wi-Fi radio is blocked by a hardware switch
//   wifiRadio   a Wi-Fi device exists; wifiEnabled its software switch
//   kind        "wifi", "ethernet" or "disconnected"
//   name        the connected network's title ("Home-5G", "Ethernet (1gbit)")
//   connectingTo  the network being joined, "" when none
//   connectivity  connectivityState(); vpn  parseVpnStatus(); dns  dnsNotice()
function vpnGuards(vpn) {
  return !!(vpn && vpn.present && vpn.mode !== "off")
}

// { title, status, tone }: the hero's title, its caps status line (the real
// state, in words), and "error" / "warning" / "" for their color. The status
// is short: beside the hero's buttons a caps line holds about 22 letters, and
// the attention row and the VPN row say the rest (the internet is blocked).
function heroState(s, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var state = s || {}
  var vpn = state.vpn || {}
  if (!state.nm || state.networking === false) return { title: t("network.networkingOff", "Networking is off"), status: "", tone: "" }
  if (!state.adapter) return { title: t("network.noAdapter", "No network adapter"), status: "", tone: "" }
  if (state.kind === "disconnected") {
    if (state.airplane) return { title: t("network.airplaneMode", "Airplane mode"), status: "", tone: "" }
    if (state.hardwareBlocked && state.wifiRadio)
      return { title: t("network.wifiOff", "Wi-Fi is off"), status: t("network.wifiOffHardwareSwitch", "With the hardware switch"), tone: "" }
    if (state.wifiRadio && !state.wifiEnabled) return { title: t("network.wifiOff", "Wi-Fi is off"), status: "", tone: "" }
    if (state.connectingTo) return { title: t("network.connectingTo", "Connecting to %1…").replace("%1", state.connectingTo), status: "", tone: "" }
    return { title: t("network.notConnectedTitle", "Not connected"), status: "", tone: "" }
  }
  var title = state.name || ""
  if (state.connectivity === "portal") return { title: title, status: t("network.statusSignIn", "Sign-in required"), tone: "warning" }
  if (vpn.present && vpn.state === "connecting") return { title: title, status: t("network.statusVpnConnecting", "VPN connecting"), tone: "warning" }
  if (vpn.present && vpn.state === "failed") return { title: title, status: t("network.statusVpnFailed", "VPN can't connect"), tone: "error" }
  if (vpn.present && vpn.state === "paused") return { title: title, status: t("network.statusVpnPaused", "VPN paused to sign in"), tone: "warning" }
  if (state.connectivity === "limited" || state.connectivity === "none") return { title: title, status: t("network.statusNoInternet", "No internet"), tone: "warning" }
  if (state.dns === "blocked") return { title: title, status: t("network.statusDnsBlocked", "DNS blocked"), tone: "warning" }
  var status = t("network.statusConnected", "Connected")
  if (vpn.present && vpn.state === "protecting") status = t("network.statusVpnProtecting", "VPN protecting")
  else if (vpn.present && vpn.state === "standing-by" && vpn.reason === "trusted") status = t("network.statusTrusted", "Trusted network")
  else if (state.airplane) status = t("network.statusAirplane", "Airplane mode")
  return { title: title, status: status, tone: "" }
}

// The one row that asks for something, or null. Only while the person has to
// act or know why nothing works: networking off, airplane mode, the hardware
// switch, a sign-in page, a failed VPN, DNS blocked. `actions` are in the order
// shown; the first is the one the row is for.
function attention(s, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var state = s || {}
  var vpn = state.vpn || {}
  if (!state.nm || state.networking === false)
    return { id: "networking", kind: "warning",
      text: !state.nm ? t("network.nmNotRunning", "NetworkManager isn't running, so nothing can connect.")
                      : t("network.networkingDisabled", "All connections are turned off."),
      actions: [{ id: "restart", label: t("network.restartNetworking", "Restart networking") }] }
  if (!state.adapter) return null
  if (state.airplane)
    return { id: "airplane", kind: "info", text: t("network.airplaneOn", "Every radio is off."),
      actions: [{ id: "airplane-off", label: t("network.airplaneOff", "Turn off airplane mode") }] }
  if (state.hardwareBlocked && state.wifiRadio && state.kind === "disconnected")
    return { id: "hardware", kind: "info", text: t("network.hardwareSwitchHint", "Turn Wi-Fi on with the switch or key on the computer."), actions: [] }
  if (state.kind !== "disconnected" && state.connectivity === "portal")
    return { id: "portal", kind: "warning", text: t("network.signInToNetwork", "Sign in to this network"),
      actions: [{ id: "sign-in", label: vpnGuards(vpn) ? t("network.signInVpnPaused", "Sign in, VPN paused until online") : t("network.signIn", "Sign in") }] }
  if (vpn.present && vpn.state === "failed")
    return { id: "vpn", kind: "error", text: t("network.vpnFailedMessage", "The VPN can't connect, so the internet stays blocked."),
      actions: [
        { id: "vpn-retry", label: t("network.vpnRetry", "Retry") },
        { id: "vpn-sign-in", label: t("network.vpnSignIn", "Sign in to network"), tooltip: t("network.vpnSignInTooltip", "") },
        { id: "vpn-off", label: t("network.vpnUseWithout", "Use without VPN"), tooltip: t("network.vpnUseWithoutTooltip", "") }
      ] }
  if (state.kind !== "disconnected" && state.dns === "blocked")
    return { id: "dns", kind: "warning", text: t("network.dnsBlocked", "Websites won't load: this network blocks encrypted DNS."),
      actions: [{ id: "dns-settings", label: t("network.dnsSettings", "DNS settings…") }] }
  return null
}

// ---- Encrypted DNS (karchy-network-dns) -------------------------------------
// /run/karchy/dns/<device> holds the link's DNS state ("state=applied" and so
// on): fallback means the network blocks encrypted DNS and its own DNS is used;
// blocked means encrypted only was chosen, so nothing resolves on this link.
function parseDnsState(raw) {
  var match = /^state=([a-z]+)$/m.exec(String(raw || ""))
  return match ? match[1] : ""
}

// What the panel says about it: "blocked" or "fallback" while it matters.
// It doesn't while the VPN protects (its DNS goes through the tunnel) or
// blocks the internet anyway (the VPN's own message says so).
function dnsNotice(dnsState, vpn) {
  if (vpn && vpn.present && ["protecting", "connecting", "failed"].indexOf(vpn.state) >= 0) return ""
  if (dnsState === "blocked" || dnsState === "fallback") return dnsState
  return ""
}

function formatHeaderSpeed(mbps, fmt) {
  var f = formatter(fmt)
  var v = parseInt(mbps, 10)
  if (!v || v < 0) return ""
  if (v >= 1000) return f(v / 1000, v % 1000 === 0 ? 0 : 1) + "gbit"
  return f(v) + "mbit"
}

function formatHeaderFreq(mhz, fmt) {
  var f = formatter(fmt)
  var v = parseFloat(mhz)
  if (!v) return ""

  if (v >= 2400 && v < 2500) return f(2.4) + "ghz"
  if (v >= 4900 && v < 5925) return f(5) + "ghz"
  if (v >= 5925 && v < 7125) return f(6) + "ghz"
  if (v >= 57000 && v < 71000) return f(60) + "ghz"

  var ghz = v / 1000
  return f(ghz, ghz % 1 === 0 ? 0 : 1) + "ghz"
}

// Wi-Fi band state belongs in the selector section, not beside the hero name.
// Ethernet has no equivalent selector, so keep its negotiated link speed here.
function headerDetail(info, fmt) {
  var value = info || {}
  if (value.type === "ethernet") return formatHeaderSpeed(value.speed || "", fmt)
  return ""
}

// What the speed test measures: the link, and the VPN when the internet goes
// through it ("Home-5G via VPN"), since the tunnel is then what is tested.
function speedTestConnection(info, tr) {
  var value = info || {}
  var name = ""
  if (value.type === "wifi") name = value.ssid || "Wi-Fi"
  else if (value.type === "ethernet") name = tr("network.ethernet")
  if (name && value.vpn_full === "yes") name = tr("network.viaVpn").replace("%1", name)
  return name
}

function bandLabel(band, tr, fmt) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (band === "auto") return t("network.bandAuto", "Auto")
  if (!band) return ""
  // The band stays the script's "2.4" everywhere else; only the label is
  // written in the language's digits.
  var number = Number(band)
  return (isFinite(number) ? formatter(fmt)(number) : band) + "ghz"
}

// Under Automatic the pills are hidden, so the header carries the live band
// instead -- "WI-FI BAND: 2.4GHZ". Once a band is pinned the pills are on
// screen and say it themselves, so the header drops back to a plain label.
function bandSectionTitle(selected, current, tr, fmt) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (selected !== "auto") return t("network.wifiBand", "WI-FI BAND")

  var label = bandLabel(current, tr, fmt)
  if (label === "") return t("network.wifiBand", "WI-FI BAND")

  return t("network.wifiBandCurrent", "WI-FI BAND: %1").replace("%1", label.toUpperCase())
}

function bandTooltip(band, tr, fmt) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (band === "auto") return t("network.bandAutoTooltip", "Let Wi-Fi pick the band")
  if (!band) return ""
  return t("network.stayOnBand", "Stay on %1").replace("%1", bandLabel(band, tr, fmt))
}

function parseBandStatus(raw) {
  var next = parseKeyValue(raw)
  var tokens = String(next.available || "").split(" ")
  var available = []

  for (var i = 0; i < tokens.length; i++) {
    if (tokens[i] !== "") available.push(tokens[i])
  }

  return {
    band: next.band || "",
    selected: next.selected || "auto",
    available: available
  }
}

function decodeIwSsid(value) {
  var raw = String(value || "")

  try {
    var encoded = ""

    for (var i = 0; i < raw.length; i++) {
      if (raw[i] === "\\" && raw[i + 1] === "x" && /^[0-9a-f]{2}$/i.test(raw.substring(i + 2, i + 4))) {
        var hex = raw.substring(i + 2, i + 4)
        var byte = parseInt(hex, 16)
        encoded += byte < 32 || byte === 127 ? encodeURIComponent(raw.substring(i, i + 4)) : "%" + hex
        i += 3
      } else {
        encoded += encodeURIComponent(raw[i])
      }
    }

    return decodeURIComponent(encoded)
  } catch (error) {
    return raw
  }
}

function parseKeyValue(raw) {
  var next = {}
  var lines = String(raw || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    if (!line) continue
    var idx = line.indexOf("\t")
    if (idx === -1) continue
    var key = line.substring(0, idx)
    var value = line.substring(idx + 1)
    next[key] = key === "ssid" ? decodeIwSsid(value) : value.trim()
  }
  return next
}

function pingSampleValue(raw) {
  var value = parseFloat(raw)
  if (!isFinite(value) || value < 0) return null
  return value
}

function appendPingSample(samples, raw, limit) {
  var values = Array.isArray(samples) ? samples.slice() : []

  values.push(pingSampleValue(raw))
  while (values.length > limit) values.shift()

  return values
}

function averagePingLatency(samples, limit) {
  var values = Array.isArray(samples) ? samples : []
  var sampleLimit = Math.max(1, parseInt(limit, 10) || values.length || 1)
  var total = 0
  var count = 0

  for (var i = Math.max(0, values.length - sampleLimit); i < values.length; i++) {
    var value = values[i]
    if (typeof value !== "number" || !isFinite(value) || value < 0) continue
    total += value
    count++
  }

  return count > 0 ? total / count : -1
}

function pingPacketLossPercent(samples) {
  var values = Array.isArray(samples) ? samples : []
  if (values.length === 0) return 0

  var lost = 0
  for (var i = 0; i < values.length; i++) {
    if (values[i] === null) lost++
  }

  return Math.round((lost / values.length) * 100)
}

// Ping and loss only mean something once the internet is reachable. Behind a
// portal, on a limited link or offline every probe is lost by design, so the
// rows read "--" instead of a "Timeout" and "100%" that just restate that.
function internetPingReadable(samples, connectivity) {
  var values = Array.isArray(samples) ? samples : []
  if (connectivity === "portal" || connectivity === "limited" || connectivity === "none") return false
  return values.length > 0
}

function formatPacketLoss(percent, hasSamples, fmt) {
  var f = formatter(fmt)
  if (hasSamples === false) return "--"

  var value = parseInt(percent, 10)
  if (!value || value < 0) return f(0) + "%"
  return f(value) + "%"
}

function pingLatencyState(previous, next, limit, averageLimit) {
  var prev = previous || {}
  var sample = next || {}
  var iface = sample.iface || ""
  var window = Math.max(1, parseInt(limit, 10) || 5)
  var averageWindow = Math.max(1, parseInt(averageLimit, 10) || window)
  var reset = iface === "" || iface !== (prev.pingIface || "")
  var routerSamples = reset ? [] : prev.routerPingSamples
  var internetSamples = reset ? [] : prev.internetPingSamples

  routerSamples = sample.router_ping_ms === undefined ? [] : appendPingSample(routerSamples, sample.router_ping_ms, window)
  internetSamples = sample.internet_ping_ms === undefined ? [] : appendPingSample(internetSamples, sample.internet_ping_ms, window)

  return {
    pingIface: iface,
    routerPingSamples: routerSamples,
    internetPingSamples: internetSamples,
    routerPingLatency: averagePingLatency(routerSamples, averageWindow),
    internetPingLatency: averagePingLatency(internetSamples, averageWindow),
    internetPingPacketLoss: pingPacketLossPercent(internetSamples)
  }
}

// `hasSamples` false means no probe has come back yet, which is different from
// a probe that timed out. The rows stay mounted through that gap and read "--"
// so the grid doesn't reflow a second after the panel opens.
function formatPingLatency(ms, hasSamples, tr, fmt) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var f = formatter(fmt)
  if (hasSamples === false) return "--"

  var value = parseFloat(ms)
  if (!isFinite(value) || value < 0) return t("network.timeout", "Timeout")
  return f(value, value > 0 && value < 10 ? 1 : 0) + " ms"
}

function wifiRow(network) {
  if (!network) return null
  // Primitives only: rows become list-model data, so a WifiNetwork here puts a
  // live QObject wrapper in every delegate's var property. NetworkManager churn
  // (scans, AP removals) can destroy the object while a delegate is still
  // incubating, which segfaults quickshell in wrap_slowPath on the dangling
  // wrapper. Callers that need the object resolve it via networkForSsid().
  return {
    connected: !!network.connected,
    known: !!network.known,
    ssid: network.name || "",
    signal: Math.round((network.signalStrength || 0) * 100),
    security: network.security
  }
}

// Every listed network's state as one comparable value. A network can connect,
// drop, be saved or be forgotten without the list itself changing.
function wifiStateKey(networks) {
  var list = networks || []
  var keys = []
  for (var i = 0; i < list.length; i++) {
    var n = list[i]
    if (n) keys.push([n.name || "", !!n.connected, !!n.known, !!n.stateChanging, n.security].join("\u001f"))
  }
  return keys.sort().join("\u001e")
}

function sortWifiRows(rows) {
  var nets = Array.isArray(rows) ? rows.slice() : []
  nets.sort(function(a, b) {
    if (a.connected !== b.connected) return a.connected ? -1 : 1
    if (a.known !== b.known) return a.known ? -1 : 1
    return b.signal - a.signal
  })
  return nets
}

function wifiSectionTitle(wifiNetworks, index, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var networks = Array.isArray(wifiNetworks) ? wifiNetworks : []
  if (index < 0 || index >= networks.length) return ""

  var net = networks[index]
  if (!net) return ""

  if (net.known && index === 0) return t("network.knownNetworks", "KNOWN NETWORKS")
  if (!net.known && (index === 0 || (networks[index - 1] && networks[index - 1].known))) return t("network.otherNetworks", "OTHER NETWORKS")
  return ""
}

// OWE (Enhanced Open) encrypts traffic without authenticating the user, so it
// has no credentials to collect. The panel's lock is a credentials-required
// affordance, so OWE should neither show it nor open its attached prompt.
function requiresCredentials(security, openSecurity, oweSecurity) {
  // Only explicit passwordless types bypass the prompt. Unknown security
  // stays credentialed as the conservative fallback.
  return security !== openSecurity && security !== oweSecurity
}

function canForgetNetwork(network) {
  return !!(network && network.known && !network.connected)
}

// The realm of an 802.1X identity ("alice@example.edu" gives "example.edu"),
// the domain the network's RADIUS server certificate is normally issued for.
// "" when the identity has none (a bare name or DOMAIN\user).
function identityRealm(identity) {
  var value = String(identity || "").trim()
  var at = value.lastIndexOf("@")
  if (at < 0) return ""
  var realm = value.substring(at + 1).toLowerCase()
  return /^[a-z0-9-]+(\.[a-z0-9-]+)+$/.test(realm) ? realm : ""
}

// The password arrives on stdin and reaches nmcli through the scriptable
// `connection edit` editor -- argv is world-readable in /proc, so the secret
// must never be an argument (printf is a bash builtin, so no process spawns
// with it either). $1 is the SSID, $2 the identity, $3 the domain the
// server's certificate must be issued for. With a domain the certificate must
// also chain to a CA the system trusts, so a fake access point with the same
// name can't collect the password. An empty $3 skips the check; the panel
// only passes one after the person chose that behind a warning. The profile
// is created with autoconnect off and gets it once it connected: otherwise
// NetworkManager starts it the moment it exists, before the password is in,
// and that attempt fails with "no secrets" while the real one is starting.
var enterpriseConnectScript =
  "u=$(uuidgen); IFS= read -r pw; verify=();" +
  " [ -n \"$3\" ] && verify=(802-1x.system-ca-certs yes 802-1x.domain-suffix-match \"$3\");" +
  " nmcli connection add type wifi con-name \"$1\" ssid \"$1\" connection.uuid \"$u\"" +
  " wifi-sec.key-mgmt wpa-eap 802-1x.eap peap 802-1x.phase2-auth mschapv2" +
  " 802-1x.identity \"$2\" \"${verify[@]}\" 802-1x.auth-timeout 8 connection.autoconnect no >/dev/null" +
  " && printf 'set 802-1x.password %s\\nsave\\nquit\\n' \"$pw\" | nmcli connection edit uuid \"$u\" >/dev/null" +
  " && nmcli connection up uuid \"$u\"" +
  " && { nmcli connection modify uuid \"$u\" connection.autoconnect yes; true; }" +
  " || { nmcli connection delete uuid \"$u\" >/dev/null 2>&1; false; }"

// What went wrong, as one of a few kinds the prompt can explain: "password"
// (refused or missing credentials), "lost", "disconnected", "failed"; the
// panel's own timeout adds "timeout".
function networkFailureKind(reason, needsCredentials, reasons) {
  var r = reasons || {}
  if (needsCredentials && (reason === r.NoSecrets || reason === r.WifiAuthTimeout)) return "password"
  if (reason === r.WifiNetworkLost) return "lost"
  if (reason === r.WifiClientDisconnected) return "disconnected"
  return "failed"
}

// What the open password prompt says after a connect from it failed, and how
// to recover. The person has just typed the password, so missing secrets mean
// it was refused, not that it is still to be entered. On work or school Wi-Fi
// a refused sign-in can also be a server certificate that doesn't match the
// domain.
function promptFailureMessage(kind, enterprise, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  if (kind === "password" && enterprise) return t("network.promptSignInFailed", "Couldn't sign in. Check the identity, domain and password.")
  if (kind === "password") return t("network.promptWrongPassword", "Wrong password. Check it and try again.")
  if (kind === "lost") return t("network.promptNetworkLost", "The network went out of range. Try again.")
  if (kind === "timeout") return t("network.promptTimedOut", "The network didn't answer in time. Try again.")
  return t("network.promptFailed", "Couldn't connect. Try again.")
}

function networkFailureReason(reason, needsCredentials, reasons, tr) {
  var t = typeof tr === "function" ? tr : function(key, english) { return english }
  var r = reasons || {}
  if (needsCredentials && reason === r.NoSecrets) return t("network.passphraseRequired", "Passphrase required")
  if (needsCredentials && reason === r.WifiAuthTimeout) return t("network.wrongPassword", "Wrong password")
  if (reason === r.WifiNetworkLost) return t("network.networkLost", "Network lost")
  if (reason === r.WifiClientDisconnected) return t("network.disconnected", "Disconnected")
  if (reason === r.WifiClientFailed) return t("network.connectionFailed", "Connection failed")
  return t("network.failedToConnect", "Failed to connect")
}

// Whether a failed connect should reopen the passphrase prompt. NoSecrets
// means credentials are missing only for a network that actually uses them.
// An auth timeout on such a network means the saved passphrase is wrong (the
// same profile a first failed attempt leaves behind as "known"), so the user
// needs a chance to re-enter it -- connectWithPsk overwrites the stored PSK on
// submit.
function shouldRepromptPassphrase(reason, needsCredentials, reasons) {
  var r = reasons || {}
  if (!needsCredentials) return false
  return reason === r.NoSecrets || reason === r.WifiAuthTimeout
}

if (typeof module !== "undefined") {
  module.exports = {
    parseNetworkStatus: parseNetworkStatus,
    speedTestConnection: speedTestConnection,
    wifiIconFor: wifiIconFor,
    connectionIcon: connectionIcon,
    parseVpnStatus: parseVpnStatus,
    vpnBlocksInternet: vpnBlocksInternet,
    vpnTone: vpnTone,
    vpnStatusLine: vpnStatusLine,
    vpnTooltip: vpnTooltip,
    applyRfkillEvent: applyRfkillEvent,
    radioState: radioState,
    heroState: heroState,
    attention: attention,
    parseDnsState: parseDnsState,
    dnsNotice: dnsNotice,
    connectedSignalStrength: connectedSignalStrength,
    parseActiveApSignal: parseActiveApSignal,
    connectivityState: connectivityState,
    captivePortalUrl: captivePortalUrl,
    formatHeaderSpeed: formatHeaderSpeed,
    formatHeaderFreq: formatHeaderFreq,
    headerDetail: headerDetail,
    bandLabel: bandLabel,
    bandSectionTitle: bandSectionTitle,
    bandTooltip: bandTooltip,
    parseBandStatus: parseBandStatus,
    decodeIwSsid: decodeIwSsid,
    parseKeyValue: parseKeyValue,
    pingLatencyState: pingLatencyState,
    pingPacketLossPercent: pingPacketLossPercent,
    internetPingReadable: internetPingReadable,
    formatPacketLoss: formatPacketLoss,
    formatPingLatency: formatPingLatency,
    wifiRow: wifiRow,
    wifiStateKey: wifiStateKey,
    sortWifiRows: sortWifiRows,
    wifiSectionTitle: wifiSectionTitle,
    requiresCredentials: requiresCredentials,
    canForgetNetwork: canForgetNetwork,
    identityRealm: identityRealm,
    enterpriseConnectScript: enterpriseConnectScript,
    networkFailureKind: networkFailureKind,
    promptFailureMessage: promptFailureMessage,
    networkFailureReason: networkFailureReason,
    shouldRepromptPassphrase: shouldRepromptPassphrase
  }
}
