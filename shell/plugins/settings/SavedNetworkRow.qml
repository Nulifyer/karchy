import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../panels/network/Model.js" as NetModel

// One saved network in Settings › Network. Closed it is one line: the name,
// what it is and how it stands. Open, everything that can be set for it, in
// the order people look for it, with Forget last and apart. Every change
// goes through karchy-network-profile (nmcli) and shows its result here; a
// refused value keeps what was typed and says why.
ColumnLayout {
  id: root
  spacing: Style.spacing.md

  property var page: null
  readonly property bool wide: width >= Style.spacing.formWide
  property var profile: ({})
  // This network's entry in karchy-trusted-networks status --json.
  property var trust: null
  property bool open: false
  signal toggleRequested()
  // Forgotten: the row goes away, so the list puts the keyboard elsewhere.
  signal forgotten()

  readonly property bool wifi: profile.type === "wifi"
  readonly property bool trusted: !!(trust && trust.trusted)
  readonly property string trustReason: trust ? String(trust.reason || "") : ""
  readonly property bool enterprise: profile.security === "wpa-eap"
  // The QR code shows the password of the network in use.
  readonly property bool canShare: wifi && profile.active && !enterprise && profile.security !== "open"

  function focusHeader() { header.forceActiveFocus() }

  function summary() {
    var parts = [wifi ? "Wi-Fi" : "Ethernet"]
    if (profile.active) parts.push("connected")
    if (trustReason === "trusted" || (trusted && !profile.active)) parts.push("trusted")
    else if (trustReason === "different router") parts.push("trusted, but a different router")
    else if (trustReason === "router unknown") parts.push("trusted, but the router couldn't be checked")
    else if (trustReason === "needs re-trust") parts.push("trusted before routers were recorded")
    if (profile.metered) parts.push("metered")
    if (!profile.autoconnect) parts.push("doesn't connect by itself")
    return parts.join(", ")
  }

  readonly property bool trustWarning: ["different router", "router unknown", "needs re-trust"].indexOf(trustReason) >= 0

  function set(args, done) {
    act.start(["karchy-network-profile", "set", profile.uuid].concat(args), function(ok, out, cancelled) {
      if (typeof done === "function") done(ok)
      if (root.page) root.page.refreshConnections()
    })
  }

  // ---- trust (karchy-trusted-networks, a password through polkit) ----
  property string connectFirst: ""
  function toggleTrust() {
    connectFirst = ""
    if (!trusted && !profile.active) {
      connectFirst = "Connect to " + profile.name + " first: trust is tied to its router."
      return
    }
    trustAct.start(["karchy-trusted-networks", "set", profile.uuid, trusted ? "false" : "true"], function() {
      if (root.page) root.page.refreshConnections()
    })
  }

  // ---- band: the choices the network in use answers on ----
  property var bands: ["2.4", "5", "6"]
  function readBands() { if (open && wifi && profile.active && !bandQuery.running) bandQuery.running = true }
  onOpenChanged: readBands()
  onWifiChanged: readBands()
  Process {
    id: bandQuery
    command: ["karchy-network-band"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var status = NetModel.parseBandStatus(text)
        root.bands = status.available.length > 0 ? status.available : ["2.4", "5", "6"]
      }
    }
  }

  // ---- IP settings: what is typed stays until it is saved or reset ----
  property string ipMode: profile.ip ? profile.ip.method : "auto"
  property bool ipEdited: false
  function resetIp() {
    if (act.tag === "ip") act.error = ""
    ipEdited = false
    ipMode = profile.ip ? profile.ip.method : "auto"
    addressField.text = profile.ip && profile.ip.addresses.length > 0 ? profile.ip.addresses[0] : ""
    gatewayField.text = profile.ip ? profile.ip.gateway : ""
    dnsField.text = profile.ip ? profile.ip.dns.join(" ") : ""
  }
  onProfileChanged: {
    if (!ipEdited) resetIp()
    readBands()
  }
  Component.onCompleted: { resetIp(); readBands() }

  function saveIp() {
    act.tag = "ip"
    var dns = dnsField.text.trim().split(/[\s,]+/).filter(function(s) { return s !== "" })
    var args = ipMode === "manual" ? ["ip", "manual", addressField.text.trim(), gatewayField.text.trim()].concat(dns) : ["ip", "auto"]
    set(args, function(ok) { if (ok) root.ipEdited = false })
  }

  NetworkAction { id: act }
  NetworkAction { id: trustAct; polkit: true }

  // ---- the row itself ----
  BorderSurface {
    id: header
    Layout.fillWidth: true
    implicitHeight: headerRow.implicitHeight + Style.spacing.lg * 2
    radius: Style.radius.control
    activeFocusOnTab: true
    readonly property bool hot: mouse.containsMouse
    color: Style.controlFill(activeFocus, hot, Commons.Color.foreground, Commons.Color.accent)
    borderSpec: Border.controlSpec(activeFocus || hot || root.open ? "hover-cursor" : "normal", Commons.Color.foreground, Commons.Color.accent)
    Keys.onReturnPressed: root.toggleRequested()
    Keys.onEnterPressed: root.toggleRequested()
    Keys.onSpacePressed: root.toggleRequested()
    Accessible.role: Accessible.Button
    Accessible.name: root.profile.name + ", " + root.summary()
    Accessible.description: root.open ? "Close" : "Open"

    FocusRing { shown: header.activeFocus }

    RowLayout {
      id: headerRow
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.spacing.rowPaddingX
      anchors.rightMargin: Style.spacing.rowPaddingX
      spacing: Style.spacing.lg

      Text {
        textFormat: Text.PlainText
        text: Icons.glyph(root.wifi ? "net.wifi.4" : "net.ethernet")
        color: root.profile.active ? Commons.Color.foreground : Commons.Color.textSecondary
        font.family: Icons.family
        font.pixelSize: Style.font.iconLarge
      }

      ColumnLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxs
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.profile.name
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: root.summary()
          color: root.trustWarning ? Commons.Color.status.warning : Commons.Color.textSecondary
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.Wrap
        }
      }

      Text {
        textFormat: Text.PlainText
        text: Icons.glyph(root.open ? "ui.chevron.up" : "ui.chevron.down")
        color: Commons.Color.textSecondary
        font.family: Icons.family
        font.pixelSize: Style.font.icon
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggleRequested()
    }
  }

  // ---- open: everything about this network ----
  ColumnLayout {
    visible: root.open
    Layout.fillWidth: true
    Layout.leftMargin: Style.spacing.xxl
    spacing: Style.spacing.md

    // A change that failed says why here; IP settings say it beside their
    // fields (below).
    InlineMessage {
      kind: "error"
      text: act.error !== "" && act.tag !== "ip" ? act.error.split("\n")[0] : ""
      details: act.error.indexOf("\n") >= 0 ? act.error : ""
      dismissible: true
      onDismissed: act.error = ""
    }

    // Trusting opens LocalSend's port and keeps the network's own DNS, so it
    // asks for a password; it records this network's router.
    SettingRow {
      label: "Trusted network"
      info: "LocalSend can receive files here, local names like nas.lan work, and the VPN stands by."
      // Why a trusted network isn't treated as one right now.
      note: root.trustReason === "different router" ? "Not trusted now: this is a different router. Turn on to trust it too."
        : root.trustReason === "router unknown" ? "Not trusted now: the router couldn't be checked."
        : root.trustReason === "needs re-trust" ? "Not trusted now: turn off and on again while connected."
        : ""
      warning: root.trustWarning
      checked: root.trusted
      busy: trustAct.running
      onToggled: root.toggleTrust()
    }
    InlineMessage {
      kind: "info"
      text: root.connectFirst
      dismissible: true
      onDismissed: root.connectFirst = ""
    }
    InlineMessage {
      kind: "error"
      text: trustAct.error !== "" ? (/Connect to this network|router address/.test(trustAct.error) ? trustAct.error : "Couldn't change whether " + root.profile.name + " is trusted.") : ""
      details: /Connect to this network|router address/.test(trustAct.error) ? "" : trustAct.error
      dismissible: true
      onDismissed: trustAct.error = ""
    }

    SettingRow {
      label: "Connect automatically"
      checked: !!root.profile.autoconnect
      busy: act.running && act.tag === "autoconnect"
      onToggled: { act.tag = "autoconnect"; root.set(["autoconnect", checked ? "no" : "yes"]) }
    }

    SettingRow {
      label: "Metered"
      info: "For a phone's hotspot or a data plan: updates and apps are asked to hold back here."
      checked: !!root.profile.metered
      busy: act.running && act.tag === "metered"
      onToggled: { act.tag = "metered"; root.set(["metered", checked ? "no" : "yes"]) }
    }

    GridLayout {
      Layout.fillWidth: true
      columns: root.wide ? 2 : 1
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { visible: root.wifi; text: "Wi-Fi band" }
      ButtonGroup {
        visible: root.wifi
        options: [{ value: "auto", label: "Automatic", tooltip: "Let Wi-Fi pick the band" }].concat(root.bands.map(function(b) {
          return { value: b, label: b + " GHz", tooltip: "Stay on " + b + " GHz" }
        }))
        value: root.profile.band || "auto"
        onChanged: function(value) { act.tag = "band"; root.set(["band", value]) }
      }

      SettingsLabel { visible: root.wifi; text: "Private Wi-Fi address" }
      Dropdown {
        visible: root.wifi
        Layout.fillWidth: true
        showLabel: false
        value: root.profile.private_address || "off"
        options: [
          { value: "off", label: "Off: the hardware address" },
          { value: "stable", label: "On: a random address kept for this network" }
        ].concat(root.profile.private_address && ["off", "stable"].indexOf(root.profile.private_address) < 0
          ? [{ value: root.profile.private_address, label: "Set elsewhere: " + root.profile.private_address }] : [])
        onChanged: function(value) {
          if (value === root.profile.private_address || (value !== "off" && value !== "stable")) return
          act.tag = "private-address"
          root.set(["private-address", value])
        }
      }

      SettingsLabel { text: "IP settings (IPv4)" }
      ButtonGroup {
        options: [{ value: "auto", label: "Automatic" }, { value: "manual", label: "Manual" }]
        value: root.ipMode
        onChanged: function(value) {
          root.ipMode = value
          root.ipEdited = true
          if (value === "auto" && root.profile.ip && root.profile.ip.method === "manual") root.saveIp()
          else if (value === "manual") Qt.callLater(function() { addressField.forceActiveFocus() })
        }
      }

      SettingsLabel { visible: root.ipMode === "manual"; text: "Address" }
      TextField {
        id: addressField
        visible: root.ipMode === "manual"
        Layout.fillWidth: true
        placeholderText: "192.168.1.20/24"
        onTextEdited: root.ipEdited = true
        onAccepted: gatewayField.forceActiveFocus()
      }

      SettingsLabel { visible: root.ipMode === "manual"; text: "Gateway" }
      TextField {
        id: gatewayField
        visible: root.ipMode === "manual"
        Layout.fillWidth: true
        placeholderText: "192.168.1.1"
        onTextEdited: root.ipEdited = true
        onAccepted: dnsField.forceActiveFocus()
      }

      SettingsLabel { visible: root.ipMode === "manual"; text: "DNS servers" }
      TextField {
        id: dnsField
        visible: root.ipMode === "manual"
        Layout.fillWidth: true
        placeholderText: "Optional, like 192.168.1.1"
        onTextEdited: root.ipEdited = true
        onAccepted: root.saveIp()
      }
    }

    InlineMessage {
      id: ipError
      kind: "error"
      text: act.error !== "" && act.tag === "ip" ? act.error.split("\n")[0] : ""
      details: act.error.indexOf("\n") >= 0 ? act.error : ""
      // The keyboard stays in the field; scroll the reason into view.
      onVisibleChanged: if (visible && root.page && root.page.settings)
        Qt.callLater(function() { root.page.settings.revealFocused(ipError) })
    }

    RowLayout {
      visible: root.ipMode === "manual" && root.ipEdited
      spacing: Style.spacing.controlGap
      Button {
        focusable: true
        variant: "primary"
        text: root.profile.active ? "Save and reconnect" : "Save IP settings"
        busy: act.running && act.tag === "ip"
        onClicked: { act.tag = "ip"; root.saveIp() }
      }
      Button {
        focusable: true
        bordered: true
        text: "Undo changes"
        onClicked: root.resetIp()
      }
    }

    RowLayout {
      Layout.topMargin: Style.spacing.md
      spacing: Style.spacing.controlGap

      Button {
        visible: root.canShare
        focusable: true
        bordered: true
        iconText: Icons.glyph("net.qr")
        text: "Share…"
        tooltipText: "Show a QR code a phone can join with"
        onClicked: if (root.page && root.page.settings && root.page.settings.shell)
          root.page.settings.shell.summon("karchy.wifiqr", JSON.stringify({ iface: root.profile.device, ssid: root.profile.ssid }))
      }

      Item { Layout.fillWidth: true; implicitHeight: 1 }

      // Apart from the rest, and asked about with Cancel selected.
      Button {
        focusable: true
        variant: "destructive"
        bordered: true
        text: "Forget"
        busy: act.running && act.tag === "forget"
        onClicked: if (root.page && root.page.settings) root.page.settings.ask(
          "Forget " + root.profile.name + "? Its password and settings are removed"
            + (root.trusted ? ", and it is no longer trusted" : "") + ". karchy won't join it again until you do.",
          "Forget", function() {
            act.tag = "forget"
            act.start(["karchy-network-profile", "forget", root.profile.uuid], function(ok) {
              if (ok) root.forgotten()
              if (root.page) root.page.refreshConnections()
            })
          })
      }
    }
  }
}
