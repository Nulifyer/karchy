import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../panels/network/Model.js" as NetModel

// Settings › Network › Status: one card per active connection (Wi-Fi,
// Ethernet, VPN), with the facts the panel has no room for. Names and icons
// are the panel's.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.spacing.lg

  property var page: null
  readonly property var connections: page ? page.connections : []

  // Nothing to change here: the keyboard starts on the section list.
  function focusFirst() { if (page && page.settings) page.settings.focusSection(page.settings.currentSectionIndex()) }

  function iconFor(c) {
    if (c.type === "vpn") return "net.vpn"
    if (c.type === "ethernet") return "net.ethernet"
    return NetModel.wifiIconFor(c.signal || 0)
  }

  function kindLabel(c) {
    return c.type === "wifi" ? "Wi-Fi" : c.type === "ethernet" ? "Ethernet" : "VPN"
  }

  // "9.9.9.9 (dns.quad9.net)": the address, and the name its certificate is
  // checked against.
  function dnsText(c) {
    if (c.type !== "vpn" && root.page && root.page.vpnFull)
      return "Not used while the VPN is connected"
    // One certificate name for all of them (a provider's servers) is said once.
    var servers = (c.dns || []).map(function(server) { return String(server).split("#") })
    var names = servers.map(function(parts) { return parts[1] || "" })
    var shared = names.length > 0 && names.every(function(n) { return n !== "" && n === names[0] })
    var list = servers.map(function(parts) { return !shared && parts[1] ? parts[0] + " (" + parts[1] + ")" : parts[0] })
    return list.join(", ") + (shared ? " (" + names[0] + ")" : "")
  }

  function linkText(c) {
    if (c.type === "ethernet") return c.speed_mbps ? (c.speed_mbps >= 1000 ? (c.speed_mbps / 1000) + " Gbit/s" : c.speed_mbps + " Mbit/s") : ""
    if (c.type !== "wifi") return ""
    var parts = []
    var band = NetModel.formatHeaderFreq(c.freq_mhz || 0).replace("ghz", " GHz")
    if (band !== "") parts.push(band)
    if (c.bitrate_mbps) parts.push(Math.round(c.bitrate_mbps) + " Mbit/s")
    if (c.signal) parts.push("signal " + c.signal + "%")
    return parts.join(", ")
  }

  function rowsFor(c) {
    var rows = []
    if ((c.ipv4 || []).length > 0) rows.push({ label: "IPv4 address", value: c.ipv4.join(", "), copyable: true, tooltip: "Copy" })
    if ((c.ipv6 || []).length > 0) rows.push({ label: "IPv6 address", value: c.ipv6.join(", "), copyable: true, tooltip: "Copy" })
    if (c.gateway4 || c.gateway6) rows.push({ label: "Gateway", value: [c.gateway4, c.gateway6].filter(function(g) { return !!g }).join(", "), copyable: true, tooltip: "Copy" })
    rows.push({ label: "DNS in use", value: dnsText(c) })
    if (!(c.type !== "vpn" && root.page && root.page.vpnFull) && (c.dns || []).length > 0)
      rows.push({ label: "Encrypted DNS", value: c.dns_encrypted ? "Yes, DNS over TLS" : "No",
        color: c.dns_encrypted ? undefined : Commons.Color.textSecondary })
    if (c.type === "vpn") rows.push({ label: "Carries", value: c.vpn_full ? "All internet traffic" : "Only its own networks" })
    var link = linkText(c)
    if (link !== "") rows.push({ label: c.type === "wifi" ? "Band and speed" : "Link speed", value: link })
    if (c.mac && c.type !== "vpn") rows.push({ label: "Hardware address", value: c.mac, copyable: true, tooltip: "Copy" })
    return rows
  }

  function copy(value) {
    Quickshell.execDetached(["bash", "-c", "printf %s \"$1\" | wl-copy", "copy", value])
  }

  SettingsHeader { id: header; text: "Status" }

  EmptyState {
    visible: root.connections.length === 0
    Layout.fillWidth: true
    iconName: "net.wifi.off"
    title: "Not connected"
    body: "Connect to Wi-Fi or plug in a cable from the network panel in the bar."
  }

  Repeater {
    model: root.connections

    Card {
      required property var modelData
      Layout.fillWidth: true
      iconName: root.iconFor(modelData)
      title: modelData.type === "wifi" && modelData.ssid ? modelData.ssid : modelData.name
      subtitle: root.kindLabel(modelData) + ", " + modelData.device
        + (root.page && root.page.trust[modelData.uuid] && root.page.trust[modelData.uuid].trusted ? ", trusted network" : "")

      KeyValueGrid {
        Layout.fillWidth: true
        // Inside the card's padding, still at the page's control column.
        valueColumn: Style.spacing.formControlColumn - Style.spacing.panelPadding
        wrapValues: true
        rows: root.rowsFor(modelData)
        onCopyRequested: function(value) { root.copy(value) }
      }
    }
  }
}
