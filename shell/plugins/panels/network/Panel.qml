import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "karchy.network"
  ipcTarget: "karchy.network"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleNetwork method below.
  manageIpc: false

  // Centralized close so callers can't forget to drop the passphrase prompt.
  function close() {
    root.controller.hide()
    cancelPasswordPrompt()
  }

  function cancelPasswordPrompt() {
    passwordSsid = ""
    passwordText = ""
    resetEnterpriseFields()
  }

  function resetEnterpriseFields() {
    identityText = ""
    domainText = ""
    domainEdited = false
    skipServerCheck = false
  }

  // Live connection details from `ip` / /sys / iw.
  // The real Wi-Fi or Ethernet link, never a VPN tunnel; vpn_* describe the
  // VPN while one is up (vpn_full: the internet goes through it).
  property var info: ({})  // { iface, type, ip, prefix, gateway, speed, duplex, ssid, signal, freq, bitrate, vpn_name, vpn_iface, vpn_ip, vpn_full, router_ping_ms, internet_ping_ms }
  property string pingIface: ""
  property var routerPingSamples: []
  property var internetPingSamples: []
  property real routerPingLatency: -1
  property real internetPingLatency: -1
  property int internetPingPacketLoss: 0
  readonly property int pingHistoryWindow: 24
  readonly property int pingAverageWindow: 5
  readonly property bool hasInternetPing: Model.internetPingReadable(internetPingSamples, connectivity)
  readonly property bool networkManagerAvailable: Networking.backend === NetworkBackendType.NetworkManager
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []
  readonly property var wifiDevice: findDevice(DeviceType.Wifi)
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  // Bound here rather than in a row, so it also sees networks with no delegate:
  // scrolled out of view, or the panel closed.
  readonly property string wifiStateKey: Model.wifiStateKey(wifiNetworkObjects)
  readonly property var connectedWifiNetwork: findConnectedWifiNetwork()
  property var wifiNetworks: []
  property bool scanning: false
  property bool wifiStationAvailable: false
  // Wi-Fi band state from `karchy-network-band`. `bandCurrent` is the band
  // the radio is actually on; `bandSelected` is the pinned choice ("auto" when
  // nothing is pinned), and the two differ whenever Auto is in effect.
  property string bandCurrent: ""
  property string bandSelected: "auto"
  property var bandAvailable: []
  property string pendingBand: ""

  // Per-row in-flight state. `actionSsid` flips on for the row whose action
  // is currently running so it can render "Connecting…" / "Disconnecting…" /
  // "Forgetting…". `passwordSsid` is the row currently expanded into
  // password-entry mode; we keep it open across refresh cycles so a slow scan
  // doesn't collapse the input the user is typing into. Rows must gate
  // comparisons on the matching `*Kind`/`*Reason` being non-empty so a
  // hidden-SSID row (ssid == "") doesn't collide with the "" defaults.
  property string actionSsid: ""
  property string actionKind: ""  // "connect" | "disconnect" | "forget"
  property string failureSsid: ""
  property string failureReason: ""
  // Model.networkFailureKind of the last failure, so the open password prompt
  // can say what went wrong and how to recover; it stays until a field is
  // edited or the next connect starts.
  property string failureKind: ""
  // The actionKind that failed, so a failed connect's reason can be dropped
  // once NetworkManager connects that network on its own.
  property string failedAction: ""
  property string passwordSsid: ""
  property string passwordText: ""
  property string identityText: ""
  // Work or school Wi-Fi (802.1X) checks the server's certificate against this
  // domain. It follows the identity's realm until the person edits it.
  property string domainText: ""
  property bool domainEdited: false
  // Set only by the explicit "Connect without checking the server" choice.
  property bool skipServerCheck: false

  // ConnectionFailReason values as a plain object, so Model.js helpers stay
  // pure JS and Node-testable.
  readonly property var connectionFailReasons: ({
    NoSecrets: ConnectionFailReason.NoSecrets,
    WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
    WifiNetworkLost: ConnectionFailReason.WifiNetworkLost,
    WifiClientDisconnected: ConnectionFailReason.WifiClientDisconnected,
    WifiClientFailed: ConnectionFailReason.WifiClientFailed
  })

  // True while any wifi action is mid-flight. Rows
  // disable themselves on this so clicks on the other rows don't silently
  // no-op against runNetworkAction's serialized guard.
  readonly property bool busy: actionKind !== ""

  // Index into `wifiNetworks` for keyboard navigation. -1 = no selection.
  property int selectedIndex: -1
  // The network under the cursor when the rows were last rebuilt, so the
  // cursor follows it when a state change re-sorts the list.
  // null rather than "", which is a hidden network's SSID.
  property var cursorSsid: null
  property bool wifiActionFocused: false
  property bool cursorActive: false

  // Keyboard focus zone for the panel. j/k crosses row boundaries, top to
  // bottom: header actions, the attention row, the VPN, the band, the Wi-Fi
  // networks, the "Network settings…" footer. h/l move within a row.
  property string focusSection: "header"  // "header" | "attention" | "vpn" | "band" | "wifi" | "footer"
  property int headerIndex: 0
  readonly property bool canDisconnect: !!connectedWifiNetwork
  readonly property bool headerHasDisconnect: false
  readonly property bool canShareWifi: info.type === "wifi" && canShareNetwork(connectedWifiNetwork)
  // The hero switch is the Wi-Fi radio, so it only exists when there is a
  // radio to switch. On a wired box it would otherwise sit there reading
  // "off" beside a perfectly live Ethernet connection.
  // A hardware switch or airplane key has blocked the radio (rfkill hard
  // block). The software switch can't turn it back on, so it isn't offered.
  readonly property bool wifiHardwareBlocked: networkManagerAvailable && !Networking.wifiHardwareEnabled
  readonly property bool canToggleWifi: networkManagerAvailable && networkingEnabled && wifiStationAvailable
    && !wifiHardwareBlocked && !airplane
  readonly property int qrHeaderIndex: canShareWifi ? 0 : -1
  readonly property int speedHeaderIndex: canRunSpeedTest ? (canShareWifi ? 1 : 0) : -1
  readonly property int toggleHeaderIndex: canToggleWifi ? (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) : -1
  readonly property int headerActionCount: (canShareWifi ? 1 : 0) + (canRunSpeedTest ? 1 : 0) + (canToggleWifi ? 1 : 0)
  readonly property bool qrHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === qrHeaderIndex
  readonly property bool speedHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === speedHeaderIndex
  readonly property bool toggleHeaderHasCursor: cursorActive && focusSection === "header" && headerIndex === toggleHeaderIndex
  readonly property string toggleHint: Networking.wifiEnabled ? Commons.I18n.t("network.turnWifiOff") : Commons.I18n.t("network.turnWifiOn")
  // ["2.4", "5", ...], or empty when there is nothing to choose between.
  // Wi-Fi only: on Ethernet the band of a secondary radio is not what the
  // panel is describing.
  // `bandBusy` keeps the section mounted across the reconnect a band change
  // causes: `kind` stops being "wifi" for a second or two in the middle of it,
  // and without this the whole segment would vanish and rebuild itself.
  // Worth showing when there is a real choice, or when a pin is in force even
  // though only one band answers right now -- otherwise the Automatic switch
  // vanishes and the pin becomes unclearable from the panel.
  readonly property bool canSelectBand: (kind === "wifi" || bandBusy)
    && (bandAvailable.length > 1 || bandPinned)
  // While a change is in flight, show the state that was asked for rather than
  // the one still in force, so the row answers the click immediately instead of
  // after the reconnect. actionProc puts it back if the change failed.
  readonly property string bandEffective: pendingBand !== "" ? pendingBand : bandSelected
  readonly property bool bandPinned: bandEffective !== "auto"
  // Under Automatic there is nothing to pick, so the pills collapse away and
  // the header states the live band instead.
  readonly property bool bandPillsVisible: canSelectBand && bandPinned
  readonly property string bandSectionTitle: Model.bandSectionTitle(bandEffective, bandCurrent, Commons.I18n.t, Commons.I18n.formatNumber)
  readonly property bool bandBusy: pendingBand !== ""
  // The speed test needs an interface to test, so its hero action only
  // appears once there is one.
  readonly property bool canRunSpeedTest: !!info.iface
  property int bandIndex: 0
  // The band section has up to two cursor rows: the Automatic switch on the
  // header line, then the pills. Same shape as wifiActionFocused.
  property bool bandAutoFocused: true

  onHeaderActionCountChanged: clampHeaderIndex()

  // Availability shifts as scans land, so the option list can shrink out from
  // under the cursor. Clamp the index and evacuate the section before it
  // disappears, or the panel is left highlighting nothing.
  onBandAvailableChanged: {
    if (bandIndex > bandAvailable.length - 1) bandIndex = Math.max(0, bandAvailable.length - 1)
  }

  onCanSelectBandChanged: {
    if (!canSelectBand && focusSection === "band") {
      focusSection = wifiNetworks.length > 0 ? "wifi" : sectionAboveWifi()
      bandAutoFocused = true
    }
  }

  // Collapsing the pills out from under the cursor would leave it pointing at
  // nothing, so send it up to the switch that is still on screen.
  onBandPillsVisibleChanged: {
    if (!bandPillsVisible) bandAutoFocused = true
  }

  function clampHeaderIndex() {
    var max = Math.max(0, headerActionCount - 1)
    if (headerIndex > max) headerIndex = max
    if (headerIndex < 0) headerIndex = 0
  }

  function selectHeaderByDelta(delta) {
    headerIndex = Math.max(0, Math.min(headerActionCount - 1, headerIndex + delta))
  }

  function toggleNetwork() {
    if (!networkManagerAvailable) return
    Networking.wifiEnabled = !Networking.wifiEnabled
    Qt.callLater(function() { root.refresh(true) })
  }

  ShellIpc {
    target: "karchy.network"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function toggleNetwork() { root.toggleNetwork() }
    // Compat routes for configs that summon the centered cards through the
    // network target; both cards are their own plugins now.
    function showQr() { root.summonWifiQr(true) }
    function speedTest() { root.summonSpeedTest() }
    function openCaptivePortal() { root.openCaptivePortal() }
    function checkConnectivity() { root.checkConnectivity() }
    // karchy-airplane changed its remembered choice.
    function radiosChanged() { airplaneFile.reload() }
  }

  function activateHeader() {
    if (headerIndex === qrHeaderIndex) summonWifiQr()
    else if (headerIndex === speedHeaderIndex) summonSpeedTest()
    else if (headerIndex === toggleHeaderIndex) toggleNetwork()
  }

  function setHeaderCursor(index) {
    cursorActive = true
    focusSection = "header"
    headerIndex = index
  }

  // The keyboard's sections, top to bottom, as they are on screen now.
  function sections() {
    var list = []
    if (headerActionCount > 0) list.push("header")
    if (attentionActionCount > 0) list.push("attention")
    if (vpnVisible) list.push("vpn")
    if (canSelectBand) list.push("band")
    if (wifiListVisible && wifiNetworks.length > 0) list.push("wifi")
    list.push("footer")
    return list
  }

  // j / k past the edge of a section: the next one up or down, entered at
  // the row nearest to where the cursor came from.
  function moveSection(dy) {
    var list = sections()
    var index = list.indexOf(focusSection)
    var next = list[index < 0 ? 0 : index + (dy > 0 ? 1 : -1)]
    if (!next) return
    focusSection = next
    if (next === "header") headerIndex = 0
    else if (next === "band") bandAutoFocused = dy > 0 || !bandPillsVisible
    else if (next === "vpn") vpnIndex = Math.max(0, vpnModes.indexOf(vpn.mode))
    else if (next === "attention") attentionIndex = 0
    else if (next === "wifi") {
      if (selectedIndex < 0 || dy < 0) selectedIndex = dy < 0 ? wifiNetworks.length - 1 : 0
    }
    if (focusSection !== "wifi") wifiActionFocused = false
  }

  // The row just above the Wi-Fi list: where the cursor goes when the
  // section it was on disappears.
  function sectionAboveWifi() {
    var list = sections().filter(function(section) { return section !== "wifi" && section !== "footer" })
    return list.length > 0 ? list[list.length - 1] : "footer"
  }

  // Where the cursor starts when the panel opens: the row that needs the
  // person, else the network list, else the first row there is.
  function openingSection() {
    if (attentionActionCount > 0) return "attention"
    if (wifiListVisible && wifiNetworks.length > 0) return "wifi"
    return sections()[0]
  }

  function selectBandByDelta(delta) {
    bandIndex = Math.max(0, Math.min(bandAvailable.length - 1, bandIndex + delta))
  }

  function activateBand() {
    if (bandAutoFocused) {
      toggleBandAuto()
      return
    }
    if (bandIndex < 0 || bandIndex >= bandAvailable.length) return
    setBand(bandAvailable[bandIndex])
  }

  // Switching Automatic off has to commit to something, so it pins whatever
  // band the radio already landed on -- the reading the pills are showing.
  function toggleBandAuto() {
    if (bandSelected !== "auto") {
      setBand("auto")
      return
    }
    if (bandCurrent === "") return
    setBand(bandCurrent)
  }

  // Park the cursor on the pinned band, so opening the panel highlights the
  // pill the user would expect. Under Automatic there are no pills, so the
  // cursor belongs on the switch.
  function syncBandIndex() {
    var idx = bandAvailable.indexOf(bandSelected)
    bandIndex = idx >= 0 ? idx : 0
    bandAutoFocused = !bandPillsVisible
  }

  function bandLabel(band) {
    return Model.bandLabel(band, Commons.I18n.t, Commons.I18n.formatNumber)
  }

  function bandTooltip(band) {
    return Model.bandTooltip(band, Commons.I18n.t, Commons.I18n.formatNumber)
  }

  // Single cursor model: exactly one highlighted spot across the whole
  // panel, located via `focusSection` + (`headerIndex` | `bandIndex` |
  // `selectedIndex`). Mouse hover and keyboard nav both mutate this state
  // at the root; items never read containsMouse for visuals. See
  // CursorSurface for the shared chrome shared by rows and pills.
  readonly property color hoverFill: Style.hoverFillFor(panelText, Commons.Color.accent)
  readonly property color selectedFill: Style.selectedFillFor(panelText, Commons.Color.accent)

  // scannerEnabled lives on the shared WifiDevice, which has no reference
  // counting, and a bar widget is instantiated once per monitor. Tracking the
  // device this instance turned scanning on for keeps the release correct when
  // the panel closes, the device is replaced, or the widget is destroyed —
  // without a closed instance ever claiming the scanner.
  property var scannerDevice: null

  function setScannerEnabled(enabled) {
    var nextDevice = opened ? wifiDevice : null

    if (scannerDevice && scannerDevice !== nextDevice)
      scannerDevice.scannerEnabled = false

    scannerDevice = nextDevice

    if (scannerDevice)
      scannerDevice.scannerEnabled = enabled
  }

  Component.onDestruction: {
    if (scannerDevice) scannerDevice.scannerEnabled = false
  }

  // KeyboardPanel primes layer-shell focus whenever the panel opens. That's
  // what makes the SUPER+CTRL+W keybind land here with navigation ready.
  onOpenedChanged: {
    if (opened) {
      refresh(true)
      selectedIndex = wifiNetworks.length > 0 ? 0 : -1
      wifiActionFocused = false
      focusSection = openingSection()
      attentionIndex = 0
      vpnIndex = Math.max(0, vpnModes.indexOf(vpn.mode))
      syncBandIndex()
      cursorActive = attentionActionCount > 0
    } else {
      // Drop a restart armed by this open: without it a close/reopen inside
      // the 100ms window reuses the running timer and re-enables the scanner
      // almost immediately, undoing the deferral #6605 restored.
      scanRestart.stop()
      pingIface = ""
      routerPingSamples = []
      internetPingSamples = []
      routerPingLatency = -1
      internetPingLatency = -1
      internetPingPacketLoss = 0
      setScannerEnabled(false)
    }
  }

  // When the passphrase prompt closes (Esc / Cancel / success) restore
  // focus to the keyCatcher so j/k/Enter resume working without a click.
  // The KeyboardPanel's focusTarget covers initial popup-open; this handles
  // the inline-editor case where focus was handed off to a child.
  onPasswordSsidChanged: {
    if (passwordSsid === "" && opened) {
      passwordText = ""
      Qt.callLater(function() { if (panel.loadedContent) panel.loadedContent.forceActiveFocus() })
    }
  }

  // Keep selectedIndex valid as scans refresh the network list.
  // If the list empties (station gone, e.g. wifi off), bounce the cursor
  // to the row above so the panel doesn't end up with no cursor at all.
  onWifiNetworksChanged: {
    if (wifiNetworks.length === 0) {
      selectedIndex = -1
      wifiActionFocused = false
      if (focusSection === "wifi") focusSection = sectionAboveWifi()
    } else if (passwordSsid !== "") {
      var passwordIndex = wifiIndexForSsid(passwordSsid)
      if (passwordIndex >= 0) {
        selectedIndex = passwordIndex
        focusSection = "wifi"
      }
    } else if (cursorSsid !== null && wifiIndexForSsid(cursorSsid) >= 0) {
      selectedIndex = wifiIndexForSsid(cursorSsid)
    } else if (selectedIndex >= wifiNetworks.length) {
      selectedIndex = wifiNetworks.length - 1
    } else if (selectedIndex < 0 && opened) {
      selectedIndex = 0
    }

    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length || !canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
    }
  }

  onWifiDeviceChanged: {
    setScannerEnabled(true)
    syncWifiNetworks()
    resetActiveApSignal()
  }

  onWifiNetworkObjectsChanged: syncWifiNetworks()
  onWifiStateKeyChanged: Qt.callLater(rebuildWifiRows)

  function selectByDelta(delta) {
    if (wifiNetworks.length === 0) { selectedIndex = -1; return }
    if (selectedIndex < 0) selectedIndex = delta > 0 ? 0 : wifiNetworks.length - 1
    else selectedIndex = Math.max(0, Math.min(wifiNetworks.length - 1, selectedIndex + delta))
    wifiActionFocused = false
  }

  function canForgetNetwork(net) {
    return Model.canForgetNetwork(net)
  }

  function canShareNetwork(net) {
    if (!net || !net.connected) return false
    return net.security !== WifiSecurityType.Wpa2Eap && net.security !== WifiSecurityType.WpaEap
  }

  function selectWifiActionByDelta(delta) {
    if (selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    if (!canForgetNetwork(wifiNetworks[selectedIndex])) {
      wifiActionFocused = false
      return
    }
    if (delta > 0) wifiActionFocused = true
    else if (delta < 0) wifiActionFocused = false
  }

  // Enter/Space on the highlighted row. Mirrors row-click semantics:
  // connected → disconnect, credentials-required/unknown → prompt,
  // passwordless/known → connect.
  function activateSelected() {
    if (busy || selectedIndex < 0 || selectedIndex >= wifiNetworks.length) return
    var net = wifiNetworks[selectedIndex]
    if (!net) return
    if (wifiActionFocused && canForgetNetwork(net)) { forget(net); return }
    // Only act on a row that still resolves. disconnect() falls back to
    // connectedWifiNetwork when handed null, so a row left stale by scan churn
    // would otherwise tear down whatever is connected now instead.
    if (net.connected) { disconnectRow(net.ssid); return }
    if (requiresCredentials(net.security) && !net.known) { openPasswordPrompt(net.ssid); return }
    connectDirectly(net.ssid)
  }

  // Bar pill state, derived from the native NetworkManager service so the
  // icon reflects connection changes without polling. Wired is preferred
  // when both are up, matching the default-route device.
  readonly property var wiredDevice: findDevice(DeviceType.Wired)
  readonly property string kind: {
    if (wiredDevice && wiredDevice.connected) return "ethernet"
    if (connectedWifiNetwork) return "wifi"
    // NetworkManager can leave the active profile out of the device's
    // AvailableConnections, and Quickshell only builds known networks from
    // that list. An OWE transition-mode network does this between scans: the
    // in-use access point carries the hidden "_owetm_" SSID, so the profile
    // for the open SSID looks out of range even while it is connected. Trust
    // the device's own state then instead of flickering to disconnected.
    if (wifiDevice && wifiDevice.connected) return "wifi"
    return "disconnected"
  }
  readonly property int signalStrength: kind === "wifi"
    ? Model.connectedSignalStrength(connectedWifiNetwork ? connectedWifiNetwork.signalStrength : 0, activeApSignal)
    : -1
  // Filled by activeApSignalPoll from nmcli while the connected network has no
  // strength of its own to report.
  property int activeApSignal: -1
  readonly property bool needsActiveApSignal: kind === "wifi"
    && !(connectedWifiNetwork && connectedWifiNetwork.signalStrength > 0)
  // Bumped whenever the cached reading stops describing the current link, so
  // an nmcli read still in flight from before cannot write a stale strength.
  property int activeApSignalGeneration: 0
  property int activeApSignalRequest: -1
  onKindChanged: if (kind !== "wifi") resetActiveApSignal()

  // Switching Wi-Fi networks always passes through a non-"wifi" kind (both the
  // device and the old network drop out of the connected state while the new
  // profile activates), so this also covers a change of network.
  function resetActiveApSignal() {
    activeApSignal = -1
    activeApSignalGeneration++
  }

  function pollActiveApSignal() {
    if (activeApSignalProc.running) return
    activeApSignalRequest = activeApSignalGeneration
    activeApSignalProc.running = true
  }

  function finishActiveApSignal(raw) {
    if (activeApSignalRequest !== activeApSignalGeneration) {
      // The link changed mid-read and the restarted poll skipped while this
      // one was running; read again now instead of a full interval later.
      if (needsActiveApSignal) activeApSignalPoll.restart()
      return
    }
    activeApSignal = Model.parseActiveApSignal(raw)
  }

  function copyToClipboard(value) {
    if (!value || !root.bar) return
    Quickshell.execDetached(["bash", "-c", "printf %s " + Util.shellQuote(value) + " | wl-copy"])
  }

  // NetworkManager performs the HTTP probe (including unexpected page bodies,
  // not just redirects). Consume its native notifications rather than running
  // a second curl loop or mistaking an ordinary timeout for a captive portal.
  readonly property bool connectivityChecksEnabled: networkManagerAvailable
    && Networking.canCheckConnectivity && Networking.connectivityCheckEnabled
  readonly property string connectivity: Model.connectivityState(kind, Networking.connectivity, {
    Portal: NetworkConnectivity.Portal, Limited: NetworkConnectivity.Limited,
    Full: NetworkConnectivity.Full, None: NetworkConnectivity.None
  }, connectivityChecksEnabled, limitedSettled)
  // A network switch passes through Limited for a fraction of a second while
  // NetworkManager's first probe is in flight. Wait that out rather than flash
  // the outage warning on every connect.
  readonly property bool nativeLimited: Networking.connectivity === NetworkConnectivity.Limited
  property bool limitedSettled: false
  onNativeLimitedChanged: if (!nativeLimited) limitedSettled = false
  Timer {
    id: limitedSettle
    interval: 3000
    running: root.nativeLimited
    onTriggered: root.limitedSettled = true
  }
  readonly property bool hasCaptivePortal: connectivity === "portal"
  readonly property bool restricted: hasCaptivePortal || connectivity === "limited"
  readonly property string icon: Icons.glyph(networkManagerAvailable && !hasAdapter ? "net.network"
    : Model.connectionIcon(kind, signalStrength, connectivity, vpn.state, airplane))

  // ---- Radios: airplane mode (karchy-airplane, rfkill) ----
  // `rfkill event` lists every radio when it starts and then reports each
  // change, so this follows airplane mode, a hardware switch and the airplane
  // key without polling. /dev/rfkill is readable by everyone.
  property var radios: ({})
  readonly property var radioState: Model.radioState(radios)
  // karchy-airplane remembers turning it on ("on"/"off"); see Model.radioState.
  property bool airplaneChosen: false
  readonly property bool airplane: airplaneChosen && radioState.allBlocked

  FileView {
    id: airplaneFile
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/karchy/airplane"
    watchChanges: true
    printErrors: false
    onLoaded: root.airplaneChosen = text().trim() === "on"
    onLoadFailed: root.airplaneChosen = false
    onFileChanged: reload()
  }

  // Every radio turned back on some other way (rfkill, the Bluetooth and
  // Wi-Fi switches) ends the remembered choice. Not at once: turning airplane
  // mode on records it a moment before the radios go off.
  Timer {
    interval: 2000
    running: root.airplaneChosen && root.radioState.radios > 0 && !root.radioState.anyBlocked
    onTriggered: Quickshell.execDetached(["karchy-airplane", "forget"])
  }

  Process {
    id: rfkillWatch
    running: true
    command: ["rfkill", "event"]
    stdout: SplitParser { onRead: function(line) { root.radios = Model.applyRfkillEvent(root.radios, line); airplaneFile.reload() } }
    // Gone (rfkill missing, or the module unloaded): forget the radios rather
    // than show a stale airplane mode.
    onExited: root.radios = ({})
  }

  function setAirplane(on) {
    Quickshell.execDetached(["karchy-airplane", on ? "on" : "off"])
  }

  // ---- NetworkManager's own switch (`nmcli networking off`) ----
  // Read when the panel opens and after the devices change; there is no
  // property for it in Quickshell.Networking.
  property bool networkingEnabled: true
  Process {
    id: networkingProc
    command: ["nmcli", "-t", "networking"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.networkingEnabled = text.trim() !== "disabled"
    }
  }
  onNetworkDevicesChanged: if (!networkingProc.running) networkingProc.running = true

  function restartNetworking() {
    Quickshell.execDetached(["karchy-restart-wifi"])
  }

  // ---- What the hero and the attention row say (Model.heroState) ----
  readonly property bool hasAdapter: !!wifiDevice || !!wiredDevice
  readonly property string connectingTo: {
    if (actionKind === "connect" && actionSsid !== "") return actionSsid
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].stateChanging && !networks[i].connected && networks[i].known) return networks[i].name || ""
    return ""
  }
  readonly property var panelState: ({
    nm: networkManagerAvailable,
    networking: networkingEnabled,
    adapter: hasAdapter,
    airplane: airplane,
    hardwareBlocked: wifiHardwareBlocked,
    wifiRadio: !!wifiDevice,
    wifiEnabled: networkManagerAvailable && Networking.wifiEnabled,
    kind: kind,
    name: connectedTitle,
    connectingTo: connectingTo,
    connectivity: connectivity,
    vpn: vpn,
    dns: dnsNotice
  })
  readonly property var heroModel: Model.heroState(panelState, Commons.I18n.t)
  readonly property var attentionModel: Model.attention(panelState, Commons.I18n.t)
  readonly property int attentionActionCount: attentionModel ? attentionModel.actions.length : 0
  property int attentionIndex: 0
  readonly property color heroToneColor: heroModel.tone === "error" ? Commons.Color.status.error
    : heroModel.tone === "warning" ? Commons.Color.status.warning : Commons.Color.secondaryText(panelText, panelSurface)
  // The Wi-Fi list is for joining networks; with the radio off, blocked or in
  // airplane mode there is nothing in it to join.
  readonly property bool wifiListVisible: wifiStationAvailable && networkingEnabled && !airplane
    && !wifiHardwareBlocked && networkManagerAvailable && Networking.wifiEnabled
  // The connected network's title: the SSID, or "Ethernet (1gbit)".
  readonly property string connectedTitle: {
    var title = ""
    if (kind === "wifi" && connectedWifiNetwork) title = connectedWifiNetwork.name || "Wi-Fi"
    else if (kind === "wifi") title = info.ssid || "Wi-Fi"
    else if (kind === "ethernet") title = Commons.I18n.t("network.ethernet")
    var detail = kind === "ethernet" ? headerDetail() : ""
    return detail !== "" ? title + " (" + detail + ")" : title
  }

  onAttentionModelChanged: {
    var id = attentionModel ? attentionModel.id : ""
    if (id === lastAttention) return
    lastAttention = id
    attentionIndex = 0
    // A new request takes the cursor, unless the person is typing a password.
    if (attentionActionCount > 0 && opened && passwordSsid === "") {
      focusSection = "attention"
      cursorActive = true
    } else if (attentionActionCount === 0 && focusSection === "attention") {
      focusSection = sections()[0]
    }
  }
  property string lastAttention: ""
  onWifiListVisibleChanged: if (!wifiListVisible && focusSection === "wifi") focusSection = sectionAboveWifi()

  function activateAttention(index) {
    if (!attentionModel || index < 0 || index >= attentionModel.actions.length) return
    var id = attentionModel.actions[index].id
    if (id === "restart") restartNetworking()
    else if (id === "airplane-off") setAirplane(false)
    else if (id === "sign-in") openCaptivePortal()
    else if (id === "vpn-retry") reconnectVpn()
    else if (id === "vpn-sign-in") signInToNetwork()
    else if (id === "vpn-off") useWithoutVpn()
    else if (id === "dns-settings") openSettings("dns")
  }

  // Settings › Network, at the network under the cursor, else the one in use
  // (D-66: the panel's "Manage…" opens the window at the item).
  function openSettings(anchor) {
    var payload = { section: "network" }
    if (anchor) payload.anchor = anchor
    var row = focusSection === "wifi" && selectedIndex >= 0 && selectedIndex < wifiNetworks.length ? wifiNetworks[selectedIndex] : null
    if (!anchor && row && row.known) payload.connection = row.ssid
    else if (!anchor && kind === "wifi" && wifiDevice) payload.device = wifiDevice.name
    else if (!anchor && kind === "ethernet" && wiredDevice) payload.device = wiredDevice.name
    controller.hide()
    cancelPasswordPrompt()
    bar.shell.summon("karchy.settings", JSON.stringify(payload))
  }

  // ---- The VPN (karchy-vpn, D-68) ----
  // Its status file is rewritten on every change and watched here; nothing
  // polls. Without the package the file doesn't exist and the VPN row hides.
  property var vpn: Model.parseVpnStatus("")
  readonly property bool vpnVisible: vpn.present
  readonly property bool vpnFailed: vpn.present && vpn.state === "failed"
  readonly property string vpnTone: Model.vpnTone(vpn)
  readonly property color vpnToneColor: vpnTone === "error" ? Commons.Color.status.error
    : vpnTone === "warning" ? Commons.Color.status.warning : panelText
  readonly property var vpnModes: ["off", "auto", "on"]
  property int vpnIndex: 1
  // "Use without VPN" says that it turned the VPN off until the mode changes.
  property bool vpnTurnedOff: false
  property string vpnError: ""
  onVpnChanged: if (vpn.mode !== "off") vpnTurnedOff = false

  FileView {
    id: vpnStatusFile
    path: "/run/karchy-vpn/status"
    watchChanges: true
    printErrors: false
    onLoaded: { root.vpn = Model.parseVpnStatus(text()); vpnStatusRetry.stop() }
    onLoadFailed: { root.vpn = Model.parseVpnStatus(""); vpnStatusRetry.restart() }
    onFileChanged: reload()
  }

  // A watch can't see the file appear when its folder is created after the
  // shell started (the VPN package installed in a running session), so look
  // again every 30 seconds while it is missing.
  Timer {
    id: vpnStatusRetry
    interval: 30000
    repeat: true
    onTriggered: vpnStatusFile.reload()
  }

  function setVpnMode(mode) {
    if (vpnModes.indexOf(mode) < 0 || vpnProc.running) return
    vpnError = ""
    vpnProc.command = ["karchy-vpn", "mode", mode]
    vpnProc.running = true
  }

  function reconnectVpn() {
    if (vpnProc.running) return
    vpnError = ""
    vpnProc.command = ["karchy-vpn", "reconnect"]
    vpnProc.running = true
  }

  function useWithoutVpn() {
    vpnTurnedOff = true
    setVpnMode("off")
  }

  // The sign-in flow also when NetworkManager couldn't see the portal: the
  // VPN's block stops its check too, so a failed VPN offers it. The command
  // pauses the VPN's block first.
  function signInToNetwork() {
    Quickshell.execDetached(["karchy-network-captive-portal", Model.captivePortalUrl])
    close()
  }

  Process {
    id: vpnProc
    stderr: StdioCollector { id: vpnStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) {
        root.vpnTurnedOff = false
        root.vpnError = vpnStderr.text.trim() || " "
      }
    }
  }

  // ---- Encrypted DNS on the link (karchy-network-dns) ----
  readonly property string linkDevice: kind === "ethernet" && wiredDevice ? wiredDevice.name
    : (kind === "wifi" && wifiDevice ? wifiDevice.name : "")
  property string dnsState: ""
  readonly property string dnsNotice: Model.dnsNotice(dnsState, vpn)

  FileView {
    id: dnsStateFile
    path: root.linkDevice !== "" ? "/run/karchy/dns/" + root.linkDevice : ""
    watchChanges: true
    printErrors: false
    onLoaded: root.dnsState = Model.parseDnsState(text())
    onLoadFailed: root.dnsState = ""
    onFileChanged: reload()
  }
  // The helper writes the file once the link is up, possibly after the path
  // was set; NetworkManager's next verdict is a good moment to read it again.
  onConnectivityChanged: dnsStateFile.reload()
  // Keyed on the device rather than the SSID: on an OWE transition-mode
  // network the listed network comes and goes with every scan while the link
  // stays up, and a real network switch already passes through "disconnected".
  readonly property string connectionKey: kind === "wifi" && wifiDevice
    ? kind + ":" + wifiDevice.name
    : (kind === "ethernet" && wiredDevice ? kind + ":" + wiredDevice.name : "")

  onConnectionKeyChanged: Qt.callLater(checkConnectivity)
  onConnectivityChecksEnabledChanged: Qt.callLater(checkConnectivity)

  function checkConnectivity() {
    if (connectivityChecksEnabled && kind !== "disconnected") Networking.checkConnectivity()
  }

  function openCaptivePortal() {
    if (!hasCaptivePortal) return
    // Explicit user action only. argv (not a shell string), and a fixed HTTP
    // URL: let the browser handle the redirect without trusting portal input.
    // The command opens a floating sign-in window and re-checks quickly until
    // the sign-in completes (it will also pause the VPN's block: D-68 step 4).
    Quickshell.execDetached(["karchy-network-captive-portal", Model.captivePortalUrl])
    close()
  }

  // Keep checking while login is needed, even with the panel closed in favour
  // of the browser. Normal connected operation relies on NM's own schedule.
  Timer {
    id: connectivityPoll
    interval: 10000
    repeat: true
    running: root.restricted && root.connectivityChecksEnabled
    onTriggered: root.checkConnectivity()
  }

  // The share card is its own panel plugin (karchy.wifiqr) so a replacement
  // design can take it over; summon() routes to whichever implementation is
  // enabled. The panel's own button pins the interface it is showing. The
  // IPC route forces self-detection instead: details polling stops while the
  // panel is closed, so its cached interface can be stale.
  function summonWifiQr(forceDetect) {
    controller.hide()
    cancelPasswordPrompt()
    var payload = {}
    if (!forceDetect && info.type === "wifi" && info.iface) {
      payload.iface = info.iface
      if (info.ssid) payload.ssid = info.ssid
    }
    bar.shell.summon("karchy.wifiqr", JSON.stringify(payload))
  }

  function refresh(scanWifi) {
    checkConnectivity()
    if (!networkingProc.running) networkingProc.running = true
    if (scanWifi === undefined) scanWifi = false
    if (!detailsProc.running) detailsProc.running = true
    if (!bandProc.running) {
      bandProc.command = ["karchy-network-band"]
      bandProc.running = true
    }
    // A closed panel has no nearby-network list to fill, and bare refresh()
    // reaches here from action completion, timeouts and construction.
    if (opened && wifiDevice) {
      if (scanWifi) {
        scanning = true
        setScannerEnabled(false)
        scanRestart.start()
      } else {
        setScannerEnabled(true)
      }
    }
    syncWifiNetworks()
  }

  function formatHeaderSpeed(mbps) {
    return Model.formatHeaderSpeed(mbps, Commons.I18n.formatNumber)
  }

  function formatHeaderFreq(mhz) {
    return Model.formatHeaderFreq(mhz, Commons.I18n.formatNumber)
  }

  function headerDetail() {
    return Model.headerDetail(info, Commons.I18n.formatNumber)
  }

  function updateDetails(raw) {
    var next = Model.parseKeyValue(raw)

    // A band change tears the link down and brings it back, and the status
    // command reports nothing at all while there is no route. Publishing that
    // would blank every stat and unmount the whole section mid-toggle, so the
    // last good sample stands until the reconnect settles. A real disconnect is
    // still reported, because nothing is in flight then.
    if (bandBusy && !next.iface) return

    info = next
    updatePingLatency(next)
  }

  function updatePingLatency(next) {
    var state = Model.pingLatencyState({
      pingIface: pingIface,
      routerPingSamples: routerPingSamples,
      internetPingSamples: internetPingSamples
    }, next, pingHistoryWindow, pingAverageWindow)

    pingIface = state.pingIface
    routerPingSamples = state.routerPingSamples
    internetPingSamples = state.internetPingSamples
    routerPingLatency = state.routerPingLatency
    internetPingLatency = state.internetPingLatency
    internetPingPacketLoss = state.internetPingPacketLoss
  }

  function formatPingLatency(ms) {
    return Model.formatPingLatency(ms, hasInternetPing, Commons.I18n.t, Commons.I18n.formatNumber)
  }

  function formatPacketLoss(percent) {
    return Model.formatPacketLoss(percent, hasInternetPing, Commons.I18n.formatNumber)
  }

  // Prefer a connected device: a machine can expose several NICs of the
  // same type (e.g. an idle onboard port alongside the active adapter),
  // and the first-enumerated one may be carrierless.
  function findDevice(type) {
    var devices = networkDevices || []
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var device = devices[i]
      if (!device || device.type !== type) continue
      if (device.connected) return device
      if (!fallback) fallback = device
    }
    return fallback
  }

  function findConnectedWifiNetwork() {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].connected) return networks[i]
    }
    return null
  }

  function syncWifiNetworks() {
    rebuildWifiRows()
    wifiStationAvailable = !!wifiDevice
    scanning = false
  }

  function rebuildWifiRows() {
    var nets = []
    var networks = wifiNetworkObjects || []

    for (var i = 0; i < networks.length; i++) {
      var network = networks[i]
      if (!network) continue
      checkActionCompletion(network)
      var row = Model.wifiRow(network)
      if (row) nets.push(row)
    }
    nets = Model.sortWifiRows(nets)
    // A new model rebuilds every delegate, which takes focus from a passphrase
    // being typed, so identical rows are left in place.
    if (JSON.stringify(nets) === JSON.stringify(wifiNetworks)) return
    var selected = wifiNetworks[selectedIndex]
    cursorSsid = selected ? selected.ssid : null
    wifiNetworks = nets
  }

  function wifiSectionTitle(index) {
    return Model.wifiSectionTitle(wifiNetworks, index, Commons.I18n.t)
  }

  function wifiIconFor(strength) {
    return Icons.glyph(Model.wifiIconFor(strength))
  }

  function updateBand(raw) {
    var status = Model.parseBandStatus(raw)

    // Mid-reconnect there is no connected station, so the command reports
    // nothing. Publishing that would empty the option list and unmount the
    // section on every toggle -- same guard as updateDetails.
    if (bandBusy && status.available.length === 0) return

    bandCurrent = status.band
    bandSelected = status.selected
    bandAvailable = status.available
  }

  // Pinning a band reassociates, but the panel deliberately stays open: the
  // reconnect is the thing you want to watch, and the details rows above
  // report it as it happens.
  function setBand(band) {
    if (!band || actionProc.running) return

    root.pendingBand = band
    actionProc.command = ["karchy-network-band", band]
    actionProc.running = true
  }

  // The speed test is its own panel plugin (karchy.speedtest) so a
  // replacement design can take it over; summon() routes to whichever
  // implementation is enabled. The payload names the connection when this
  // panel knows it; the plugin looks it up itself otherwise.
  function summonSpeedTest() {
    controller.hide()
    cancelPasswordPrompt()
    var connection = Model.speedTestConnection(info, Commons.I18n.t)
    bar.shell.summon("karchy.speedtest", connection ? JSON.stringify({ connection: connection }) : "{}")
  }

  function requiresCredentials(security) {
    return Model.requiresCredentials(security, WifiSecurityType.Open, WifiSecurityType.Owe)
  }

  function openPasswordPrompt(ssid) {
    if (passwordSsid !== ssid) {
      passwordText = ""
      resetEnterpriseFields()
    }
    passwordSsid = ssid
  }

  function setIdentity(text) {
    identityText = text
    if (!domainEdited) domainText = Model.identityRealm(text)
  }

  // Editing any field of the prompt answers the failure it shows.
  function clearPromptFailure() {
    if (failureSsid === passwordSsid) {
      failureSsid = ""
      failureReason = ""
      failureKind = ""
    }
  }

  function networkForSsid(ssid) {
    var networks = wifiNetworkObjects || []
    for (var i = 0; i < networks.length; i++) {
      if (networks[i] && networks[i].name === ssid) return networks[i]
    }
    return null
  }

  function wifiIndexForSsid(ssid) {
    for (var i = 0; i < wifiNetworks.length; i++) {
      if (wifiNetworks[i] && wifiNetworks[i].ssid === ssid) return i
    }
    return -1
  }

  function runNetworkAction(kind, network, callback) {
    if (actionKind !== "" || !network) return
    var ssid = network.name || ""
    actionSsid = ssid
    actionKind = kind
    failureSsid = ""
    failureReason = ""
    failureKind = ""
    // Already in the asked-for state: Quickshell ignores such a call, so nothing
    // would ever signal, and the enterprise script would reconnect a live link.
    checkActionCompletion(network)
    if (actionKind === "") return
    callback(network)
    // Safety net: if onExited never fires (process death, signal handler
    // throws, etc.), clear the busy state so the row doesn't get stuck on
    // "Connecting…" / "Disconnecting…" forever.
    actionTimeout.restart()
  }

  function clearNetworkAction() {
    actionTimeout.stop()
    if (actionKind === "connect" && passwordSsid === actionSsid) passwordSsid = ""
    failureSsid = ""
    failureReason = ""
    failureKind = ""
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function failNetworkAction(network, reason) {
    if (!network || actionKind === "" || actionSsid !== (network.name || "")) return
    actionTimeout.stop()
    var needsCredentials = requiresCredentials(network.security)
    failureSsid = actionSsid
    failedAction = actionKind
    failureReason = networkFailureReason(reason, needsCredentials)
    failureKind = Model.networkFailureKind(reason, needsCredentials, connectionFailReasons)
    actionSsid = ""
    actionKind = ""
    refresh()
  }

  function networkFailureReason(reason, needsCredentials) {
    return Model.networkFailureReason(reason, needsCredentials, connectionFailReasons, Commons.I18n.t)
  }

  function shouldRepromptPassphrase(reason, needsCredentials) {
    return Model.shouldRepromptPassphrase(reason, needsCredentials, connectionFailReasons)
  }

  function checkActionCompletion(network) {
    if (!network) return
    var settled = network.connected && !network.stateChanging
    // A prompt only opens for a network that is not connected, so once it is
    // there is nothing left to ask, whether or not its error is still showing.
    if (settled && passwordSsid !== "" && passwordSsid === (network.name || "")) passwordSsid = ""
    // NetworkManager can connect a network on its own after a panel connect to
    // it failed; only a failed connect, since a timed-out disconnect stays connected.
    if (settled && failedAction === "connect" && failureReason !== "" && failureSsid === (network.name || "")) {
      failureSsid = ""
      failureReason = ""
      failureKind = ""
    }
    if (actionKind === "" || actionSsid !== (network.name || "")) return
    if (actionKind === "connect" && network.connected) clearNetworkAction()
    else if (actionKind === "disconnect" && !network.connected && !network.stateChanging) clearNetworkAction()
    else if (actionKind === "forget" && !network.known && !network.stateChanging) clearNetworkAction()
  }

  function connectDirectly(ssid) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connect() })
  }

  function connectWithPassphrase(ssid, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) { network.connectWithPsk(passphrase) })
  }

  // `domain` empty means the person chose to connect without checking the
  // server; the prompt allows that only behind its warning.
  function connectEnterprise(ssid, identity, domain, passphrase) {
    runNetworkAction("connect", networkForSsid(ssid), function(network) {
      enterpriseConnect.secret = passphrase
      enterpriseConnect.ssid = ssid
      enterpriseConnect.command = ["bash", "-c", Model.enterpriseConnectScript, "nmcli-eap", ssid, identity, domain]
      enterpriseConnect.running = true
    })
  }

  // Creates and activates the 802.1X profile (see Model.enterpriseConnectScript).
  // The password goes over stdin, never argv.
  Process {
    id: enterpriseConnect
    property string secret: ""
    property string ssid: ""
    stdinEnabled: true
    onStarted: {
      write(secret + "\n")
      secret = ""
    }
    // NetworkManager's own failure signal usually lands first; this catches a
    // profile nmcli refused before activation, or a failed sign-in the
    // network reported no reason for, instead of waiting out the timeout.
    // nmcli only says "Secrets were required" when the credentials (or the
    // server's certificate) were refused.
    stderr: StdioCollector { id: enterpriseStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) return
      var refused = /Secrets were required|802\.1X supplicant/.test(enterpriseStderr.text)
      root.failNetworkAction(root.networkForSsid(ssid), refused ? ConnectionFailReason.NoSecrets : undefined)
    }
  }

  function disconnect(network) {
    runNetworkAction("disconnect", network || connectedWifiNetwork, function(net) { net.disconnect() })
  }

  // Disconnect from a row's SSID. Rows are primitive snapshots that can outlive
  // their WifiNetwork, and disconnect()'s null fallback targets whatever is
  // connected now, so a stale row must do nothing rather than hit an unrelated
  // network. Callers that mean "drop the current connection" call disconnect().
  function disconnectRow(ssid) {
    var network = networkForSsid(ssid)
    if (network) disconnect(network)
  }

  function forget(net) {
    runNetworkAction("forget", net ? networkForSsid(net.ssid) : null, function(network) { network.forget() })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  // Pulls everything we want about the active route's interface in one shot.
  Process {
    id: detailsProc
    command: ["karchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateDetails(text)
    }
  }

  // Reads the in-use access point's strength without triggering a scan, for
  // the connected network that has none of its own (see signalStrength).
  Process {
    id: activeApSignalProc
    command: ["nmcli", "-t", "-f", "IN-USE,SIGNAL", "device", "wifi", "list", "ifname", root.wifiDevice ? root.wifiDevice.name : "", "--rescan", "no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.finishActiveApSignal(text)
    }
  }

  Timer {
    id: activeApSignalPoll
    interval: 5000
    repeat: true
    triggeredOnStart: true
    running: root.needsActiveApSignal
    onTriggered: root.pollActiveApSignal()
  }

  Timer {
    id: scanRestart
    interval: 100
    repeat: false
    onTriggered: {
      if (root.opened && root.wifiDevice) {
        root.setScannerEnabled(true)
        scanDone.start()
      }
    }
  }

  Timer {
    id: scanDone
    interval: 1500
    repeat: false
    onTriggered: root.syncWifiNetworks()
  }

  Process {
    id: bandProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateBand(text)
    }
  }

  // Slower than detailsPoll on purpose: this shells out to nmcli several times,
  // and band availability only moves when a scan turns up a new BSSID.
  Timer {
    id: bandPoll
    interval: 4000
    repeat: true
    running: root.opened
    onTriggered: {
      if (bandProc.running) return
      bandProc.command = ["karchy-network-band"]
      bandProc.running = true
    }
  }

  // Action runner for band changes. Wi-Fi actions use the
  // Quickshell.Networking NetworkManager backend directly.
  Process {
    id: actionProc
    stdout: StdioCollector { id: actionStdout; waitForEnd: true }
    stderr: StdioCollector { id: actionStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (root.pendingBand !== "") {
        // A refused or reverted pin leaves bandSelected alone, so the pills
        // keep showing what is actually in force rather than what was asked.
        if (exitCode === 0) root.bandSelected = root.pendingBand
        root.pendingBand = ""
        // The panel stayed open through the reconnect, so pull fresh state now
        // instead of leaving stale readings until the next poll tick.
        root.refresh()
      }
    }
  }

  // Poll details while the panel is open so the IP/route header catches up
  // as soon as NetworkManager finishes activating a connection.
  Timer {
    id: detailsPoll
    interval: 1500
    repeat: true
    running: root.opened
    onTriggered: if (!detailsProc.running) detailsProc.running = true
  }

  Timer {
    id: actionTimeout
    // Must outlast NetworkManager's 25s supplicant timeout: a wrong saved
    // PSK fails with WifiAuthTimeout at ~25s, and that failure has to land
    // while the action is still tracked to show "Wrong password" and reopen
    // the passphrase prompt.
    interval: 30000
    repeat: false
    onTriggered: {
      if (!root.actionKind) return
      var reason
      if (root.actionKind === "connect") reason = Commons.I18n.t("network.timedOutConnecting")
      else if (root.actionKind === "disconnect") reason = Commons.I18n.t("network.timedOutDisconnecting")
      else reason = Commons.I18n.t("network.timedOutForgetting")
      root.failureSsid = root.actionSsid
      root.failedAction = root.actionKind
      root.failureReason = reason
      root.failureKind = "timeout"
      root.actionSsid = ""
      root.actionKind = ""
      root.refresh()
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    // The VPN's block is never hidden: warning while it connects or pauses,
    // error once it failed.
    active: root.restricted || root.vpnTone !== ""
    activeColor: root.vpnTone !== "" ? root.vpnToneColor : (root.bar ? root.bar.urgent : Commons.Color.urgent)
    tooltipText: root.airplane && root.kind === "disconnected" ? Commons.I18n.t("network.airplaneMode")
      : root.hasCaptivePortal ? Commons.I18n.t("network.signInToNetwork")
      : Model.vpnTooltip(root.vpn, Commons.I18n.t) !== "" ? Model.vpnTooltip(root.vpn, Commons.I18n.t)
      : (root.restricted ? Commons.I18n.t("network.limitedAccess") : "")

    onPressed: function(b) {
      if (root.opened) root.close()
      // open() is enough: onOpenedChanged runs refresh(true), which defers the
      // PHY scan past the first frame. The bare refresh() that used to follow
      // took the no-scan branch and set scannerEnabled synchronously, undoing
      // that deferral and stalling the open on NetworkManager's AP flood.
      else root.open()
    }
  }

  // Keyboard-driven popup anchored to the bar widget icon. The shared
  // KeyboardPanel handles the layer-shell PanelWindow scaffolding
  // (focus priming on open, screen binding, anchored-to-icon positioning,
  // outside-click via an overlay MouseArea + Region mask that lets the bar
  // remain clickable, fade animation, popout coordination). What stays
  // here is the wifi-specific UI inside.
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    // Catches all unhandled keys for keyboard navigation. AfterItem priority
    // lets the passphrase TextField (a child via focus chain) get its keys
    // first; only events the focused subtree ignores bubble back here.
    content: PanelKeyCatcher {
      id: keyCatcher
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      // Freeze the cursor model while the inline password prompt is open;
      // the TextField inside owns input until Esc/Enter/Cancel.
      blocked: root.passwordSsid !== ""

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          if (dy >= 0) return
        }
        if (dy !== 0) {
          // Hidden sections drop out of the keyboard chain entirely. The band
          // has two rows of its own (Automatic, then the pills) and the list
          // walks its rows before handing back to the section above.
          if (root.focusSection === "band" && dy < 0 && !root.bandAutoFocused) {
            root.bandAutoFocused = true
          } else if (root.focusSection === "band" && dy > 0 && root.bandAutoFocused && root.bandPillsVisible) {
            root.bandAutoFocused = false
          } else if (root.focusSection === "wifi" && !(dy < 0 && root.selectedIndex <= 0)
              && !(dy > 0 && root.selectedIndex >= root.wifiNetworks.length - 1)) {
            root.selectByDelta(dy)
          } else {
            root.moveSection(dy)
          }
        }
        if (dx !== 0) {
          if (root.focusSection === "vpn") root.vpnIndex = Math.max(0, Math.min(2, root.vpnIndex + dx))
          else if (root.focusSection === "attention") root.attentionIndex = Math.max(0, Math.min(root.attentionActionCount - 1, root.attentionIndex + dx))
          else if (root.focusSection === "header") root.selectHeaderByDelta(dx)
          else if (root.focusSection === "band") { if (!root.bandAutoFocused) root.selectBandByDelta(dx) }
          else if (root.focusSection === "wifi") root.selectWifiActionByDelta(dx)
        }
      }
      onActivateRequested: {
        if (root.cursorActive) {
          if (root.focusSection === "header") root.activateHeader()
          else if (root.focusSection === "attention") root.activateAttention(root.attentionIndex)
          else if (root.focusSection === "footer") root.openSettings("")
          else if (root.focusSection === "vpn") root.setVpnMode(root.vpnModes[root.vpnIndex])
          else if (root.focusSection === "band") root.activateBand()
          else root.activateSelected()
        }
      }
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "w" || t === "W") root.toggleNetwork()
      }

    Column {
      id: column
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      spacing: Style.space(12)

      // ---------- Hero: network icon · SSID + state · actions ----------
      // Status only on the left. Sharing belongs to the connected-network
      // hero rather than the scan result row; the radio switch sits beside
      // it as the other hero action. Link detail rides inline after the name
      // ("Ethernet (2.5gbit)") rather than in a pill, which crowded the switch.
      // The real state in words (Model.heroState): the network and whether
      // the internet works through it, never a decorative phrase.
      PanelHero {
        id: hero
        iconText: root.icon
        iconColor: root.heroModel.tone !== "" ? root.heroToneColor
          : root.networkManagerAvailable && root.hasAdapter ? root.panelText
          : Commons.Color.secondaryText(root.panelText, root.panelSurface)
        title: root.heroModel.title
        meta: root.heroModel.status
        metaColor: root.heroToneColor
        fontFamily: root.bar.fontFamily

        trailingControl: Component {
          RowLayout {
            spacing: Style.space(8)

            PanelActionButton {
              visible: root.canShareWifi
              iconText: Icons.glyph("net.qr")
              tooltipText: Commons.I18n.t("network.showQrCode")
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.iconLarge
              hasCursor: root.qrHeaderHasCursor
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor(root.qrHeaderIndex) }
              onClicked: root.summonWifiQr()
            }

            PanelActionButton {
              visible: root.canRunSpeedTest
              iconText: Icons.glyph("net.speedtest")
              tooltipText: Commons.I18n.t("network.runSpeedTest")
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              fontSize: Style.font.iconLarge
              hasCursor: root.speedHeaderHasCursor
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor(root.speedHeaderIndex) }
              onClicked: root.summonSpeedTest()
            }

            ToggleSwitch {
              id: powerSwitch
              flush: true
              visible: root.canToggleWifi
              checked: Networking.wifiEnabled
              hasCursor: root.toggleHeaderHasCursor
              foreground: root.panelText
              accessibleName: "Wi-Fi"
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor(root.toggleHeaderIndex) }
              onToggled: root.toggleNetwork()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.bar.fontFamily
              }
            }
          }
        }
      }

      // ---------- Attention: the one thing that needs the person ----------
      // Only while something must be done or explained (Model.attention): the
      // first button is what the row is for, and says what it will do.
      Column {
        visible: root.attentionModel !== null
        width: parent.width
        spacing: Style.spacing.md

        InlineMessage {
          width: parent.width
          kind: root.attentionModel ? root.attentionModel.kind : "info"
          text: root.attentionModel ? root.attentionModel.text : ""
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
        }

        Flow {
          visible: root.attentionActionCount > 0
          width: parent.width
          spacing: Style.spacing.md

          Repeater {
            model: root.attentionModel ? root.attentionModel.actions : []

            Button {
              required property var modelData
              required property int index
              text: modelData.label
              tooltipText: modelData.tooltip || ""
              variant: index === 0 ? "primary" : "neutral"
              bordered: true
              fontFamily: root.bar.fontFamily
              foreground: root.panelText
              busy: (modelData.id === "vpn-retry" || modelData.id === "vpn-off") && vpnProc.running
              hasCursor: root.cursorActive && root.focusSection === "attention" && root.attentionIndex === index
              onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "attention"; root.attentionIndex = index } }
              onClicked: root.activateAttention(index)
            }
          }
        }
      }

      // ---------- VPN: what it does now, and Off / Auto / On ----------
      Column {
        visible: root.vpnVisible
        width: parent.width
        spacing: Style.spacing.md

        Item {
          width: parent.width
          implicitHeight: Math.max(vpnHeader.implicitHeight, vpnModeGroup.implicitHeight)

          PanelSectionHeader {
            id: vpnHeader
            text: Commons.I18n.t("network.vpn")
            foreground: root.panelText
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          ButtonGroup {
            id: vpnModeGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            focusable: false
            options: [
              { value: "off", label: Commons.I18n.t("network.vpnModeOff"), tooltip: Commons.I18n.t("network.vpnModeOffTooltip") },
              { value: "auto", label: Commons.I18n.t("network.vpnModeAuto"), tooltip: Commons.I18n.t("network.vpnModeAutoTooltip") },
              { value: "on", label: Commons.I18n.t("network.vpnModeOn"), tooltip: Commons.I18n.t("network.vpnModeOnTooltip") }
            ]
            value: root.vpn.mode
            foreground: root.panelText
            fontFamily: root.bar.fontFamily
            fontSize: Style.font.bodySmall
            cursorIndex: root.cursorActive && root.focusSection === "vpn" ? root.vpnIndex : -1
            onChanged: function(value) { root.setVpnMode(value) }
            onHovered: function(index, on) {
              if (!on) return
              root.cursorActive = true
              root.focusSection = "vpn"
              root.vpnIndex = index
            }
          }
        }

        // While it failed, the attention row above already says it.
        Text {
          visible: !root.vpnFailed
          width: parent.width
          textFormat: Text.PlainText
          wrapMode: Text.Wrap
          text: root.vpnTurnedOff && root.vpn.mode === "off"
            ? Commons.I18n.t("network.vpnTurnedOff")
            : Model.vpnStatusLine(root.vpn, Commons.I18n.t, function(epoch) {
                return Qt.formatTime(new Date(epoch * 1000), Qt.locale().timeFormat(Locale.ShortFormat))
              })
          color: root.vpnTone !== "" ? root.vpnToneColor : Commons.Color.secondaryText(root.panelText, root.panelSurface)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        InlineMessage {
          width: parent.width
          kind: "error"
          visible: root.vpnError !== ""
          text: Commons.I18n.t("network.vpnChangeFailed")
          details: root.vpnError.trim()
          dismissible: true
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
          onDismissed: root.vpnError = ""
        }
      }

      PanelSeparator {
        visible: root.vpnVisible
        foreground: root.panelText
      }

      // Connection details, compact: is the internet answering, and where is
      // this computer on the network. The rest is in Settings › Network.
      Column {
        visible: !!root.info.iface && root.kind !== "disconnected"
        width: parent.width
        spacing: Style.spacing.labelGap

        // Always mounted: ping and packet loss used to appear a beat after
        // the panel opened, once the first probe returned, shoving everything
        // below them down. They hold their place and read "--" until there
        // is a sample, and while the internet is out of reach.
        KeyValueGrid {
          readonly property color lossColor: root.hasInternetPing && root.internetPingPacketLoss > 0
            ? Commons.Color.status.warning : root.panelText
          width: parent.width
          columns: 2
          justify: true
          fontSize: Style.font.bodySmall
          foreground: root.panelText
          surface: root.panelSurface
          fontFamily: root.bar.fontFamily
          placeholder: "--"
          // The real link's address and router, also with a VPN up; the VPN's
          // own address is in Settings.
          rows: [
            { label: Commons.I18n.t("network.ping"), value: root.formatPingLatency(root.internetPingLatency), color: lossColor },
            { label: Commons.I18n.t("network.packetLoss"), value: root.formatPacketLoss(root.internetPingPacketLoss), color: lossColor },
            { label: Commons.I18n.t("network.ipAddress"), value: root.info.ip || "", copyable: true, tooltip: Commons.I18n.t("network.copyIp") },
            { label: Commons.I18n.t("network.gateway"), value: root.info.gateway || "", copyable: true, tooltip: Commons.I18n.t("network.copyGateway") }
          ]
          onCopyRequested: function(value) { root.copyToClipboard(value) }
        }

        // The network blocks encrypted DNS, so its own is used for now. A
        // fact about this link, not something to act on here.
        Row {
          visible: root.dnsNotice === "fallback"
          spacing: Style.spacing.sm

          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: Commons.I18n.t("network.dnsFallback")
            color: Commons.Color.secondaryText(root.panelText, root.panelSurface)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          InfoTip {
            anchors.verticalCenter: parent.verticalCenter
            subject: Commons.I18n.t("network.dnsFallback")
            text: Commons.I18n.t(root.vpnVisible ? "network.dnsFallbackWhyVpn" : "network.dnsFallbackWhy")
          }
        }
      }

      // Wi-Fi band selection. Only on Wi-Fi, and only when the network answers
      // on more than one band -- a single-band AP has nothing to toggle.
      PanelSeparator {
        visible: root.canSelectBand
        foreground: root.panelText
      }

      Column {
        visible: root.canSelectBand
        width: parent.width
        spacing: Style.space(10)

        // "Automatic" rides on the header line rather than under the pills: it
        // qualifies the whole row, and at header scale it reads as a modifier
        // instead of competing with the band choices for attention.
        Item {
          width: parent.width
          implicitHeight: Math.max(bandHeader.implicitHeight, bandAutoRow.implicitHeight)

          PanelSectionHeader {
            id: bandHeader
            text: root.bandSectionTitle
            foreground: root.panelText
            fontFamily: root.bar.fontFamily
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Row {
            id: bandAutoRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(6)

            PanelSectionHeader {
              id: bandAutoLabel
              text: Commons.I18n.t("network.automatic")
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              anchors.verticalCenter: parent.verticalCenter
            }

            // Sized off the label rather than the theme's control height so it
            // reads as part of the header, and centred on the label's *glyphs*:
            // PanelSectionHeader carries topPadding to protect Nerd Font
            // overshoot, which pushes its text below its own box centre, so a
            // plain verticalCenter would sit the switch visibly high.
            ToggleSwitch {
              id: bandAutoSwitch
              trackHeight: Math.round(bandAutoLabel.font.pixelSize * 1.2)
              cursorPad: Style.space(3)
              anchors.verticalCenter: bandAutoLabel.verticalCenter
              anchors.verticalCenterOffset: Math.round(bandAutoLabel.topPadding / 2)
              checked: !root.bandPinned
              busy: root.bandBusy
              hasCursor: root.cursorActive && root.focusSection === "band" && root.bandAutoFocused
              foreground: root.panelText
              onToggled: root.toggleBandAuto()

              onHovered: function(isHovered) {
                if (!isHovered) return
                root.cursorActive = true
                root.focusSection = "band"
                root.bandAutoFocused = true
              }

              PanelToolTip {
                visible: bandAutoSwitch.containsMouse
                text: root.bandPinned
                  ? Commons.I18n.t("network.bandAutoTooltip")
                  : Commons.I18n.t("network.stayOnBand").arg(root.bandLabel(root.bandCurrent))
                fontFamily: root.bar.fontFamily
              }
            }
          }
        }

        // Collapsing container: the pills animate their height so toggling
        // Automatic slides the sections below into place instead of snapping.
        // `visible` only drops at a real zero, which keeps the row rendered for
        // the whole animation and takes it out of the Column's spacing once
        // it's actually gone.
        Item {
          id: bandPillsClip
          width: parent.width
          clip: true
          visible: height > 0
          height: root.bandPillsVisible ? bandRow.implicitHeight : 0
          opacity: root.bandPillsVisible ? 1 : 0

          Behavior on height {
            NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
          }
          Behavior on opacity {
            NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
          }

          Row {
            id: bandRow
            width: parent.width
            spacing: Style.space(6)

            readonly property int count: Math.max(1, root.bandAvailable.length)
            readonly property real cellWidth: (width - spacing * (count - 1)) / count

            // Wrapper takes modelData/index from the Repeater's delegate
            // context, which doesn't bind into nested `component` declarations,
            // and passes them down explicitly -- same shape as the network
            // list delegate.
            Repeater {
              model: root.bandAvailable

              delegate: Item {
                required property var modelData
                required property int index
                width: bandRow.cellWidth
                height: bandPill.implicitHeight

                BandPill {
                  id: bandPill
                  band: modelData
                  slot: index
                  width: parent.width
                }
              }
            }
          }
        }

      }

      // Wi-Fi networks (only while the radio can join one).
      PanelSeparator {
        visible: root.wifiListVisible || ethernetHardwareNote.visible
        foreground: root.panelText
      }

      // On Ethernet the hero describes the cable, so say here why the Wi-Fi
      // switch and networks are gone.
      PanelSectionHeader {
        id: ethernetHardwareNote
        visible: root.wifiStationAvailable && root.wifiHardwareBlocked && root.kind !== "disconnected" && !root.airplane
        text: Commons.I18n.t("network.wifiHardwareOff")
        foreground: root.panelText
        fontFamily: root.bar.fontFamily
      }

      PanelSectionHeader {
        visible: root.wifiListVisible && root.scanning
        text: Commons.I18n.t("network.scanningWifi")
        foreground: root.panelText
        fontFamily: root.bar.fontFamily
      }

      // Scrollable network list — cap the height so a busy neighbourhood
      // doesn't push the popup off-screen. ListView (vs Repeater+Column)
      // gives us positionViewAtIndex for free, which is what keeps the
      // keyboard-selected row scrolled into view as j/k walk past the
      // visible window.
      ListView {
        id: networkList
        visible: root.wifiListVisible
        width: parent.width
        height: Math.min(contentHeight, Style.space(240))
        spacing: Style.space(4)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        model: root.wifiListVisible ? root.wifiNetworks : []
        currentIndex: root.selectedIndex
        onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)

        // Wrapper takes the required props from ListView's delegate context
        // (which doesn't bind into nested `component` declarations like
        // NetworkRow) and passes them down explicitly.
        delegate: Item {
          required property var modelData
          required property int index
          readonly property string sectionTitle: root.wifiSectionTitle(index)
          width: ListView.view.width
          height: delegateColumn.implicitHeight

          Column {
            id: delegateColumn
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              visible: sectionTitle !== ""
              text: sectionTitle
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              height: visible ? implicitHeight : 0
            }

            NetworkRow {
              id: row
              width: parent.width
              net: modelData
              index: parent.parent.index
            }
          }
        }
      }

      EmptyState {
        visible: root.wifiListVisible && !root.scanning && root.wifiNetworks.length === 0
        width: parent.width
        iconName: "net.wifi.0"
        title: Commons.I18n.t("network.noNetworksTitle")
        body: Commons.I18n.t("network.noNetworksBody")
        foreground: root.panelText
        surface: root.panelSurface
        fontFamily: root.bar.fontFamily
      }

      EmptyState {
        visible: root.networkManagerAvailable && root.networkingEnabled && !root.hasAdapter
        width: parent.width
        iconName: "net.network"
        title: Commons.I18n.t("network.noAdapterTitle")
        body: Commons.I18n.t("network.noAdapterBody")
        foreground: root.panelText
        surface: root.panelSurface
        fontFamily: root.bar.fontFamily
      }

      PanelSeparator { foreground: root.panelText }

      // Everything else about the network, at the one under the cursor or in
      // use (D-66), as Containers and VMs open their windows.
      Button {
        width: parent.width
        text: Commons.I18n.t("network.settings")
        iconText: Icons.glyph("ui.open-external")
        bordered: true
        foreground: root.panelText
        fontFamily: root.bar.fontFamily
        hasCursor: root.cursorActive && root.focusSection === "footer"
        onHovered: function(on) { if (on) { root.cursorActive = true; root.focusSection = "footer" } }
        onClicked: root.openSettings("")
      }
    }
    }
  }

  // One Wi-Fi band pill. `active` (fill) is the band actually in use and
  // `selected` (bold) is the pinned choice; with Automatic on nothing is
  // pinned, so only the live band lights up and the two can no longer read as
  // a contradiction. They land on the same pill once a band is pinned.
  component BandPill: Button {
    id: pill
    required property string band
    required property int slot

    text: root.bandLabel(band)
    tooltipText: root.bandTooltip(band)
    fontSize: Style.font.bodySmall
    foreground: root.panelText
    fontFamily: root.bar.fontFamily
    horizontalPadding: Style.spacing.controlPaddingX
    verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
    bordered: true

    active: root.bandCurrent === band
    selected: root.bandEffective === band
    hasCursor: root.cursorActive && root.focusSection === "band"
      && !root.bandAutoFocused && root.bandIndex === slot

    onClicked: root.setBand(band)

    onHovered: function(isHovered) {
      if (!isHovered) return
      root.cursorActive = true
      root.focusSection = "band"
      root.bandIndex = pill.slot
    }
  }

  // Label and field of the inline credentials prompt (NetworkRow). Work or
  // school Wi-Fi asks for three values, so each gets a label; the one-field
  // passphrase prompt goes without.
  component PromptLabel: Text {
    textFormat: Text.PlainText
    Layout.preferredWidth: Style.space(64)
    Layout.alignment: Qt.AlignVCenter
    color: Commons.Color.secondaryText(root.panelText, Commons.Color.popups.background)
    font.family: root.bar.fontFamily
    font.pixelSize: Style.font.bodySmall
    elide: Text.ElideRight
  }

  component PromptField: TextField {
    Layout.fillWidth: true
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    foreground: root.panelText
    horizontalPadding: Style.spacing.controlGap
    verticalPadding: Style.spacing.controlPaddingY
    Keys.onEscapePressed: root.cancelPasswordPrompt()
  }

  // A single Wi-Fi network entry. Collapses to a one-line pill normally;
  // expands inline to a passphrase prompt when the user picks a network that
  // requires credentials we do not have. Clicking a connected row
  // disconnects.
  component NetworkRow: CursorSurface {
    id: row
    required property var net
    required property int index

    readonly property bool isConnected: net && net.connected
    readonly property bool isKnown: !!(net && net.known)
    readonly property bool requiresCredentials: net ? root.requiresCredentials(net.security) : false
    readonly property bool isEnterprise: net
      ? (net.security === WifiSecurityType.Wpa2Eap || net.security === WifiSecurityType.WpaEap)
      : false
    readonly property bool canForget: root.canForgetNetwork(net)
    readonly property bool isSelected: root.focusSection === "wifi" && root.selectedIndex === index
    readonly property bool forgetFocused: isSelected && root.wifiActionFocused && canForget
    readonly property bool forgetVisible: canForget && (!requiresCredentials || forgetFocused || rightMouse.containsMouse)

    hasCursor: root.cursorActive && isSelected && !root.wifiActionFocused
    current: isConnected
    foreground: root.panelText
    fill: root.hoverFill
    currentFill: root.selectedFill
    // Gate on the matching *Kind/*Reason being non-empty so a hidden-SSID
    // row (ssid == "") doesn't match the "" defaults of actionSsid etc.
    readonly property bool isBusy: root.actionKind !== "" && root.actionSsid === (net ? net.ssid : "")
    readonly property bool isFailed: root.failureReason !== "" && root.failureSsid === (net ? net.ssid : "")
    readonly property bool isPasswordOpen: root.passwordSsid !== "" && root.passwordSsid === (net ? net.ssid : "")

    // Work or school Wi-Fi connects only with a domain to check the server
    // against, unless the person chose to skip that check behind its warning.
    readonly property string serverDomain: root.domainText.trim()
    readonly property bool canSubmit: !!net && root.passwordText.length > 0
      && (!isEnterprise || (root.identityText.trim().length > 0 && (serverDomain !== "" || root.skipServerCheck)))
    // Offered when there's no domain to check, or a sign-in with one failed
    // (the server's certificate may not match it).
    readonly property bool offersSkipServerCheck: isEnterprise && (root.skipServerCheck || serverDomain === "" || isFailed)

    function submitCredentials() {
      if (!canSubmit || root.busy) return
      if (!isEnterprise) return root.connectWithPassphrase(net.ssid, root.passwordText)
      root.connectEnterprise(net.ssid, root.identityText.trim(), root.skipServerCheck ? "" : serverDomain, root.passwordText)
    }

    // Where typing goes when the prompt appears: after a failure, the
    // password, selected so typing replaces it (the row may have been rebuilt
    // by then, when the attempt turned it into a known network); otherwise
    // the first field.
    function focusPrompt() {
      if (!isPasswordOpen || isBusy) return
      if (isFailed) {
        pwField.forceActiveFocus()
        pwField.selectAll()
      } else if (isEnterprise && root.identityText === "") {
        idField.forceActiveFocus()
      } else {
        pwField.forceActiveFocus()
      }
    }

    onIsFailedChanged: if (isFailed) Qt.callLater(focusPrompt)
    onIsBusyChanged: if (!isBusy) Qt.callLater(focusPrompt)
    onIsPasswordOpenChanged: if (isPasswordOpen) Qt.callLater(focusPrompt)
    Component.onCompleted: if (isPasswordOpen) Qt.callLater(focusPrompt)

    Connections {
      target: row.net ? root.networkForSsid(row.net.ssid) : null
      function onConnectionFailed(reason) {
        // Background auto-connect retries fire this too; only reprompt for
        // the connect started from this panel. Checked before
        // failNetworkAction, which clears the action state.
        var ours = root.actionKind === "connect" && root.actionSsid === (row.net.ssid || "")
        root.failNetworkAction(root.networkForSsid(row.net.ssid), reason)
        if (ours && root.shouldRepromptPassphrase(reason, row.requiresCredentials)) root.openPasswordPrompt(row.net.ssid)
      }
    }

    readonly property string statusText: {
      if (!net) return ""
      if (isPasswordOpen) return ""
      if (isBusy && root.actionKind === "connect") return Commons.I18n.t("network.connecting")
      if (isBusy && root.actionKind === "disconnect") return Commons.I18n.t("network.disconnecting")
      if (isBusy && root.actionKind === "forget") return Commons.I18n.t("network.forgetting")
      if (isFailed) return root.failureReason || Commons.I18n.t("network.failed")
      if (isConnected && root.kind === "wifi" && root.hasCaptivePortal) return Commons.I18n.t("network.signInRequired")
      if (isConnected) return Commons.I18n.t("network.connected")
      return ""
    }

    readonly property color statusColor: {
      if (isFailed) return Commons.Color.status.error
      if (isBusy) return root.panelText
      if (isConnected && root.kind === "wifi" && root.hasCaptivePortal) return Commons.Color.status.warning
      if (isConnected) return root.panelText
      return Commons.Color.secondaryText(root.panelText, Commons.Color.popups.background)
    }

    implicitHeight: rowBody.implicitHeight + (isPasswordOpen ? passwordPanel.implicitHeight + Style.spacing.md : 0)

    MouseArea {
      id: rowMouse
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      height: rowBody.implicitHeight
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton
      cursorShape: Qt.PointingHandCursor
      enabled: !root.busy

      // Move the cursor here when the mouse enters; mouse leaving doesn't
      // clear it (so the cursor stays where the mouse last was and
      // subsequent j/k pick up from this row).
      onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index; root.wifiActionFocused = false }

      onClicked: {
        if (!row.net) return
        // Resync cursor in case keyboard nav moved it away while the mouse
        // stayed parked on this row — the click target is unambiguously here.
        root.cursorActive = true
        root.focusSection = "wifi"
        root.selectedIndex = row.index
        root.wifiActionFocused = false
        if (row.isConnected) {
          root.disconnectRow(row.net.ssid)
          return
        }
        if (row.requiresCredentials && !row.isKnown) {
          root.openPasswordPrompt(row.net.ssid)
          return
        }
        root.connectDirectly(row.net.ssid)
      }
    }

    Item {
      id: rowBody
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(networkIcon.implicitHeight, networkInfo.implicitHeight, rightAction.implicitHeight) + Style.spacing.rowPaddingX

      Text {
        id: networkIcon
        textFormat: Text.PlainText
        text: row.net ? Icons.glyph(Model.connectionIcon("wifi", row.net.signal,
          row.isConnected && root.kind === "wifi" ? root.connectivity : "")) : ""
        color: row.statusColor
        font.family: Icons.family
        font.pixelSize: Style.font.icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      // The right edge shows a lock for networks that require credentials and
      // reveals Forget on hover. Known passwordless networks show Forget
      // directly rather than reserving an invisible or misleading target.
      Item {
        id: rightAction
        visible: row.requiresCredentials || row.canForget
        width: Style.space(22)
        implicitHeight: lockIndicator.implicitHeight
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter

        Text {
          id: lockIndicator
          textFormat: Text.PlainText
          visible: row.requiresCredentials || row.forgetVisible
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignHCenter
          text: Icons.glyph(row.forgetVisible ? "ui.close.circle" : "system.lock")
          color: row.forgetVisible ? Commons.Color.status.error : Commons.Color.secondaryText(root.panelText, Commons.Color.popups.background)
          font.family: Icons.family
          font.pixelSize: Style.font.icon
        }

        BorderSurface {
          anchors.fill: parent
          visible: row.forgetFocused
          color: Style.hoverFillFor(Commons.Color.status.error, Commons.Color.status.error)
          borderSpec: Border.controlSpec("hover-cursor", Commons.Color.status.error, Commons.Color.status.error)
          radius: Style.cornerRadius

          FocusRing { shown: true }
          z: -1
        }

        MouseArea {
          id: rightMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          enabled: row.canForget && !root.busy
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onContainsMouseChanged: if (containsMouse) { root.cursorActive = true; root.focusSection = "wifi"; root.selectedIndex = row.index; root.wifiActionFocused = true }
          onClicked: if (row.net) root.forget(row.net)
        }

        PanelToolTip {
          visible: rightMouse.containsMouse || row.forgetFocused
          text: Commons.I18n.t("network.forgetNetwork")
          fontFamily: root.bar.fontFamily
        }
      }

      Column {
        id: networkInfo
        spacing: Style.space(1)
        anchors.left: networkIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: rightAction.visible ? rightAction.left : parent.right
        anchors.rightMargin: rightAction.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: row.net ? (row.net.ssid || Commons.I18n.t("network.hidden")) : ""
          color: root.panelText
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          textFormat: Text.PlainText
          // Signal strength is conveyed by the wifi-bars icon and the
          // right-edge glyph/buttons carry protection or forget affordances,
          // so the second line only carries action status (Connecting…,
          // Connected, Failed, etc.). Collapses to zero height when empty
          // so rows without status keep a tight one-line look.
          text: row.statusText
          visible: row.statusText !== ""
          height: visible ? implicitHeight : 0
          color: row.statusColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }
    }

    // Inline credentials prompt -- shown when we hit a protected network we
    // don't have saved credentials for, or when a connect fails because the
    // saved passphrase is wrong. Submitting (Enter or the check button) fires
    // connect; Esc cancels back to the row. A failure is explained under the
    // fields and stays until one of them is edited.
    Column {
      id: passwordPanel
      visible: row.isPasswordOpen
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: rowMouse.bottom
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      anchors.topMargin: Style.space(4)
      spacing: Style.space(4)
      bottomPadding: Style.spacing.rowGap / 2

      RowLayout {
        visible: row.isEnterprise && !row.isBusy
        width: parent.width
        spacing: Style.space(6)

        PromptLabel { visible: row.isEnterprise; text: Commons.I18n.t("network.identityLabel") }
        PromptField {
          id: idField
          placeholderText: Commons.I18n.t("network.identityPlaceholder")
          text: row.isPasswordOpen ? root.identityText : ""
          onAccepted: (domainField.visible ? domainField : pwField).forceActiveFocus()
          onTextChanged: if (row.isPasswordOpen && text !== root.identityText) { root.setIdentity(text); root.clearPromptFailure() }
        }
        // Keeps the fields' right edges in line with the password field's,
        // which has the connect button beside it.
        Item { Layout.preferredWidth: Style.spacing.actionButtonSize; implicitHeight: 1 }
      }

      RowLayout {
        visible: row.isEnterprise && !row.isBusy && !root.skipServerCheck
        width: parent.width
        spacing: Style.space(6)

        PromptLabel { visible: row.isEnterprise; text: Commons.I18n.t("network.domainLabel") }
        PromptField {
          id: domainField
          placeholderText: Commons.I18n.t("network.domainPlaceholder")
          text: row.isPasswordOpen ? root.domainText : ""
          onAccepted: pwField.forceActiveFocus()
          onTextChanged: if (row.isPasswordOpen && text !== root.domainText) {
            root.domainText = text
            root.domainEdited = true
            root.clearPromptFailure()
          }
        }
        Item { Layout.preferredWidth: Style.spacing.actionButtonSize; implicitHeight: 1 }
      }

      // The explicit choice to skip the server check, with what it risks
      // beside the commit.
      Text {
        visible: row.isEnterprise && !row.isBusy && root.skipServerCheck
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: Commons.I18n.t("network.skipServerCheckWarning")
        color: Commons.Color.status.warning
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      RowLayout {
        visible: !row.isBusy
        width: parent.width
        spacing: Style.space(6)

        PromptLabel { visible: row.isEnterprise; text: Commons.I18n.t("network.passwordLabel") }
        PromptField {
          id: pwField
          password: true
          placeholderText: row.isEnterprise ? "" : Commons.I18n.t("network.passphrase")
          text: row.isPasswordOpen ? root.passwordText : ""
          onAccepted: row.submitCredentials()
          onTextChanged: if (row.isPasswordOpen && text !== root.passwordText) { root.passwordText = text; root.clearPromptFailure() }
        }

        // 22×22, lined up with lockIndicator above. Esc closes the prompt, so
        // there's no separate cancel button.
        PanelActionButton {
          id: connectPwBtn
          Layout.alignment: Qt.AlignVCenter
          enabled: row.canSubmit
          iconText: Icons.glyph("ui.check")
          tooltipText: root.skipServerCheck && row.isEnterprise
            ? Commons.I18n.t("network.connectWithoutCheck") : Commons.I18n.t("network.connect")
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
          onClicked: row.submitCredentials()
        }
      }

      BorderSurface {
        visible: row.isBusy
        width: parent.width
        height: Style.spacing.controlHeight
        color: Style.normalFillFor(root.panelText)
        borderSpec: Border.controlSpec("normal", root.panelText, Commons.Color.accent)
        radius: Style.cornerRadius

        Text {
          textFormat: Text.PlainText
          anchors.fill: parent
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: Commons.I18n.t("network.connecting")
          color: root.panelText
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }

      Text {
        visible: row.isFailed && !row.isBusy
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: Model.promptFailureMessage(root.failureKind, row.isEnterprise, Commons.I18n.t)
        color: Commons.Color.status.error
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.bodySmall
      }

      Button {
        visible: row.offersSkipServerCheck && !row.isBusy
        text: root.skipServerCheck ? Commons.I18n.t("network.checkServer") : Commons.I18n.t("network.skipServerCheck")
        foreground: root.panelText
        fontFamily: root.bar.fontFamily
        fontSize: Style.font.bodySmall
        onClicked: {
          root.skipServerCheck = !root.skipServerCheck
          root.clearPromptFailure()
          pwField.forceActiveFocus()
        }
      }
    }
  }
}
