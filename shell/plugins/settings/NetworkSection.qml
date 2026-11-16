import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Network (D-66, D-68): everything about the network, on one
// scroll. The network panel answers "am I online, am I protected?"; this page
// shows it all and changes it:
//   Status               a card per active connection
//   Saved networks       each opens in place: trusted, connect automatically,
//                        metered, band, private address, IP settings, share,
//                        forget; then "Join hidden network…"
//   DNS                  karchy's DNS on networks that aren't trusted
//   VPN                  the VPN package's mode and options, or plain VPN
//                        profiles; importing a WireGuard file
//   Sharing and firewall what is open right now (read-only)
//   Advanced             Wi-Fi country, connectivity check
// Opened from the panel's "Network settings…" (or `karchy-settings network
// <item>`) it starts at that network: its row opens and takes the keyboard.
// Every change goes through a karchy command; nothing here writes a file.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  // What the page was opened at (the summon payload).
  property var target: ({})
  property bool targetPending: false

  // karchy-network-status --json: the active connections in full.
  property var connections: []
  property bool vpnFull: false
  // karchy-network-profile list: saved Wi-Fi and Ethernet networks.
  property var profiles: []
  property bool profilesLoaded: false
  // The rows' keys, replaced only when the set of networks changes, so a
  // refresh doesn't rebuild the rows (and take the keyboard out of them).
  property var profileIds: []
  property var profileMap: ({})
  // karchy-trusted-networks status --json, by UUID.
  property var trust: ({})
  property int trustedCount: 0

  function refresh() {
    statusQuery.request()
    profileQuery.request()
    trustQuery.request()
    dnsPart.refresh()
    vpnPart.refresh()
    sharingPart.refresh()
    advancedPart.refresh()
  }

  // The connections changed: read what depends on them again.
  function refreshConnections() {
    statusQuery.request()
    profileQuery.request()
    trustQuery.request()
    dnsPart.refresh()
    vpnPart.refresh()
    sharingPart.refresh()
  }

  onTargetChanged: {
    targetPending = !!(target && (target.item || target.connection || target.device || target.anchor))
    if (profilesLoaded) Qt.callLater(applyTarget)
  }

  // The page grows as its parts load; for a moment after opening at an item,
  // keep that item on screen.
  property double revealUntil: 0
  onImplicitHeightChanged: if (Date.now() < revealUntil) Qt.callLater(revealFocus)
  function revealFocus() {
    if (settings && root.Window.activeFocusItem) settings.revealFocused(root.Window.activeFocusItem)
  }

  function applyTarget() {
    if (!targetPending) return
    targetPending = false
    revealUntil = Date.now() + 2000
    var t = target || {}
    var parts = { status: statusPart, saved: savedPart, dns: dnsPart, vpn: vpnPart, sharing: sharingPart, advanced: advancedPart }
    var anchor = t.anchor || (parts[t.item] ? t.item : "")
    if (anchor && parts[anchor]) { Qt.callLater(parts[anchor].focusFirst); return }
    var key = String(t.connection || t.item || "")
    var device = String(t.device || "")
    for (var i = 0; i < profiles.length; i++) {
      var p = profiles[i]
      if ((key !== "" && (p.uuid === key || p.name === key || p.ssid === key || p.device === key))
          || (key === "" && device !== "" && p.device === device)) {
        savedPart.openAt(p.uuid)
        return
      }
    }
    // Nothing by that name: the keyboard starts on the section list as usual.
    if (settings) settings.focusSection(settings.currentSectionIndex())
  }

  function loadStatus(text) {
    try {
      var value = JSON.parse(text)
      root.connections = value.connections || []
      root.vpnFull = value.vpn_full === true
    } catch (e) {}
  }

  function loadProfiles(text) {
    var list
    try { list = JSON.parse(text).networks || [] } catch (e) { return }
    var map = {}
    for (var i = 0; i < list.length; i++) map[list[i].uuid] = list[i]
    var ids = list.map(function(p) { return p.uuid })
    root.profiles = list
    root.profileMap = map
    if (ids.join(" ") !== root.profileIds.join(" ")) root.profileIds = ids
    root.profilesLoaded = true
    if (root.targetPending) Qt.callLater(root.applyTarget)
  }

  function loadTrust(text) {
    try {
      var value = JSON.parse(text)
      var byUuid = {}
      var count = 0
      var networks = value.networks || []
      for (var i = 0; i < networks.length; i++) {
        byUuid[networks[i].uuid] = networks[i]
        if (networks[i].saved_trust) count++
      }
      root.trust = byUuid
      root.trustedCount = count
    } catch (e) {}
  }

  Component.onCompleted: refresh()

  // A read that can be asked for again while it runs; it runs once more
  // after, so the newest state always lands.
  component Query: Process {
    id: query
    property bool again: false
    signal result(string text)
    function request() {
      if (running) again = true
      else running = true
    }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: query.result(text) }
    onExited: if (again) { again = false; running = true }
  }

  Query { id: statusQuery; command: ["karchy-network-status", "--json"]; onResult: function(text) { root.loadStatus(text) } }
  Query { id: profileQuery; command: ["karchy-network-profile", "list"]; onResult: function(text) { root.loadProfiles(text) } }
  Query { id: trustQuery; command: ["karchy-trusted-networks", "status", "--json"]; onResult: function(text) { root.loadTrust(text) } }

  // NetworkManager says when anything changes; nothing polls. A burst of
  // events (a connection coming up) is read once, a moment after.
  Process {
    running: root.visible
    command: ["nmcli", "monitor"]
    stdout: SplitParser { onRead: function(line) { changes.restart() } }
  }
  Timer { id: changes; interval: 700; onTriggered: root.refreshConnections() }

  PageHeader {
    title: "Network"
    explanation: "On a trusted network, such as home, LocalSend can receive files from nearby devices and the network's own DNS is used, so names like nas.lan work. On every other network LocalSend's port stays closed and DNS goes to karchy's DNS servers, encrypted. Trust follows the network's router: the same network name or cable somewhere else isn't trusted."
  }

  NetworkStatus { id: statusPart; page: root }
  NetworkSaved { id: savedPart; page: root }
  NetworkDns { id: dnsPart; page: root }
  NetworkVpn { id: vpnPart; page: root }
  NetworkSharing { id: sharingPart; page: root }
  NetworkAdvanced { id: advancedPart; page: root }
}
