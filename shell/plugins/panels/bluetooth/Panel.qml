import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "Model.js" as Model

Panel {
  id: root
  moduleName: "karchy.bluetooth"
  ipcTarget: "karchy.bluetooth"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleBluetooth method below.
  manageIpc: false

  // Address -> "connecting" | "disconnecting" | "forgetting".
  // The actual Bluetooth sequencing lives in bin/karchy-bluetooth-device;
  // this map only keeps the panel responsive while BlueZ catches up.
  property var pendingActions: ({})

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

  readonly property var adapter: Bluetooth.defaultAdapter

  // True while this instance owes BlueZ a StopDiscovery: set when it starts
  // discovery (or opens onto a session already running) and cleared once
  // discovery is confirmed down after close. Ownership, not state — BlueZ's
  // Discovering property also reflects sessions other clients hold, which are
  // never this panel's to stop.
  property bool owesDiscoveryStop: false
  readonly property var devices: Bluetooth.devices ? Bluetooth.devices.values : []
  readonly property var pipewireNodes: Pipewire.nodes ? Pipewire.nodes.values : []
  property var pendingAudioOutputDevice: null
  property int pendingAudioOutputAttempts: 0

  function deviceLabel(device) {
    return Model.deviceLabel(device)
  }

  function isUuidLike(value) {
    return Model.isUuidLike(value)
  }

  function isAddressLike(value) {
    return Model.isAddressLike(value)
  }

  function hasHumanName(device) {
    return Model.hasHumanName(device)
  }

  readonly property var deviceGroups: Model.deviceLists(devices)
  readonly property var connectedDevices: deviceGroups.connected || []
  readonly property var knownDevices: deviceGroups.known || []
  readonly property var discoveredDevices: deviceGroups.discovered || []

  readonly property string icon: {
    // No adapter reads like switched off, so the header keeps its shape.
    if (!adapter || !adapter.enabled) return Icons.glyph("bluetooth.off")
    if (connectedDevices.length > 0) return Icons.glyph("bluetooth.connected")
    return Icons.glyph("bluetooth")
  }

  // The real state, not a rotating phrase (the network panel says the same
  // kind of thing): searching, what's connected, or simply on.
  readonly property string heroStatusText: {
    if (!adapter) return Commons.I18n.t("bluetooth.noAdapter")
    if (!adapter.enabled) return Commons.I18n.t("bluetooth.turnedOff")
    if (connectedDevices.length === 1) {
      var only = connectedDevices[0]
      return "Connected to " + (only.name || only.deviceName || only.address || "a device")
    }
    if (connectedDevices.length > 1) return connectedDevices.length + " devices connected"
    if (adapter.discovering) return "Searching for devices"
    return "On"
  }

  // Single cursor model shared by keyboard and mouse. Sections:
  //   "connected"  — currently connected devices; Enter disconnects.
  //   "known"      — remembered devices; Enter connects.
  //   "discovered" — unremembered devices visible while scanning; Enter connects.
  // Visuals always come from CursorSurface (hasCursor / current),
  // never from containsMouse. Mouse hover updates root cursor state too,
  // guaranteeing one highlight on screen.
  property string focusSection: "connected"
  property int selectedIndex: 0
  property bool actionFocused: false
  property bool cursorActive: false

  // Stable identity for the focused device. Devices move between sections as
  // they connect, disconnect, pair, or get forgotten, so follow the BlueZ
  // address across section changes instead of preserving a stale row index.
  property string focusedDeviceAddress: ""

  // "header" is a virtual section for the hero Bluetooth on/off toggle; it
  // sits above the device sections so the adapter can be toggled by keyboard
  // even when it is off and no device rows exist.
  readonly property bool headerHasCursor: cursorActive && focusSection === "header"
  readonly property string toggleHint: root.adapter && root.adapter.enabled ? Commons.I18n.t("bluetooth.turnOff") : Commons.I18n.t("bluetooth.turnOn")

  readonly property color hoverFill: bar
    ? Style.hoverFillFor(panelText, Commons.Color.accent)
    : "transparent"
  readonly property color selectedFill: bar
    ? Style.selectedFillFor(panelText, Commons.Color.accent)
    : "transparent"

  function sectionCount(section) {
    if (section === "connected") return connectedDevices.length
    if (section === "known") return knownDevices.length
    if (section === "discovered") return discoveredDevices.length
    return 0
  }

  function sectionVisible(section) {
    if (section === "connected") return connectedDevices.length > 0
    if (section === "known") return knownDevices.length > 0
    if (section === "discovered") return adapter && adapter.discovering && discoveredDevices.length > 0
    return false
  }

  readonly property var visibleSections: {
    return Model.visibleSections(deviceGroups, adapter && adapter.discovering)
  }

  function devicesForSection(section) {
    return Model.sectionDevices(deviceGroups, section)
  }

  // The scrollable half of the panel — remembered devices, then whatever the
  // scan turned up — flattened into one model so a ListView can own the
  // viewport. Each entry carries the section it came from, which is what lets
  // the delegate and the cursor keep working in section-relative terms.
  readonly property var scrollRows: {
    var rows = []
    for (var k = 0; k < knownDevices.length; k++)
      rows.push({ dev: Model.deviceRow(knownDevices[k]), section: "known", indexInSection: k })
    if (sectionVisible("discovered"))
      for (var d = 0; d < discoveredDevices.length; d++)
        rows.push({ dev: Model.deviceRow(discoveredDevices[d]), section: "discovered", indexInSection: d })
    return rows
  }

  // Connected devices render above the scroll area; same primitives-only
  // projection so those delegates never hold Device QObject wrappers either.
  readonly property var connectedRows: {
    var rows = []
    for (var i = 0; i < connectedDevices.length; i++)
      rows.push(Model.deviceRow(connectedDevices[i]))
    return rows
  }

  // Live BlueZ device behind a row. Rows carry primitives only, so actions
  // resolve the backend object here rather than holding a wrapper that can
  // dangle mid-incubation. `devices` is already the raw device array (see the
  // property declaration), so it is iterated directly.
  function deviceFor(row) {
    if (!row || !row.dev) return null
    var addr = row.dev.address || ""
    var devs = devices || []
    for (var i = 0; i < devs.length; i++) {
      if ((devs[i].address || "") === addr) return devs[i]
    }
    return null
  }

  // Flat position of the keyboard cursor, or -1 while it sits on the hero or
  // in the connected list (both of which live outside the scroll area).
  readonly property int scrollRowIndex: {
    if (focusSection !== "known" && focusSection !== "discovered") return -1
    for (var i = 0; i < scrollRows.length; i++)
      if (scrollRows[i].section === focusSection && scrollRows[i].indexInSection === selectedIndex) return i
    return -1
  }

  // A row opens a section when it is the first of its kind in the flat list.
  function scrollSectionTitle(index) {
    var rows = scrollRows
    if (index < 0 || index >= rows.length) return ""
    if (index > 0 && rows[index - 1].section === rows[index].section) return ""
    return rows[index].section === "known" ? Commons.I18n.t("bluetooth.paired") : Commons.I18n.t("bluetooth.available")
  }

  function audioSinks() {
    var sinks = []
    for (var i = 0; i < pipewireNodes.length; i++) {
      var node = pipewireNodes[i]
      if (node && node.isSink && !node.isStream) sinks.push(node)
    }
    return sinks
  }

  function bluetoothAudioSink(device) {
    var sinks = audioSinks()
    for (var i = 0; i < sinks.length; i++) {
      if (Model.bluetoothSinkMatchesDevice(sinks[i], device)) return sinks[i]
    }
    return null
  }

  function setDefaultAudioSink(sink) {
    if (!sink) return
    Pipewire.preferredDefaultAudioSink = sink
    if (sink.id !== undefined && sink.name) {
      Quickshell.execDetached([
        "karchy-audio-output-set-default",
        String(sink.id),
        String(sink.name)
      ])
    }
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
      setDefaultAudioSink(sink)
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

  function deviceAt(section, index) {
    var list = devicesForSection(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  function cloneMap(map) {
    return Model.cloneMap(map)
  }

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

  function startPairing(device) {
    if (!device || !device.address || pairProc.running) return
    pairingAddress = device.address
    pairingName = deviceLabel(device)
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
      // The device waits for the answer, so bring the question to the person.
      if (!opened) open()
      return
    }

    pairingQuestion = null
    if (event.type === "paired") {
      pairingPaired = true
    } else if (event.type === "connected") {
      scheduleAudioOutputSwitch(deviceForAddress(pairingAddress))
    } else if (event.type === "failed") {
      pairFailureAddress = pairingAddress
      pairFailureText = Model.pairFailureText(event.reason, Commons.I18n.t)
      if (pairFailureText !== "") pairFailureClear.restart()
    }
  }

  function deviceForAddress(address) {
    for (var i = 0; i < devices.length; i++) {
      if (devices[i] && devices[i].address === address) return devices[i]
    }
    return null
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

  function syncPendingActions() {
    var next = cloneMap(pendingActions)
    var changed = false

    for (var address in next) {
      var action = next[address]
      var found = null

      for (var i = 0; i < devices.length; i++) {
        var d = devices[i]
        if (d && d.address === address) {
          found = d
          break
        }
      }

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

  // j/k navigates the hero toggle ("header") and the device sections
  // row-by-row.
  function moveCursor(delta) {
    var sections = visibleSections
    if (focusSection === "header") {
      if (delta > 0 && sections && sections.length > 0) {
        focusSection = sections[0]; selectedIndex = 0; actionFocused = false
      }
      return
    }
    if (!sections || sections.length === 0) { focusSection = "header"; actionFocused = false; return }
    var sIdx = sections.indexOf(focusSection)
    if (sIdx < 0) { focusSection = sections[0]; selectedIndex = 0; actionFocused = false; return }

    var idx = selectedIndex
    var max = sectionCount(focusSection) - 1

    if (delta > 0) {
      if (idx < max) { selectedIndex = idx + 1; actionFocused = false; return }
      if (sIdx < sections.length - 1) {
        focusSection = sections[sIdx + 1]
        selectedIndex = 0
        actionFocused = false
      }
    } else {
      if (idx > 0) { selectedIndex = idx - 1; actionFocused = false; return }
      if (sIdx > 0) {
        focusSection = sections[sIdx - 1]
        selectedIndex = sectionCount(focusSection) - 1
        actionFocused = false
      } else {
        focusSection = "header"; actionFocused = false
      }
    }
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
    actionFocused = false
  }

  function moveCursorH(delta) {
    if (!cursorActive) { cursorActive = true; return }
    if (focusSection !== "known" && focusSection !== "connected") return
    var dev = deviceAt(focusSection, selectedIndex)
    if (!dev || !dev.address) return
    if (delta > 0) actionFocused = true
    else if (delta < 0) actionFocused = false
  }

  function activateCursor() {
    if (focusSection === "header") {
      toggleBluetooth()
      return
    }
    if (actionFocused) {
      deleteSelected()
      return
    }

    if (focusSection === "connected" || focusSection === "known") {
      var dev = deviceAt(focusSection, selectedIndex)
      if (!dev) return
      if (dev.connected) disconnectDevice(dev)
      else connectDevice(dev)
      return
    }
    if (focusSection === "discovered") {
      var d = discoveredDevices[selectedIndex]
      if (!d) return
      connectDevice(d)
    }
  }

  // 'x' forgets remembered devices. For connected devices this first
  // disconnects, then removes the BlueZ pairing record via karchy-bluetooth-device.
  function deleteSelected() {
    if (focusSection !== "known" && focusSection !== "connected") return
    var dev = deviceAt(focusSection, selectedIndex)
    if (!dev) return
    forgetDevice(dev)
  }

  onOpenedChanged: {
    if (opened) {
      // Adopt a discovery session that is already running — a popout handoff
      // from another monitor, or one leaked by an instance that could not
      // finish its own stop — so this close settles it either way.
      if (adapter !== null && adapter.discovering) owesDiscoveryStop = true
      if (connectedDevices.length > 0) { focusSection = "connected"; selectedIndex = 0 }
      else if (knownDevices.length > 0) { focusSection = "known"; selectedIndex = 0 }
      else if (discoveredDevices.length > 0) { focusSection = "discovered"; selectedIndex = 0 }
      else { focusSection = "header" }
      actionFocused = false
      cursorActive = false
    }
  }

  // Another per-monitor instance of this widget whose panel is open, if any.
  // All instances share the default adapter, and switching the popout to a
  // different monitor closes one instance as it opens the next, so the
  // closing side has to leave the scan alone for the side still on screen.
  function openSibling() {
    if (!bar || typeof bar.moduleWidgets !== "function") return null
    var items = bar.moduleWidgets(moduleName)
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root && items[i].opened === true) return items[i]
    }
    return null
  }

  function updateFocusedAddress() {
    var d = deviceAt(focusSection, selectedIndex)
    focusedDeviceAddress = d ? (d.address || "") : ""
  }

  function reselectFocusedDevice() {
    if (focusedDeviceAddress === "") {
      clampCursor()
      return
    }

    var sections = ["connected", "known", "discovered"]
    for (var s = 0; s < sections.length; s++) {
      var section = sections[s]
      if (!sectionVisible(section)) continue
      var list = devicesForSection(section)
      for (var i = 0; i < list.length; i++) {
        if (list[i] && list[i].address === focusedDeviceAddress) {
          focusSection = section
          selectedIndex = i
          clampCursor()
          return
        }
      }
    }

    clampCursor()
  }

  onSelectedIndexChanged: updateFocusedAddress()
  onFocusSectionChanged: updateFocusedAddress()
  onConnectedDevicesChanged: { reselectFocusedDevice(); syncPendingActions() }
  onKnownDevicesChanged: { reselectFocusedDevice(); syncPendingActions() }
  onDiscoveredDevicesChanged: { reselectFocusedDevice(); syncPendingActions() }
  onVisibleSectionsChanged: clampCursor()

  function clampCursor() {
    var sections = visibleSections
    // "header" is virtual and never appears in visibleSections, so it has to
    // be let through: toggling the adapter empties and refills the device
    // lists, and clamping would knock the cursor off the hero switch every
    // time it is used.
    if (focusSection === "header") return
    if (!sections || !sections.length) {
      selectedIndex = 0
      return
    }
    if (sections.indexOf(focusSection) < 0) {
      focusSection = sections[0]
      selectedIndex = 0
      return
    }
    var count = sectionCount(focusSection)
    if (count === 0) {
      // Section emptied out — bounce to the previous visible one.
      var sIdx = sections.indexOf(focusSection)
      focusSection = sIdx > 0 ? sections[sIdx - 1] : sections[0]
      selectedIndex = Math.max(0, sectionCount(focusSection) - 1)
      return
    }
    if (selectedIndex > count - 1) selectedIndex = count - 1
    if (selectedIndex < 0) selectedIndex = 0
  }

  visible: adapter !== null
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // BlueZ rejects StartDiscovery while the adapter is still powering up, and
  // discovery can also time out on its own. While the panel is open, keep
  // nudging it back on so an enabled adapter is always scanning.
  Timer {
    id: discoveryRetry
    interval: 1000
    repeat: true
    triggeredOnStart: true
    running: root.opened && root.adapter !== null && root.adapter.enabled && !root.adapter.discovering
    onTriggered: {
      root.owesDiscoveryStop = true
      root.adapter.discovering = true
    }
  }

  // The way back down. The BlueZ discovery session behind adapter.discovering
  // is held by quickshell's D-Bus connection, so nothing ends it at close:
  // without this timer, one visit to the panel left the radio in inquiry
  // until the next shell restart, starving A2DP audio on the same controller
  // into stutters.
  //
  // A timer bound to the confirmed state rather than a write at close time:
  // quickshell only forwards a discovering write that differs from the last
  // state BlueZ reported, so a stop issued while a just-fired StartDiscovery
  // is still awaiting confirmation would be swallowed and leak the session.
  // Binding to adapter.discovering means a confirmation landing at any point
  // after close re-arms the stop, and a reopen inside the first interval
  // keeps the scan running uninterrupted. Attempts are bounded so a session
  // some other BlueZ client keeps up cannot draw StopDiscovery fire forever.
  Timer {
    id: discoveryStop
    interval: 1000
    repeat: true
    property int attempts: 0
    running: !root.opened && root.owesDiscoveryStop && root.adapter !== null && root.adapter.discovering === true
    onRunningChanged: if (running) attempts = 0
    onTriggered: {
      // The scan now serves the open panel, so the debt moves with it — B may
      // have opened before BlueZ confirmed A's start, in which case B's own
      // open-time adoption saw nothing to adopt.
      var sibling = root.openSibling()
      if (sibling) {
        sibling.owesDiscoveryStop = true
        root.owesDiscoveryStop = false
        return
      }
      attempts += 1
      if (attempts > 3) { root.owesDiscoveryStop = false; return }
      root.adapter.discovering = false
    }
  }

  // The debt is settled the moment BlueZ reports discovery down — whether
  // because the stop above landed or the session ended some other way — so a
  // stale claim never touches a scan another client starts later. While the
  // panel is open, discoveryRetry re-incurs it as it restarts the scan.
  Connections {
    target: root.adapter
    function onDiscoveringChanged() {
      if (!root.adapter.discovering) root.owesDiscoveryStop = false
    }
  }

  // A destroyed instance cannot wait for BlueZ confirmations, so it hands any
  // debt to a surviving sibling — whose declarative stop catches even a start
  // confirmed after this object is gone — and only writes the stop directly
  // when it is the last one standing.
  Component.onDestruction: {
    if (!owesDiscoveryStop) return
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : []
    for (var i = 0; i < items.length; i++) {
      if (items[i] && items[i] !== root) { items[i].owesDiscoveryStop = true; return }
    }
    if (adapter !== null && adapter.discovering) adapter.discovering = false
  }

  Timer {
    id: pendingTimeout
    interval: 20000
    repeat: false
    onTriggered: root.pendingActions = ({})
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

  Timer {
    id: audioSwitchTimer
    interval: 500
    repeat: false
    onTriggered: root.switchPendingAudioOutput()
  }

  // Not adapter.enabled: that writes BlueZ's Powered, which nothing persists, so
  // the adapter came back on at the next boot. karchy-bluetooth-power moves the
  // rfkill soft block instead, which systemd-rfkill restores across reboots.
  // Powered still follows the block, so the switch and icon read it as before.
  //
  // Asking for a direction rather than a toggle: the helper runs detached and the
  // switch only moves once BlueZ catches up, so a second click inside that window
  // would re-read the old state and undo the first.
  function toggleBluetooth() {
    if (!adapter) return
    Quickshell.execDetached(["karchy-bluetooth-power", adapter.enabled ? "off" : "on"])
  }

  ShellIpc {
    target: "karchy.bluetooth"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
    function toggleBluetooth() { root.toggleBluetooth() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleBluetooth()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      property alias heroStatus: hero
      implicitHeight: column.implicitHeight
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveCursorH(dx)
      }
      // A typed answer (a PIN) takes the keys. Otherwise an open question
      // owns Enter and Escape: yes and no, or giving the pairing up.
      blocked: pairAnswer.activeFocus
      onActivateRequested: {
        if (root.pairingQuestion) root.acceptPairingQuestion()
        else if (root.cursorActive) root.activateCursor()
      }
      onCloseRequested: {
        if (root.pairingQuestion) root.declinePairingQuestion()
        else root.close()
      }
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onDeleteRequested: if (root.cursorActive && !root.pairingQuestion) root.deleteSelected()
      onTextKey: function(t) {
        if (root.pairingQuestion) {
          if (root.pairingQuestion.kind !== "confirm") return
          if (t === "y" || t === "Y") root.answerPairing("yes")
          else if (t === "n" || t === "N") root.answerPairing("no")
          return
        }
        if (t === "b" || t === "B") root.toggleBluetooth()
      }

      Column {
        id: column
        anchors.fill: parent
        spacing: Style.space(14)

        // ---------- Hero: Bluetooth icon · status · power switch ----------
        // Status only on the left; the switch owns toggling, mouse and
        // keyboard alike, and is the header's only cursor target.
        PanelHero {
          id: hero
          iconText: root.icon
          iconColor: root.adapter && root.adapter.enabled ? root.panelText : Commons.Color.secondaryText(root.panelText, root.panelSurface)
          title: Commons.I18n.t("bluetooth.title")
          meta: root.heroStatusText
          fontFamily: root.bar.fontFamily
          trailingControl: Component {
            ToggleSwitch {
              id: powerSwitch
              visible: !!root.adapter
              checked: !!root.adapter && root.adapter.enabled
              hasCursor: root.headerHasCursor
              foreground: root.panelText
              accessibleName: Commons.I18n.t("bluetooth.title")
              onHovered: function(on) { if (on) root.setHeaderCursor() }
              onToggled: root.toggleBluetooth()

              PanelToolTip {
                visible: powerSwitch.containsMouse
                text: root.toggleHint
                fontFamily: root.bar.fontFamily
              }
            }
          }
        }

        // Scrollable device list — capped so a noisy neighborhood doesn't
        // grow the popup past the screen.
        PanelSeparator {
          foreground: root.panelText
        }

        // ---------- The code a device wants checked, shown or entered ----------
        Column {
          id: pairCard
          readonly property string kind: root.pairingQuestion ? root.pairingQuestion.kind : ""
          readonly property bool typed: Model.pairQuestionTyped(kind)

          visible: root.pairingQuestion !== null
          width: parent.width
          spacing: Style.space(10)

          // The field takes the keyboard for a typed answer and hands it
          // back to the panel when the question is over. A question can also
          // be what opened the panel, which focuses the panel itself.
          function placeFocus() {
            Qt.callLater(function() {
              if (pairCard.typed) pairAnswer.forceActiveFocus()
              else keyCatcher.forceActiveFocus()
            })
          }
          onTypedChanged: placeFocus()
          Component.onCompleted: if (typed) placeFocus()
          Connections {
            target: root
            function onOpenedChanged() { if (root.opened && pairCard.typed) pairCard.placeFocus() }
          }

          Text {
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: Model.pairQuestionText(pairCard.kind, root.pairingName || Commons.I18n.t("bluetooth.device"), Commons.I18n.t)
            color: root.panelText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            visible: !pairCard.typed
            width: parent.width
            textFormat: Text.PlainText
            horizontalAlignment: Text.AlignHCenter
            text: root.pairingQuestion ? root.pairingQuestion.code : ""
            color: root.panelText
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.display
            font.letterSpacing: Style.space(4)
          }

          TextField {
            id: pairAnswer
            visible: pairCard.typed
            width: parent.width
            foreground: root.panelText
            font.family: root.bar.fontFamily
            inputMethodHints: pairCard.kind === "enter-passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
            text: root.pairingAnswerText
            onTextChanged: if (text !== root.pairingAnswerText) root.pairingAnswerText = text
            onAccepted: root.submitPairingText()
            Keys.onEscapePressed: root.declinePairingQuestion()
          }

          Text {
            visible: pairCard.kind === "enter-pin"
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: Commons.I18n.t("bluetooth.pairEnterPinHint")
            color: Commons.Color.secondaryText(root.panelText, root.panelSurface)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Row {
            spacing: Style.space(8)

            Button {
              visible: pairCard.kind === "confirm" || pairCard.typed
              enabled: !pairCard.typed || Model.pairTypedAnswer(pairCard.kind, root.pairingAnswerText) !== ""
              text: pairCard.typed ? Commons.I18n.t("bluetooth.pairSubmit") : Commons.I18n.t("bluetooth.pairConfirmYes")
              variant: "primary"
              bordered: true
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              onClicked: root.acceptPairingQuestion()
            }

            Button {
              text: pairCard.kind === "confirm" ? Commons.I18n.t("bluetooth.pairConfirmNo") : Commons.I18n.t("bluetooth.pairCancel")
              bordered: true
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              onClicked: root.declinePairingQuestion()
            }
          }

          PanelSeparator {
            foreground: root.panelText
          }
        }

        Column {
          id: connectedList
          visible: root.connectedDevices.length > 0
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: Commons.I18n.t("bluetooth.connected")
            foreground: root.panelText
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.connectedRows
            DeviceRow {
              required property var modelData
              required property int index
              width: connectedList.width
              dev: modelData
              rowIndex: index
              sectionName: "connected"
              isDiscovered: false
            }
          }
        }

        PanelSeparator {
          visible: root.connectedDevices.length > 0 && root.scrollRows.length > 0
          foreground: root.panelText
        }

        // ListView, not a Flickable: it owns the scroll position, so it keeps
        // the current row visible on j/k, re-clamps itself when discovery
        // shortens the list, and — because Contain only moves when a row is
        // actually clipped — never lurches under a hovering mouse.
        ListView {
          id: deviceListView
          width: parent.width
          height: Math.min(contentHeight, Style.space(400))
          spacing: Style.space(10)
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          model: root.scrollRows
          currentIndex: root.scrollRowIndex
          // Deferred by a turn. Called straight out of the signal the position
          // does not take — verified with the cursor six rows down and
          // contentY still 0 — because scrollRows is rebuilt every time
          // discovery reports, and swapping the model resets the view out from
          // under the call. Network's list is stable enough not to need this.
          onCurrentIndexChanged: if (currentIndex >= 0) Qt.callLater(keepCurrentVisible)
          function keepCurrentVisible() {
            if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Contain)
          }

          delegate: Item {
            required property var modelData
            required property int index
            readonly property string sectionTitle: root.scrollSectionTitle(index)

            width: ListView.view.width
            height: delegateColumn.implicitHeight

            Column {
              id: delegateColumn
              width: parent.width
              spacing: Style.space(10)

              PanelSeparator {
                visible: index > 0 && sectionTitle !== ""
                height: visible ? implicitHeight : 0
                foreground: root.panelText
              }

              PanelSectionHeader {
                visible: sectionTitle !== ""
                height: visible ? implicitHeight : 0
                text: sectionTitle
                foreground: root.panelText
                fontFamily: root.bar.fontFamily
              }

              DeviceRow {
                width: parent.width
                dev: modelData.dev
                rowIndex: modelData.indexInSection
                sectionName: modelData.section
                isDiscovered: modelData.section === "discovered"
              }
            }
          }
        }

        // Why the list is empty, and the next step when there is one. With
        // no adapter the hero already says so; this says what to do.
        EmptyState {
          visible: root.connectedDevices.length === 0 && root.scrollRows.length === 0
          width: parent.width
          iconName: !root.adapter || !root.adapter.enabled ? "bluetooth.off" : "bluetooth"
          title: !root.adapter ? Commons.I18n.t("bluetooth.noBluetoothAdapter")
            : !root.adapter.enabled ? Commons.I18n.t("bluetooth.turnOnToScan")
            : Commons.I18n.t("bluetooth.scanning")
          body: !root.adapter ? Commons.I18n.t("bluetooth.noAdapterHint") : ""
          actionText: root.adapter && !root.adapter.enabled ? Commons.I18n.t("bluetooth.turnOn") : ""
          foreground: root.panelText
          surface: root.panelSurface
          fontFamily: root.bar.fontFamily
          onAction: root.toggleBluetooth()
        }
      }
    }
  }

  // Two-line device row showing name + live status. Pending state is owned
  // by the panel so it survives rows moving between sections.
  component DeviceRow: CursorSurface {
    id: row
    required property var dev
    required property int rowIndex
    required property string sectionName
    required property bool isDiscovered

    readonly property bool isConnected: dev && dev.connected
    readonly property int devState: dev && dev.state !== undefined ? dev.state : -1
    readonly property string action: root.pendingAction(dev ? dev.address : "")
    readonly property string actionTooltip: {
      if (!dev) return ""
      if (isConnected) return Commons.I18n.t("bluetooth.disconnect")
      if (isDiscovered) return Commons.I18n.t("bluetooth.pair")
      return Commons.I18n.t("bluetooth.connect")
    }

    readonly property bool rowSelected: root.cursorActive && root.focusSection === sectionName && root.selectedIndex === rowIndex
    readonly property bool forgetAvailable: (sectionName === "known" || sectionName === "connected") && !isDiscovered
    readonly property bool showForgetButton: forgetAvailable && (rowMouse.containsMouse || rowSelected)

    hasCursor: rowSelected && !root.actionFocused
    current: isConnected
    foreground: root.panelText
    fill: root.hoverFill
    currentFill: root.selectedFill

    // The link is up, and the device counts as connected, while its code is
    // still being checked. Once paired, a connected device is done, though the
    // pairing command can take longer to hear that every profile is up.
    readonly property bool isPairing: !!dev && root.pairingAddress !== "" && root.pairingAddress === dev.address
      && !(root.pairingPaired && dev.connected)
    readonly property bool pairFailed: !!dev && root.pairFailureText !== "" && root.pairFailureAddress === dev.address

    readonly property string statusText: {
      if (!dev) return ""
      if (isPairing) return root.pairingPaired ? Commons.I18n.t("bluetooth.connecting") : Commons.I18n.t("bluetooth.pairing")
      if (pairFailed && !isConnected) return root.pairFailureText
      if (action === "forgetting") return Commons.I18n.t("bluetooth.forgetting")
      if (action === "disconnecting" || devState === 2) return Commons.I18n.t("bluetooth.disconnecting")
      if (isConnected) {
        if (dev.batteryAvailable) return Commons.I18n.formatNumber(Math.round(dev.battery * 100)) + "%"
        return sectionName === "connected" ? "" : Commons.I18n.t("bluetooth.connectedStatus")
      }
      if (action === "connecting" || devState === 3 || dev.pairing === true) return Commons.I18n.t("bluetooth.connecting")
      if (isDiscovered) return ""
      return ""
    }

    readonly property color statusColor: {
      if (isConnected) return root.panelText
      if (isPairing) return root.panelText
      if (pairFailed) return Commons.Color.status.error
      if (action !== "" || devState === 3 || dev.pairing === true) return root.panelText
      return Commons.Color.secondaryText(root.panelText, Commons.Color.popups.background)
    }

    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: row.dev ? Qt.PointingHandCursor : Qt.ArrowCursor

      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.focusSection = row.sectionName
        root.selectedIndex = row.rowIndex
        root.actionFocused = false
      }

      onClicked: function(mouse) {
        var dev = root.deviceFor(row)
        if (!dev) return
        if (mouse.button === Qt.RightButton) {
          if (row.isConnected) root.disconnectDevice(dev)
          else if (!row.isDiscovered) root.forgetDevice(dev)
          return
        }
        if (row.isConnected) root.disconnectDevice(dev)
        else root.connectDevice(dev)
      }
    }

    PanelToolTip {
      visible: row.actionTooltip !== "" && rowMouse.containsMouse && !root.actionFocused
      text: row.actionTooltip
      fontFamily: root.bar.fontFamily
    }

    Item {
      id: rowContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      implicitHeight: Math.max(deviceIcon.implicitHeight, info.implicitHeight, forgetBtn.implicitHeight)

      Text {
        id: deviceIcon
        textFormat: Text.PlainText
        text: Icons.glyph(row.isConnected ? "bluetooth.connected" : "bluetooth")
        color: row.statusColor
        font.family: Icons.family
        font.pixelSize: Style.font.icon
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        id: info
        spacing: Style.space(1)
        anchors.left: deviceIcon.right
        anchors.leftMargin: Style.space(10)
        anchors.right: forgetBtn.visible ? forgetBtn.left : parent.right
        anchors.rightMargin: forgetBtn.visible ? Style.space(8) : 0
        anchors.verticalCenter: parent.verticalCenter

        Text {
          textFormat: Text.PlainText
          text: root.deviceLabel(row.dev) || Commons.I18n.t("bluetooth.device")
          color: root.panelText
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
          width: parent.width
        }
        Text {
          textFormat: Text.PlainText
          visible: row.statusText !== ""
          text: row.statusText
          color: row.statusColor
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      PanelActionButton {
        id: forgetBtn
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: row.showForgetButton
        iconText: Icons.glyph("ui.close.circle")
        tooltipText: Commons.I18n.t("bluetooth.forget")
        foreground: root.panelText
        hoverColor: root.panelText
        fontFamily: root.bar.fontFamily
        hasCursor: row.rowSelected && root.actionFocused
        onHovered: function(isHovered) {
          if (!isHovered) {
            if (rowMouse.containsMouse) root.actionFocused = false
            return
          }
          root.cursorActive = true
          root.focusSection = row.sectionName
          root.selectedIndex = row.rowIndex
          root.actionFocused = true
        }
        onClicked: {
          var dev = root.deviceFor(row)
          if (!dev) return
          root.forgetDevice(dev)
        }
      }
    }
  }
}
