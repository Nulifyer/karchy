// The network panel's model: the internet through a VPN, and a WireGuard
// tunnel's health. Usage: node tests/network-model.js "$PWD"
const assert = require("assert")
const M = require(process.argv[2] + "/shell/plugins/panels/network/Model.js")
const eq = (a, b) => assert.deepStrictEqual(a, b)
const vpn = state => M.parseVpnStatus(JSON.stringify({ mode: "auto", state, reason: "", network: { trusted: false } }))
const none = M.parseVpnStatus("")

// NetworkManager's check can't leave past the kill switch: Limited while the
// VPN protects is the internet through the VPN, not an outage.
eq(M.internetState("limited", vpn("protecting"), true), "vpn")
eq(M.internetState("none", vpn("protecting"), true), "vpn")
eq(M.internetState("full", vpn("protecting"), true), "vpn")
// A sign-in page still comes first; a VPN that isn't up proves nothing.
eq(M.internetState("portal", vpn("protecting"), true), "portal")
eq(M.internetState("limited", vpn("connecting"), false), "limited")
eq(M.internetState("limited", vpn("failed"), false), "limited")
eq(M.internetState("full", vpn("standing-by"), false), "full")
// Without the package: a full-tunnel VPN counts once NetworkManager agrees.
eq(M.internetState("full", none, true), "vpn")
eq(M.internetState("limited", none, true), "limited")
eq(M.internetState("full", none, false), "full")
eq(M.internetState("unknown", none, false), "unknown")

// The hero and the Wi-Fi icon tell the two apart.
const hero = (connectivity, v) => M.heroState({ nm: true, networking: true, adapter: true, kind: "wifi",
  name: "Home", connectivity, vpn: v }).status
eq(hero(M.internetState("limited", vpn("protecting"), true), vpn("protecting")), "VPN protecting")
eq(hero(M.internetState("full", none, true), none), "Connected through VPN")
eq(hero(M.internetState("full", none, false), none), "Connected")
eq(hero(M.internetState("limited", none, false), none), "No internet")
eq(M.connectionIcon("wifi", 80, "vpn", "", false), M.wifiIconFor(80) + ".vpn")
eq(M.connectionIcon("wifi", 80, "full", "", false), M.wifiIconFor(80))
eq(M.connectionIcon("ethernet", 0, "vpn", "protecting", false), "net.ethernet.vpn")
eq(M.connectionIcon("wifi", 80, "limited", "", false), "net.wifi.restricted")

// The status file names the tunnel, so the panel can read its health.
eq(M.parseVpnStatus('{"mode":"on","state":"protecting","tunnel":{"name":"Home VPN","interface":"wg0"}}').tunnel,
  { name: "Home VPN", interface: "wg0" })
eq(M.parseVpnStatus('{"mode":"on","state":"protecting","tunnel":{"name":"x"}}').tunnel, null)
eq(none.tunnel, null)

// A WireGuard tunnel's health, from wireguard-status.
const status = { now: 1000, interfaces: [
  { interface: "wg0", peers: [{ latest_handshake: 960, allowed_ips: ["0.0.0.0/0"], keepalive: 0, rx_bytes: 1234567, tx_bytes: 999 }] },
  { interface: "wg1", peers: [] }] }
const peer = M.wireguardPeer(status, "wg0")
eq(peer.rx_bytes, 1234567)
eq(M.wireguardPeer(status, "wg1"), null)
eq(M.wireguardPeer(status, "nope"), null)
eq(M.wireguardPeer(null, "wg0"), null)
eq(M.wireguardHealth(peer, 1000), { state: "healthy", age: 40, tone: "" })
eq(M.wireguardHealth(peer, 1140), { state: "healthy", age: 180, tone: "" })
eq(M.wireguardHealth(peer, 1200), { state: "stale", age: 240, tone: "error" })
const split = { latest_handshake: 100, allowed_ips: ["10.0.0.0/8"], keepalive: 0 }
eq(M.wireguardHealth(split, 1000).state, "idle")
eq(M.wireguardHealth(Object.assign({}, split, { keepalive: 25 }), 1000).state, "stale")
eq(M.wireguardHealth({ latest_handshake: 0, allowed_ips: ["0.0.0.0/0"] }, 1000), { state: "no-handshake", age: -1, tone: "error" })
eq(M.wireguardHealth(null, 1000).state, "unknown")
eq(M.peerCarriesAll({ allowed_ips: ["10.0.0.0/8", "::/0"] }), true)
eq(M.wireguardHealthText(M.wireguardHealth(peer, 1000)), "Working, last handshake 40 s ago")
eq(M.wireguardHealthText(M.wireguardHealth(peer, 1200)), "The server stopped answering, last handshake 4 min ago")
eq(M.wireguardHealthText({ state: "unknown" }), "")
eq(M.formatAge(2), "just now"); eq(M.formatAge(59), "59 s ago"); eq(M.formatAge(3599), "59 min ago")
eq(M.formatAge(7200), "2 h ago"); eq(M.formatAge(200000), "2 days ago")
eq(M.formatBytes(0), "0 B"); eq(M.formatBytes(999), "999 B"); eq(M.formatBytes(1234567), "1.23 MB")
eq(M.formatBytes(1e9), "1 GB"); eq(M.formatBytes(-1), ""); eq(M.formatBytes("x"), "")
// The VPN's line says why it isn't up, where the VPN could tell.
const why = (state, reason) => M.vpnStatusLine(M.parseVpnStatus(JSON.stringify({ mode: "on", state, reason, network: { trusted: true } })))
eq(why("connecting", "keys-rejected"), "The server answers, but the keys don't match. Check the profile's preshared key. The internet is blocked.")
eq(why("failed", "keys-rejected"), why("connecting", "keys-rejected"), "the same words while connecting and once failed")
eq(why("failed", "probe-unanswered"), "Connected to the server, but its DNS server doesn't answer through the VPN. The internet is blocked.")
eq(why("connecting", "no-handshake"), "Connecting. The internet is blocked until it's up.")
eq(why("failed", "no-handshake"), "Can't connect. The internet is blocked.")
eq(why("connecting", "starting"), "Connecting. The internet is blocked until it's up.")
console.log("network model ok")
