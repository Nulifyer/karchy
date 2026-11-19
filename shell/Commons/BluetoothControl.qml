pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import "BluetoothControlModel.js" as Model

// Bluetooth, once for the whole shell: the adapter, its devices, what is
// being done to them, the one pairing in progress and its question, and the
// scan. The bar's Bluetooth panel and Settings › Bluetooth both show and
// drive it through here, so a pairing started in one can be answered in the
// other and the scan has a single owner.
//
// A view calls scan(<its own key>) while it wants nearby devices found and
// stopScan() when it leaves; attend(<key>) while it shows the pairing
// question itself (unattended, the panel opens to ask it).
Singleton {
  id: root

  readonly property var adapter: Bluetooth.defaultAdapter
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property bool available: adapter !== null
  readonly property bool enabled: adapter !== null && adapter.enabled === true

  readonly property var deviceGroups: Model.deviceLists(devices)
  readonly property var connectedDevices: deviceGroups.connected || []
  readonly property var knownDevices: deviceGroups.known || []
  readonly property var discoveredDevices: deviceGroups.discovered || []

  function deviceForAddress(address) {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && devices[i].address === address) return devices[i]
    }
    return null
  }

  // ------------------------------------------------------------------- power

  // Not adapter.enabled: that writes BlueZ's Powered, which nothing persists, so
  // the adapter came back on at the next boot. karchy-bluetooth-power moves the
  // rfkill soft block instead, which systemd-rfkill restores across reboots.
  // Powered still follows the block, so a switch reads it as before.
  //
  // Asking for a direction rather than a toggle: the helper runs detached and the
  // switch only moves once BlueZ catches up, so a second click inside that window
  // would re-read the old state and undo the first.
  function togglePower() {
    if (!adapter) return
    Quickshell.execDetached(["karchy-bluetooth-power", adapter.enabled ? "off" : "on"])
  }

  // The name other devices see this computer under (BlueZ's alias, which it
  // keeps). The adapter's name is read-only in Quickshell, so bluetoothctl
  // sets it, on the default controller as `adapter` is.
  function rename(name) {
    var value = String(name || "").trim()
    if (!adapter || value === "" || value === adapter.name) return
    Quickshell.execDetached(["bluetoothctl", "system-alias", value])
  }

  // ---------------------------------------------------------------- scanning

  property var scanners: ({})
  readonly property bool scanWanted: Object.keys(scanners).length > 0
  // True while this shell owes BlueZ a StopDiscovery: set when it starts
  // discovery (or a view arrives onto a session already running) and cleared
  // once discovery is confirmed down. Ownership, not state: BlueZ's
  // Discovering property also reflects sessions other clients hold, which are
  // never the shell's to stop.
  property bool owesDiscoveryStop: false

  function scan(key) {
    if (scanners[key]) return
    // Adopt a discovery session that is already running, so the last view
    // to leave settles it either way.
    if (adapter !== null && adapter.discovering) owesDiscoveryStop = true
    var next = Object.assign({}, scanners)
    next[key] = true
    scanners = next
  }

  function stopScan(key) {
    if (!scanners[key]) return
    var next = Object.assign({}, scanners)
    delete next[key]
    scanners = next
  }

  // BlueZ rejects StartDiscovery while the adapter is still powering up, and
  // discovery can also time out on its own. While a view wants the scan, keep
  // nudging it back on so an enabled adapter is always scanning.
  Timer {
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.scanWanted && root.adapter !== null && root.adapter.enabled && !root.adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  // The way back down. The BlueZ discovery session behind adapter.discovering
  // is held by quickshell's D-Bus connection, so nothing ends it when a view
  // closes: without this timer, one visit left the radio in inquiry until the
  // next shell restart, starving A2DP audio on the same controller into
  // stutters.
  //
  // A timer bound to the confirmed state rather than a write at close time:
  // quickshell only forwards a discovering write that differs from the last
  // state BlueZ reported, so a stop issued while a just-fired StartDiscovery
  // is still awaiting confirmation would be swallowed and leak the session.
  // Binding to adapter.discovering means a confirmation landing at any point
  // after the last view left re-arms the stop, and a view arriving inside the
  // first interval keeps the scan running uninterrupted. Attempts are bounded
  // so a session some other BlueZ client keeps up cannot draw StopDiscovery
  // fire forever.
  Timer {
    interval: 1000
    repeat: true
    property int attempts: 0
    running: !root.scanWanted && root.owesDiscoveryStop && root.adapter !== null && root.adapter.discovering === true
    onRunningChanged: if (running) attempts = 0
    onTriggered: {
      attempts += 1
      if (attempts > 3) { root.owesDiscoveryStop = false; return }
      root.adapter.discovering = false
    }
  }

  // The debt is settled the moment BlueZ reports discovery down, whether
  // because the stop above landed or the session ended some other way, so a
  // stale claim never touches a scan another client starts later. While a
  // view wants the scan, the retry above re-incurs it as it restarts.
  Connections {
    target: root.adapter
    function onDiscoveringChanged() {
      if (!root.adapter.discovering) root.owesDiscoveryStop = false
    }
  }

  // ----------------------------------------------------------- device actions

  // Address -> "connecting" | "disconnecting" | "forgetting".
  // The actual Bluetooth sequencing lives in bin/karchy-bluetooth-device;
  // this map only keeps the views responsive while BlueZ catches up.
  property var pendingActions: ({})

  function pendingAction(address) {
    return Model.pendingAction(pendingActions, address)
  }

  function setPendingAction(address, action) {
    if (!address) return
    pendingActions = Model.withPendingAction(pendingActions, address, action)
    if (action) pendingTimeout.restart()
  }

  function deviceCommand(action, address) {
    return ["karchy-bluetooth-device", action, address]
  }

  function runDeviceAction(device, action, pending) {
    if (!device || !device.address) return
    setPendingAction(device.address, pending)
    Quickshell.execDetached(deviceCommand(action, device.address))
  }

  function connectDevice(device) {
    if (!device || device.connected) return
    if (device.paired || device.bonded || device.trusted) runDeviceAction(device, "connect", "connecting")
    else startPairing(device)
  }

  function disconnectDevice(device) {
    if (!device || !device.address) return
    if (!device.connected) return
    setPendingAction(device.address, "disconnecting")
    if (device.disconnect) device.disconnect()
    Quickshell.execDetached(deviceCommand("disconnect", device.address))
  }

  function forgetDevice(device) {
    if (!device || !device.address) return
    runDeviceAction(device, "forget", "forgetting")
  }

  // A trusted device may connect by itself when it comes in range; BlueZ
  // keeps the choice with the pairing.
  function setTrusted(device, trusted) {
    if (device) device.trusted = trusted
  }

  function syncPendingActions() {
    var next = Model.cloneMap(pendingActions)
    var changed = false

    for (var address in next) {
      var action = next[address]
      var found = deviceForAddress(address)

      var finishedConnecting = action === "connecting" && found && found.connected
      if (finishedConnecting
          || (action === "disconnecting" && found && !found.connected)
          || (action === "forgetting" && (!found || (!found.paired && !found.bonded && !found.trusted)))) {
        if (finishedConnecting) scheduleAudioOutputSwitch(found)
        delete next[address]
        changed = true
      }
    }

    if (changed) pendingActions = next
  }

  onConnectedDevicesChanged: syncPendingActions()
  onKnownDevicesChanged: syncPendingActions()
  onDiscoveredDevicesChanged: syncPendingActions()

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.pendingActions = ({})
  }

  // ----------------------------------------------------------------- pairing

  // Pairing runs one device at a time, in karchy-bluetooth-device pair, which
  // stays up until the device is connected or the pairing failed. A device
  // that wants a code asks through it: each question is a line on its stdout
  // (Model.parsePairEvent) and the answer goes to its stdin.
  property string pairingAddress: ""
  property string pairingName: ""
  property bool pairingPaired: false
  // { kind, code } while a question is open, else null.
  property var pairingQuestion: null
  property string pairingAnswerText: ""
  // Why the last pairing failed, shown on that device's row for a while.
  property string pairFailureAddress: ""
  property string pairFailureText: ""

  // The device waits for the answer, so the question has to reach the
  // person: a view that is on screen and shows it attends; with none, the
  // panel opens on this signal.
  signal questionAsked()
  property var attendants: ({})
  readonly property bool attended: Object.keys(attendants).length > 0

  function attend(key) {
    if (attendants[key]) return
    var next = Object.assign({}, attendants)
    next[key] = true
    attendants = next
  }

  function leave(key) {
    if (!attendants[key]) return
    var next = Object.assign({}, attendants)
    delete next[key]
    attendants = next
  }

  function startPairing(device) {
    if (!device || !device.address || pairProc.running) return
    pairingAddress = device.address
    pairingName = Model.deviceLabel(device)
    pairingPaired = false
    pairingQuestion = null
    pairFailureAddress = ""
    pairFailureText = ""
    pairProc.command = deviceCommand("pair", device.address)
    pairProc.running = true
  }

  function handlePairEvent(line) {
    var event = Model.parsePairEvent(line)
    if (!event) return

    if (event.type === "question") {
      pairingAnswerText = ""
      pairingQuestion = { kind: event.kind, code: event.code }
      root.questionAsked()
      return
    }

    pairingQuestion = null
    if (event.type === "paired") {
      pairingPaired = true
    } else if (event.type === "connected") {
      scheduleAudioOutputSwitch(deviceForAddress(pairingAddress))
    } else if (event.type === "failed") {
      pairFailureAddress = pairingAddress
      pairFailureText = Model.pairFailureText(event.reason, I18n.t)
      if (pairFailureText !== "") pairFailureClear.restart()
    }
  }

  function answerPairing(text) {
    if (!pairProc.running) return
    pairProc.write(text + "\n")
    pairingQuestion = null
  }

  function submitPairingText() {
    if (!pairingQuestion) return
    var answer = Model.pairTypedAnswer(pairingQuestion.kind, pairingAnswerText)
    if (answer !== "") answerPairing(answer)
  }

  // Enter and Escape while a question is open. A code that is only read
  // (typed on the device) has nothing to accept; Escape gives the pairing up.
  function acceptPairingQuestion() {
    if (!pairingQuestion) return
    if (pairingQuestion.kind === "confirm") answerPairing("yes")
    else if (Model.pairQuestionTyped(pairingQuestion.kind)) submitPairingText()
  }

  function declinePairingQuestion() {
    if (!pairingQuestion) return
    answerPairing(pairingQuestion.kind === "confirm" ? "no" : "cancel")
  }

  function pairingEnded() {
    pairingQuestion = null
    pairingAddress = ""
    pairingName = ""
    pairingPaired = false
  }

  Process {
    id: pairProc
    stdinEnabled: true
    stdout: SplitParser {
      onRead: function(line) { root.handlePairEvent(line) }
    }
    onExited: root.pairingEnded()
  }

  Timer {
    id: pairFailureClear
    interval: 10000
    repeat: false
    onTriggered: {
      root.pairFailureAddress = ""
      root.pairFailureText = ""
    }
  }

  // ------------------------------------------------- sound to a new headset

  // A headset or speaker that has just connected becomes the output: its
  // PipeWire sink appears a moment after BlueZ reports the connection.
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  property var pendingAudioOutputDevice: null
  property int pendingAudioOutputAttempts: 0

  function bluetoothAudioSink(device) {
    for (var i = 0; i < pipewireNodes.length; i++) {
      var node = pipewireNodes[i]
      if (node && node.isSink && !node.isStream && Model.bluetoothSinkMatchesDevice(node, device)) return node
    }
    return null
  }

  function scheduleAudioOutputSwitch(device) {
    pendingAudioOutputDevice = {
      address: device && device.address ? device.address : "",
      name: device && device.name ? device.name : "",
      deviceName: device && device.deviceName ? device.deviceName : ""
    }
    pendingAudioOutputAttempts = 0
    audioSwitchTimer.restart()
  }

  function switchPendingAudioOutput() {
    if (!pendingAudioOutputDevice) return

    var sink = bluetoothAudioSink(pendingAudioOutputDevice)
    if (sink) {
      AudioControl.setDefaultSink(sink)
      pendingAudioOutputDevice = null
      audioSwitchTimer.stop()
      return
    }

    pendingAudioOutputAttempts += 1
    if (pendingAudioOutputAttempts >= 8) {
      pendingAudioOutputDevice = null
      return
    }
    audioSwitchTimer.restart()
  }

  Timer {
    id: audioSwitchTimer
    interval: 500
    repeat: false
    onTriggered: root.switchPendingAudioOutput()
  }
}
