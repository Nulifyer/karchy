import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Network › DNS: which servers answer name lookups on networks
// that aren't trusted, and whether they are encrypted (karchy-network-dns,
// D-68). Changes are written by its root helper (a password through polkit,
// remembered for a few minutes) and applied to the connections at once.
// Below the choices: what each connection uses right now, in words.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.spacing.md

  property var page: null
  // karchy-network-dns status.
  property var dns: ({ provider: "quad9", servers: [], encrypted: true, trusted_too: false, fallback_allowed: true, links: [] })
  property bool loaded: false
  readonly property bool wide: width >= Style.space(560)

  // Custom servers as typed, until saved.
  property bool customEdited: false
  property string pendingProvider: ""
  readonly property string provider: pendingProvider !== "" ? pendingProvider : dns.provider
  readonly property bool customHasName: tlsField.text.trim() !== ""
  readonly property bool canEncrypt: provider === "quad9" || provider === "cloudflare"
    || (provider === "custom" && (customEdited ? customHasName : root.serversHaveName()))

  function refresh() { if (!statusQuery.running) statusQuery.running = true }
  function focusFirst() { providerBox.takeFocus() }

  function load(text) {
    try { root.dns = JSON.parse(text) } catch (e) { return }
    root.loaded = true
    if (!root.customEdited) root.resetCustom()
  }

  function serversHaveName() {
    var list = dns.servers || []
    return list.length > 0 && list.every(function(s) { return String(s).indexOf("#") > 0 })
  }

  function resetCustom() {
    var list = (dns.provider === "custom" ? dns.servers : []) || []
    addressesField.text = list.map(function(s) { return String(s).split("#")[0] }).join(" ")
    var names = list.map(function(s) { return String(s).split("#")[1] || "" }).filter(function(n) { return n !== "" })
    tlsField.text = names.length > 0 ? names[0] : ""
    customEdited = false
  }

  // Every setting at once, so root writes one consistent file.
  function apply(changes) {
    var next = {
      provider: dns.provider,
      encrypted: dns.encrypted ? "yes" : "no",
      trusted: dns.trusted_too ? "yes" : "no",
      fallback: dns.fallback_allowed ? "yes" : "no",
      servers: (dns.servers || []).join(" ")
    }
    for (var key in changes) next[key] = changes[key]
    if (next.provider !== "custom") delete next.servers
    var args = ["karchy-network-dns", "set"]
    for (var k in next) args.push(k + "=" + next[k])
    act.start(args, function(ok, out) {
      root.pendingProvider = ""
      if (ok) {
        root.load(out)
        root.customEdited = false
        root.resetCustom()
      }
      if (root.page) Qt.callLater(root.page.refreshConnections)
    })
  }

  function saveCustom() {
    var name = tlsField.text.trim()
    var servers = addressesField.text.trim().split(/[\s,]+/).filter(function(s) { return s !== "" })
      .map(function(s) { return name !== "" ? s + "#" + name : s })
    apply({ provider: "custom", servers: servers.join(" "), encrypted: name !== "" && dns.encrypted ? "yes" : "no" })
  }

  // What a link's state means, in words.
  function linkWords(state) {
    var name = dns.provider === "cloudflare" ? "Cloudflare" : dns.provider === "custom" ? "your servers" : "Quad9"
    switch (state) {
    case "applied": return name + (dns.encrypted ? ", encrypted" : ", not encrypted")
    case "network": return dns.provider === "network" ? "The network's DNS" : "The network's DNS (trusted network)"
    case "waiting": return "The network's DNS for now"
    case "portal": return "The network's DNS while you sign in"
    case "fallback": return "The network's DNS: encrypted DNS is blocked"
    case "blocked": return "None: encrypted DNS is blocked here"
    }
    return state
  }

  function linkName(device) {
    var list = page ? page.connections : []
    for (var i = 0; i < list.length; i++) if (list[i].device === device) return (list[i].ssid || list[i].name) + " (" + device + ")"
    return device
  }

  readonly property var linkRows: {
    var rows = []
    var list = dns.links || []
    var active = page ? page.connections.map(function(c) { return c.device }) : []
    for (var i = 0; i < list.length; i++) {
      if (active.indexOf(list[i].device) < 0) continue
      rows.push({ label: linkName(list[i].device), value: linkWords(list[i].state),
        color: list[i].state === "blocked" ? Commons.Color.status.error
          : list[i].state === "fallback" ? Commons.Color.status.warning : undefined })
    }
    return rows
  }

  Process {
    id: statusQuery
    command: ["karchy-network-dns", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  NetworkAction { id: act; polkit: true }

  SettingsHeader { text: "DNS" }

  Text {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: "On networks you haven't marked trusted. Trusted networks use their own DNS unless you choose otherwise. Changes ask for your password."
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  InlineMessage {
    kind: "error"
    text: act.error !== "" ? "Couldn't change the DNS settings." : ""
    details: act.error
    dismissible: true
    onDismissed: act.error = ""
  }

  GridLayout {
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "DNS servers" }
    Dropdown {
      id: providerBox
      Layout.fillWidth: true
      showLabel: false
      enabled: !act.running
      value: root.provider
      options: [
        { value: "network", label: "Automatic (from the network)" },
        { value: "quad9", label: "Quad9" },
        { value: "cloudflare", label: "Cloudflare" },
        { value: "custom", label: "Custom" }
      ]
      onChanged: function(value) {
        if (value === root.dns.provider) { root.pendingProvider = ""; return }
        if (value === "custom") {
          // Nothing to save until there is an address.
          root.pendingProvider = "custom"
          root.customEdited = true
          Qt.callLater(function() { addressesField.forceActiveFocus() })
          return
        }
        root.pendingProvider = value
        root.apply({ provider: value })
      }
    }

    SettingsLabel { visible: root.provider === "custom"; text: "Addresses" }
    TextField {
      id: addressesField
      visible: root.provider === "custom"
      Layout.fillWidth: true
      placeholderText: "Like 9.9.9.9 149.112.112.112"
      onTextEdited: root.customEdited = true
      onAccepted: tlsField.forceActiveFocus()
    }

    SettingsLabel { visible: root.provider === "custom"; text: "Certificate name" }
    TextField {
      id: tlsField
      visible: root.provider === "custom"
      Layout.fillWidth: true
      placeholderText: "For encrypted DNS, like dns.quad9.net"
      onTextEdited: root.customEdited = true
      onAccepted: root.saveCustom()
    }
  }

  RowLayout {
    visible: root.provider === "custom" && root.customEdited
    spacing: Style.spacing.controlGap
    Button {
      focusable: true
      variant: "primary"
      text: "Save DNS servers"
      busy: act.running
      enabled: addressesField.text.trim() !== ""
      onClicked: root.saveCustom()
    }
    Button {
      focusable: true
      bordered: true
      text: "Undo changes"
      onClicked: { root.pendingProvider = ""; root.resetCustom() }
    }
  }

  Toggle {
    visible: root.provider !== "network"
    enabled: root.canEncrypt
    Layout.fillWidth: true
    label: "Encrypted DNS"
    description: root.canEncrypt
      ? "DNS over TLS: the network can't see or change which sites you look up."
      : "Needs the servers' certificate name."
    checked: root.dns.encrypted && root.canEncrypt
    busy: act.running
    onClicked: root.apply({ encrypted: checked ? "no" : "yes" })
  }

  Toggle {
    visible: root.provider !== "network"
    Layout.fillWidth: true
    label: "Use on trusted networks too"
    description: "Off: trusted networks keep their own DNS, so names like nas.lan work there."
    checked: root.dns.trusted_too
    busy: act.running
    onClicked: root.apply({ trusted: checked ? "no" : "yes" })
  }

  // The consequence sits beside the switch, never behind (i).
  Toggle {
    visible: root.provider !== "network" && root.dns.encrypted && root.canEncrypt
    Layout.fillWidth: true
    label: "Encrypted only"
    description: "On networks that block encrypted DNS, and on sign-in pages, websites won't load."
    warning: !root.dns.fallback_allowed
    checked: !root.dns.fallback_allowed
    busy: act.running
    onClicked: root.apply({ fallback: checked ? "yes" : "no" })
  }

  Text {
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: "While the VPN is connected, it uses the VPN's DNS."
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  // Each connection's DNS right now.
  Card {
    visible: root.linkRows.length > 0
    title: "In use now"
    KeyValueGrid {
      Layout.fillWidth: true
      rows: root.linkRows
    }
  }
}
