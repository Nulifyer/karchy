import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "../panels/network/Model.js" as NetModel

// Settings › Network › VPN. With the VPN package (karchy-vpn): its mode,
// what it is doing and since when, and "Allow local devices on trusted
// networks". Without it: NetworkManager's own VPN and WireGuard profiles,
// each with a switch. Either way, a WireGuard file from a VPN provider can be
// imported. The status is the package's file, read the way the panel reads
// it (Model.js).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.spacing.md

  property var page: null
  readonly property bool wide: width >= Style.space(560)
  // karchy-network-vpn status.
  property var info: ({ package: false, configured: false, home_lan: true, connection: "", connect_timeout: 30, profiles: [] })
  property var vpn: NetModel.parseVpnStatus("")
  property string imported: ""
  // Setting the package up with a profile ("Set up VPN"): the profile chosen,
  // and what the last try came to.
  property string setupUuid: ""
  property string setupDone: ""
  property string setupError: ""
  readonly property var wireguardProfiles: (info.profiles || []).filter(function(p) { return p.type === "wireguard" })
  readonly property var setupProfile: {
    for (var i = 0; i < wireguardProfiles.length; i++)
      if (wireguardProfiles[i].uuid === setupUuid) return wireguardProfiles[i]
    return wireguardProfiles.length > 0 ? wireguardProfiles[0] : null
  }
  // A profile that names no DNS server needs one typed in.
  readonly property bool setupNeedsDns: !!setupProfile && setupProfile.has_dns !== true

  // karchy-network-vpn prepares the profile and hands the configuration to
  // the package's root helper, which checks it and asks for an
  // administrator's password. Its last line says why when it refuses.
  function setUp(profile) {
    if (!profile || setupAct.running) return
    root.setupDone = ""
    root.setupError = ""
    var command = ["karchy-network-vpn", "setup", profile.uuid]
    if (root.setupNeedsDns && dnsField.text.trim() !== "") command.push(dnsField.text.trim())
    setupAct.start(command, function(ok, out, cancelled) {
      if (ok) {
        root.setupDone = "The VPN is set up with " + profile.name + "."
        root.imported = ""
      } else if (!cancelled) {
        var lines = setupAct.error.trim().split("\n")
        root.setupError = lines[lines.length - 1].replace(/^Setup failed: /, "")
      }
      root.refresh()
      if (root.page) root.page.refreshConnections()
    })
  }
  readonly property bool packaged: info.package === true
  readonly property string home: Quickshell.env("HOME")

  function refresh() { if (!infoQuery.running) infoQuery.running = true }
  function focusFirst() {
    (packaged && info.configured ? modeGroup : setupButton.visible ? setupButton : importButton).forceActiveFocus()
  }

  // Profile rows keyed by UUID, rebuilt only when the set changes, so a
  // switch keeps the keyboard after it is flipped.
  property var profileIds: []
  property var profileMap: ({})

  function load(text) {
    var next
    try { next = JSON.parse(text) } catch (e) { return }
    var map = {}
    var list = next.profiles || []
    for (var i = 0; i < list.length; i++) map[list[i].uuid] = list[i]
    var ids = list.map(function(p) { return p.uuid })
    root.info = next
    root.profileMap = map
    if (ids.join(" ") !== root.profileIds.join(" ")) root.profileIds = ids
  }

  function formatTime(epoch) {
    return Qt.formatTime(new Date(epoch * 1000), Qt.locale().timeFormat(Locale.ShortFormat))
  }

  function since(epoch) {
    if (!epoch) return ""
    var date = new Date(epoch * 1000)
    var today = new Date()
    return date.toDateString() === today.toDateString() ? formatTime(epoch)
      : Qt.formatDateTime(date, Qt.locale().dateTimeFormat(Locale.ShortFormat))
  }

  readonly property var facts: {
    var rows = []
    if (!vpn.present) return rows
    rows.push({ label: "Now", value: NetModel.vpnStatusLine(vpn, null, formatTime),
      color: NetModel.vpnTone(vpn) === "error" ? Commons.Color.status.error
        : NetModel.vpnTone(vpn) === "warning" ? Commons.Color.status.warning : undefined })
    if (vpn.since) rows.push({ label: "Since", value: since(vpn.since) })
    if (vpn.network) rows.push({ label: "Network", value: (vpn.network.name || vpn.network.device)
      + (vpn.network.trusted ? ", trusted" : ", not trusted") })
    if (vpn.tunnel) rows.push({ label: "Tunnel", value: vpn.tunnel.name + (vpn.tunnel.interface ? " (" + vpn.tunnel.interface + ")" : "") })
    return rows
  }

  function importFile() {
    if (chooser.running || importAct.running) return
    root.imported = ""
    chooser.start(["karchy-file-choose", "--title", "Import a WireGuard file", "--folder", root.home + "/Downloads",
      "--filter", "WireGuard configuration|*.conf"], function(ok, out) {
        var path = String(out || "").trim()
        if (!ok || path === "") return
        importAct.start(["karchy-network-vpn", "import", path], function(done, result) {
          if (!done) return
          try {
            var made = JSON.parse(result)
            root.imported = made.name
            root.setupUuid = made.uuid
          } catch (e) { root.imported = "the file" }
          root.refresh()
        })
      })
  }

  Process {
    id: infoQuery
    command: ["karchy-network-vpn", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  // The package's status: rewritten on every change, watched, never polled.
  FileView {
    path: "/run/karchy-vpn/status"
    watchChanges: true
    printErrors: false
    onLoaded: {
      var raw = text()
      var next = NetModel.parseVpnStatus(raw)
      // parseVpnStatus keeps what the panel needs; since and the tunnel are
      // extra here.
      try {
        var full = JSON.parse(raw)
        next.tunnel = full.tunnel || null
        next.since = Number(full.since) || 0
      } catch (e) {}
      root.vpn = next
    }
    onLoadFailed: root.vpn = NetModel.parseVpnStatus("")
    onFileChanged: reload()
  }

  NetworkAction { id: modeAct; polkit: true }
  NetworkAction { id: homeAct; polkit: true }
  NetworkAction { id: switchAct }
  NetworkAction { id: chooser }
  NetworkAction { id: importAct }
  NetworkAction { id: setupAct; polkit: true }

  SettingsHeader { text: "VPN" }

  // ---- with the VPN package ----
  GridLayout {
    // A mode means nothing until the VPN has a profile to use.
    visible: root.packaged && root.info.configured
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Mode" }
    ButtonGroup {
      id: modeGroup
      options: [
        { value: "off", label: "Off", tooltip: "Never use the VPN" },
        { value: "auto", label: "Auto", tooltip: "Use the VPN except on trusted networks" },
        { value: "on", label: "On", tooltip: "Use the VPN on every network" }
      ]
      value: root.vpn.present ? root.vpn.mode : ""
      onChanged: function(value) { modeAct.start(["karchy-vpn", "mode", value]) }
    }
  }

  InlineMessage {
    kind: "error"
    text: modeAct.error !== "" ? "Couldn't change the VPN." : ""
    details: modeAct.error
    dismissible: true
    onDismissed: modeAct.error = ""
  }

  // Not set up yet: with a profile to use, one action sets it up; with none,
  // the next step is the import below.
  Text {
    visible: root.packaged && !root.info.configured && root.wireguardProfiles.length === 0
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: "Not set up yet. Import the WireGuard file from your VPN provider."
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  GridLayout {
    visible: root.packaged && !root.info.configured && root.wireguardProfiles.length > 0
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Profile" }
    Dropdown {
      Layout.fillWidth: true
      showLabel: false
      enabled: !setupAct.running
      value: root.setupProfile ? root.setupProfile.uuid : ""
      options: root.wireguardProfiles.map(function(p) { return { value: p.uuid, label: p.name } })
      onChanged: function(value) { root.setupUuid = value }
    }

    SettingsLabel { visible: root.setupNeedsDns; text: "DNS server" }
    TextField {
      id: dnsField
      visible: root.setupNeedsDns
      Layout.fillWidth: true
      enabled: !setupAct.running
      placeholderText: "One inside the VPN, like 10.0.0.1"
      Accessible.name: "DNS server inside the VPN"
      onAccepted: root.setUp(root.setupProfile)
    }
  }

  Button {
    id: setupButton
    visible: root.packaged && !root.info.configured && root.wireguardProfiles.length > 0
    focusable: true
    variant: "primary"
    text: setupAct.running ? "Setting up…" : "Set up VPN"
    busy: setupAct.running
    enabled: !root.setupNeedsDns || dnsField.text.trim() !== ""
    onClicked: root.setUp(root.setupProfile)
  }

  // What setting it up does to this network, before it is done.
  Text {
    visible: setupButton.visible
    Layout.fillWidth: true
    Layout.maximumWidth: Style.space(620)
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: "Starts on Auto: on networks you haven't trusted, the internet is blocked until the VPN connects."
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  InlineMessage {
    kind: "error"
    text: root.setupError !== "" ? "Couldn't set up the VPN: " + root.setupError : ""
    details: setupAct.error.trim().indexOf("\n") >= 0 ? setupAct.error : ""
    dismissible: true
    onDismissed: root.setupError = ""
  }
  InlineMessage {
    kind: "info"
    text: root.setupDone
    dismissible: true
    onDismissed: root.setupDone = ""
  }

  Section {
    visible: root.packaged && root.facts.length > 0
    title: "What it's doing"
    subtitle: "The internet is blocked while it connects, and stays blocked if it can't."
    KeyValueGrid {
      Layout.fillWidth: true
      rows: root.facts
    }
  }

  SettingRow {
    visible: root.packaged && root.info.configured
    label: "Local devices on trusted networks"
    info: "With the VPN on at home, the NAS, the printer and names like nas.lan stay reachable beside it."
    checked: root.info.home_lan
    busy: homeAct.running
    onToggled: homeAct.start(["karchy-network-vpn", "home-lan", checked ? "no" : "yes"], function() { root.refresh() })
  }
  InlineMessage {
    kind: "error"
    text: homeAct.error !== "" ? "Couldn't change the VPN's settings." : ""
    details: homeAct.error
    dismissible: true
    onDismissed: homeAct.error = ""
  }

  // ---- without it: NetworkManager's VPN profiles ----
  EmptyState {
    visible: !root.packaged && root.info.profiles.length === 0
    Layout.fillWidth: true
    iconName: "net.vpn"
    title: "No VPN yet"
    body: "Import the WireGuard file your VPN provider gives you."
  }

  Repeater {
    model: root.packaged ? [] : root.profileIds
    Toggle {
      required property var modelData
      readonly property var profile: root.profileMap[modelData] || ({})
      Layout.fillWidth: true
      label: profile.name || ""
      description: (profile.type === "wireguard" ? "WireGuard" : "VPN") + (profile.active ? ", connected" : "")
      checked: !!profile.active
      busy: switchAct.running && switchAct.tag === modelData
      onClicked: {
        switchAct.tag = modelData
        switchAct.start(["karchy-network-vpn", "switch", modelData, profile.active ? "off" : "on"], function() {
          root.refresh()
          if (root.page) root.page.refreshConnections()
        })
      }
    }
  }
  InlineMessage {
    kind: "error"
    text: switchAct.error !== "" ? "Couldn't switch the VPN." : ""
    details: switchAct.error
    dismissible: true
    onDismissed: switchAct.error = ""
  }

  Button {
    id: importButton
    focusable: true
    bordered: true
    text: "Import WireGuard file…"
    busy: chooser.running || importAct.running
    onClicked: root.importFile()
  }

  InlineMessage {
    kind: "error"
    text: importAct.error
    dismissible: true
    onDismissed: importAct.error = ""
  }
  // A profile imported while the VPN uses another: one action switches it.
  InlineMessage {
    readonly property bool other: root.packaged && root.info.configured
    kind: "info"
    text: root.imported === "" ? ""
      : other ? "Imported as " + root.imported + ". The VPN uses " + (root.info.connection || "another profile") + "."
      : root.packaged ? ""
      : "Imported as " + root.imported + ". Switch it on above to connect."
    actionText: other && root.setupProfile ? "Use " + root.imported + " instead" : ""
    onAction: root.setUp(root.setupProfile)
    dismissible: true
    onDismissed: root.imported = ""
  }
}
