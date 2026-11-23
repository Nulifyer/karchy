import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import qs.Commons as Commons
import "../../../Commons/BluetoothControlModel.js" as Model

Panel {
  id: root
  moduleName: "karchy.bluetooth"
  ipcTarget: "karchy.bluetooth"
  // manageIpc: false so this panel can own the single IpcHandler the target
  // permits — needed for the toggleBluetooth method below.
  manageIpc: false

  // The adapter, its devices, what is being done to them, the pairing in
  // progress and the scan are BluetoothControl's (qs.Commons), which
  // Settings › Bluetooth uses too. The panel adds its cursor, its rows' looks
  // and the keys.
  readonly property var pendingActions: BluetoothControl.pendingActions
  readonly property string pairingAddress: BluetoothControl.pairingAddress
  readonly property string pairingName: BluetoothControl.pairingName
  readonly property bool pairingPaired: BluetoothControl.pairingPaired
  readonly property var pairingQuestion: BluetoothControl.pairingQuestion
  readonly property string pairingAnswerText: BluetoothControl.pairingAnswerText
  readonly property string pairFailureAddress: BluetoothControl.pairFailureAddress
  readonly property string pairFailureText: BluetoothControl.pairFailureText

  readonly property var adapter: BluetoothControl.adapter
  readonly property var devices: BluetoothControl.devices

  // While this panel is open the scan runs and it shows the pairing question
  // (BluetoothControl.scan, attend). A question nobody is showing opens one
  // panel: the first of the per-monitor instances.
  readonly property string viewKey: "bluetooth-panel-" + Math.random().toString(36).slice(2)
  Connections {
    target: BluetoothControl
    function onQuestionAsked() {
      if (BluetoothControl.attended) return
      var items = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.moduleName) : []
      if (items.length === 0 || items[0] === root) root.open()
    }
  }
  Component.onDestruction: {
    BluetoothControl.stopScan(viewKey)
    BluetoothControl.leave(viewKey)
  }

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

  readonly property var deviceGroups: BluetoothControl.deviceGroups
  readonly property var connectedDevices: BluetoothControl.connectedDevices
  readonly property var knownDevices: BluetoothControl.knownDevices
  readonly property var discoveredDevices: BluetoothControl.discoveredDevices

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

  function deviceAt(section, index) {
    var list = devicesForSection(section)
    return index >= 0 && index < list.length ? list[index] : null
  }

  function pendingAction(address) { return BluetoothControl.pendingAction(address) }
  function connectDevice(device) { BluetoothControl.connectDevice(device) }
  function disconnectDevice(device) { BluetoothControl.disconnectDevice(device) }
  function forgetDevice(device) { BluetoothControl.forgetDevice(device) }
  function answerPairing(text) { BluetoothControl.answerPairing(text) }
  function submitPairingText() { BluetoothControl.submitPairingText() }
  function acceptPairingQuestion() { BluetoothControl.acceptPairingQuestion() }
  function declinePairingQuestion() { BluetoothControl.declinePairingQuestion() }
  function toggleBluetooth() { BluetoothControl.togglePower() }

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
    if (!opened) {
      BluetoothControl.stopScan(viewKey)
      BluetoothControl.leave(viewKey)
      return
    }
    BluetoothControl.scan(viewKey)
    BluetoothControl.attend(viewKey)
    if (connectedDevices.length > 0) { focusSection = "connected"; selectedIndex = 0 }
    else if (knownDevices.length > 0) { focusSection = "known"; selectedIndex = 0 }
    else if (discoveredDevices.length > 0) { focusSection = "discovered"; selectedIndex = 0 }
    else { focusSection = "header" }
    actionFocused = false
    cursorActive = false
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
  onConnectedDevicesChanged: reselectFocusedDevice()
  onKnownDevicesChanged: reselectFocusedDevice()
  onDiscoveredDevicesChanged: reselectFocusedDevice()
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
              flush: true
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
            onTextChanged: if (text !== root.pairingAnswerText) BluetoothControl.pairingAnswerText = text
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
