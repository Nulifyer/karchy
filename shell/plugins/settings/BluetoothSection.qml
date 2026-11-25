import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../../Commons/BluetoothControlModel.js" as BluetoothModel

// Settings › Bluetooth: the adapter on or off, this computer's Bluetooth
// name and whether others can find it, the paired devices, and adding one.
//
// Everything is BluetoothControl's (qs.Commons), which the bar's Bluetooth
// panel shows too: the same devices, the same pairing in progress, one scan.
// Pairing asks what the device asks (D-95): a code to compare, a code to
// type on the device, or the device's own PIN.
//
// On or off is kept across restarts by itself (karchy-bluetooth-power moves
// the rfkill block, which systemd restores), so there is no separate "on at
// startup" setting. Connecting, disconnecting and forgetting go through
// karchy-bluetooth-device.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  property var settings: null
  property var target: ({})
  readonly property bool wide: width >= Style.spacing.formWide

  readonly property var adapter: BluetoothControl.adapter
  readonly property bool on: BluetoothControl.enabled
  // The devices this computer knows, the connected ones first (one being
  // paired is connected already); rows of primitives, as the panel's
  // (BluetoothModel.deviceRow says why).
  readonly property var pairedRows: BluetoothControl.connectedDevices.concat(BluetoothControl.knownDevices)
    .map(function(d) { return root.row(d) })
  readonly property var nearbyRows: BluetoothControl.discoveredDevices.map(function(d) { return root.row(d) })
  // "Add device" is open: the scan runs and nearby devices are listed.
  property bool adding: false
  readonly property var question: BluetoothControl.pairingQuestion

  function row(device) {
    var r = BluetoothModel.deviceRow(device)
    r.label = BluetoothModel.deviceLabel(device)
    r.trusted = device.trusted === true
    return r
  }

  function deviceFor(row) {
    return row ? BluetoothControl.deviceForAddress(row.address) : null
  }

  function statusText(row) {
    var pending = BluetoothControl.pendingAction(row.address)
    if (pending === "connecting") return Commons.I18n.t("bluetooth.connecting")
    if (pending === "disconnecting") return Commons.I18n.t("bluetooth.disconnecting")
    if (pending === "forgetting") return Commons.I18n.t("bluetooth.forgetting")
    if (BluetoothControl.pairingAddress === row.address) return Commons.I18n.t("bluetooth.pairing")
    if (BluetoothControl.pairFailureAddress === row.address && BluetoothControl.pairFailureText !== "")
      return BluetoothControl.pairFailureText
    if (!row.connected) return "Not connected"
    // BlueZ reports the battery as a share of 1.
    return row.batteryAvailable
      ? "Connected · battery " + Commons.I18n.formatNumber(Math.round(row.battery * 100)) + "%"
      : Commons.I18n.t("bluetooth.connectedStatus")
  }

  function setAdding(value) {
    root.adding = value
    if (value) BluetoothControl.scan("settings-bluetooth")
    else BluetoothControl.stopScan("settings-bluetooth")
  }

  // Off, or the adapter gone: nothing to add to.
  onOnChanged: if (!on) setAdding(false)

  // The device asked for is paired: it is in the list above now, and the
  // search has done its work.
  Connections {
    target: BluetoothControl
    function onPairingPairedChanged() { if (BluetoothControl.pairingPaired) root.setAdding(false) }
  }

  Component.onCompleted: BluetoothControl.attend("settings-bluetooth")
  Component.onDestruction: {
    BluetoothControl.leave("settings-bluetooth")
    BluetoothControl.stopScan("settings-bluetooth")
  }

  PageHeader {
    title: "Bluetooth"
    explanation: "The Bluetooth panel on the bar shows the same devices. Bluetooth stays on or off across restarts. A device set to connect automatically does so when it is switched on in range."
  }

  // No adapter: the page is not in the list, and says why if it is opened anyway.
  EmptyState {
    visible: !BluetoothControl.available
    Layout.fillWidth: true
    Layout.topMargin: Style.space(40)
    centered: true
    iconName: "bluetooth.off"
    title: Commons.I18n.t("bluetooth.noBluetoothAdapter")
    body: Commons.I18n.t("bluetooth.noAdapterHint")
  }

  SettingRow {
    visible: BluetoothControl.available
    label: "Bluetooth"
    checked: root.on
    onToggled: BluetoothControl.togglePower()
  }

  // ----------------------------------------------------------- this computer

  Section {
    visible: root.on
    title: "This computer"

    GridLayout {
      Layout.fillWidth: true
      columns: root.wide ? 2 : 1
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "Name" }
      TextField {
        id: nameField
        Layout.fillWidth: true
        Accessible.name: "This computer's Bluetooth name"
        // What other devices see. Saved on Enter or when the field is left.
        text: root.adapter ? root.adapter.name : ""
        maximumLength: 64
        function save() {
          if (text.trim() !== "") BluetoothControl.rename(text)
          else if (root.adapter) text = root.adapter.name
        }
        onAccepted: save()
        onActiveFocusChanged: if (!activeFocus) save()
      }
    }

    SettingRow {
      label: "Visible to nearby devices"
      info: "Needed only for a device that starts the pairing itself, such as a phone. Pairing from here doesn't need it."
      checked: root.adapter !== null && root.adapter.discoverable === true
      note: checked ? root.visibleNote() : ""
      onToggled: if (root.adapter) root.adapter.discoverable = !root.adapter.discoverable
    }
  }

  function visibleNote() {
    var name = root.adapter ? root.adapter.name : ""
    var seconds = root.adapter ? Number(root.adapter.discoverableTimeout) : 0
    var how = seconds > 0
      ? " It turns off by itself after " + (seconds >= 120 ? Math.round(seconds / 60) + " minutes." : seconds + " seconds.")
      : ""
    return "Other devices can find " + name + " and ask to pair." + how
  }

  // ---------------------------------------------------------------- pairing

  // The question of the pairing in progress, wherever it was started.
  Card {
    id: pairCard
    visible: root.question !== null
    selected: true
    readonly property string kind: root.question ? root.question.kind : ""
    readonly property bool typed: BluetoothModel.pairQuestionTyped(kind)
    title: BluetoothModel.pairQuestionText(kind, BluetoothControl.pairingName || Commons.I18n.t("bluetooth.device"), Commons.I18n.t)
    onVisibleChanged: if (visible) Qt.callLater(function() { (pairCard.typed ? pairAnswer : pairYes).forceActiveFocus() })

    // The code to compare or to type on the device.
    Text {
      visible: !pairCard.typed
      textFormat: Text.PlainText
      text: root.question ? root.question.code : ""
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.heading
      font.letterSpacing: Style.space(3)
      font.features: { "tnum": 1 }
      Accessible.name: "Code " + text
    }

    TextField {
      id: pairAnswer
      visible: pairCard.typed
      Layout.fillWidth: true
      Layout.maximumWidth: Style.space(240)
      Accessible.name: pairCard.title
      inputMethodHints: pairCard.kind === "enter-passkey" ? Qt.ImhDigitsOnly : Qt.ImhNone
      text: BluetoothControl.pairingAnswerText
      onTextChanged: if (text !== BluetoothControl.pairingAnswerText) BluetoothControl.pairingAnswerText = text
      onAccepted: BluetoothControl.submitPairingText()
      Keys.onEscapePressed: BluetoothControl.declinePairingQuestion()
    }

    Text {
      visible: pairCard.kind === "enter-pin"
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: Commons.I18n.t("bluetooth.pairEnterPinHint")
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.Wrap
    }

    RowLayout {
      spacing: Style.spacing.controlGap
      Button {
        id: pairYes
        // A code typed on the device has nothing to accept here.
        visible: pairCard.kind === "confirm" || pairCard.typed
        focusable: true
        bordered: true
        variant: "primary"
        text: pairCard.kind === "confirm" ? Commons.I18n.t("bluetooth.pairConfirmYes") : Commons.I18n.t("bluetooth.pairSubmit")
        enabled: !pairCard.typed || BluetoothModel.pairTypedAnswer(pairCard.kind, BluetoothControl.pairingAnswerText) !== ""
        onClicked: BluetoothControl.acceptPairingQuestion()
      }
      Button {
        focusable: true
        bordered: true
        text: pairCard.kind === "confirm" ? Commons.I18n.t("bluetooth.pairConfirmNo") : Commons.I18n.t("bluetooth.pairCancel")
        onClicked: BluetoothControl.declinePairingQuestion()
      }
    }
  }

  // ----------------------------------------------------------------- devices

  Section {
    visible: root.on
    title: "Devices"
    // Opens the list of nearby devices below, and closes it again.
    trailing: Button {
      focusable: true
      bordered: true
      text: root.adding ? "Done" : "Add device…"
      onClicked: root.setAdding(!root.adding)
    }

    Text {
      visible: root.pairedRows.length === 0
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: "No paired devices."
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: root.pairedRows
      delegate: Card {
        id: deviceCard
        required property var modelData
        readonly property string pending: BluetoothControl.pendingAction(modelData.address)
        readonly property bool busy: pending !== ""
        // The change the first button asks for.
        readonly property bool connecting: pending === "connecting" || pending === "disconnecting"
        Layout.fillWidth: true
        iconName: modelData.connected ? "bluetooth.connected" : "bluetooth"
        title: modelData.label
        subtitle: root.statusText(modelData)
        trailing: [
          Button {
            focusable: true
            bordered: true
            busy: deviceCard.connecting
            text: deviceCard.modelData.connected ? Commons.I18n.t("bluetooth.disconnect") : Commons.I18n.t("bluetooth.connect")
            accessibleName: text + " " + deviceCard.modelData.label
            onClicked: {
              var device = root.deviceFor(deviceCard.modelData)
              if (deviceCard.modelData.connected) BluetoothControl.disconnectDevice(device)
              else BluetoothControl.connectDevice(device)
            }
          },
          Button {
            focusable: true
            bordered: true
            variant: "destructive"
            enabled: !deviceCard.busy
            text: Commons.I18n.t("bluetooth.forget")
            accessibleName: text + " " + deviceCard.modelData.label
            onClicked: {
              var address = deviceCard.modelData.address, label = deviceCard.modelData.label
              if (!root.settings) return
              root.settings.ask("Forget " + label + "? It is disconnected and unpaired; to use it again, pair it again.",
                Commons.I18n.t("bluetooth.forget"),
                function() { BluetoothControl.forgetDevice(BluetoothControl.deviceForAddress(address)) })
            }
          }
        ]

        SettingRow {
          label: "Connect automatically"
          labelWidth: 0
          checked: deviceCard.modelData.trusted
          onToggled: BluetoothControl.setTrusted(root.deviceFor(deviceCard.modelData), !deviceCard.modelData.trusted)
        }
      }
    }
  }

  // ------------------------------------------------------------- add a device

  Section {
    visible: root.on && root.adding
    title: "Nearby devices"
    subtitle: root.nearbyRows.length === 0
      ? "Searching… Put the device in pairing mode."
      : "Searching…"

    Repeater {
      model: root.nearbyRows
      delegate: Card {
        id: nearbyCard
        required property var modelData
        readonly property bool pairingThis: BluetoothControl.pairingAddress === modelData.address
        Layout.fillWidth: true
        iconName: "bluetooth"
        title: modelData.label
        subtitle: pairingThis ? Commons.I18n.t("bluetooth.pairing")
          : BluetoothControl.pairFailureAddress === modelData.address ? BluetoothControl.pairFailureText : ""
        trailing: Button {
          focusable: true
          bordered: true
          // One pairing at a time.
          enabled: BluetoothControl.pairingAddress === "" || busy
          busy: nearbyCard.pairingThis
          text: Commons.I18n.t("bluetooth.pair")
          accessibleName: text + " " + nearbyCard.modelData.label
          onClicked: BluetoothControl.connectDevice(root.deviceFor(nearbyCard.modelData))
        }
      }
    }
  }
}
