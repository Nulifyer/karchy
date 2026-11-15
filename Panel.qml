import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "nulifyer.vpn"
  ipcTarget: "nulifyer.vpn"

  property var vpnInfo: emptyInfo("unknown")
  property string lastError: ""
  property color themeGreen: Color.accent
  property bool cursorActive: false
  property string focusSection: "header"
  property int modeIndex: 1
  property int phraseIndex: 0

  readonly property bool connected: vpnInfo.state === "connected"
  readonly property string policyMode: String(vpnInfo.mode || vpnInfo.intent || "off")
  readonly property bool busy: modeProcess.running
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color iconColor: connected ? themeGreen
    : vpnInfo.state === "failed" || vpnInfo.state === "unknown" ? urgent
    : vpnInfo.state === "off" && policyMode === "off" ? dim
    : foreground
  readonly property var activePhrases: [
    "Encrypting traffic",
    "Routing through WireGuard",
    "Guarding packets",
    "Sealing the tunnel"
  ]
  readonly property string heroMeta: connected
    ? activePhrases[phraseIndex % activePhrases.length]
    : stateLabel()

  function emptyInfo(state) {
    return {
      state: state || "unknown",
      intent: state === "off" ? "off" : "on",
      mode: state === "off" ? "off" : "on",
      effective: state === "off" ? "off" : "on",
      tunnel: "wgclient",
      vpnNm: "inactive",
      vpnIp: "",
      upstreamInterface: "",
      upstreamName: "",
      upstreamType: "",
      networkClass: "none",
      trusted: false,
      probe: "unavailable",
      guard: "unknown",
      traffic: state === "off" ? "direct" : "unknown",
      routeMode: state === "off" ? "direct" : "unknown",
      dnsMode: "unknown",
      dnsServer: "",
      handshakeAge: -1,
      statusAge: -1
    }
  }

  function loadThemeGreen(raw) {
    var match = String(raw || "").match(/^\s*green\s*=\s*["'](#[0-9A-Fa-f]{6})["']/m)
    themeGreen = match ? match[1] : Color.accent
  }

  function refresh() {
    if (!statusProcess.running) statusProcess.running = true
  }

  function updateStatus(raw) {
    var value = String(raw || "").trim()
    if (value === "") {
      vpnInfo = emptyInfo("unknown")
      return
    }
    try {
      var parsed = JSON.parse(value)
      if (!parsed || !parsed.state) throw new Error("missing state")
      vpnInfo = parsed
      lastError = ""
    } catch (error) {
      if (["off", "waiting", "connecting", "connected", "failed", "unknown"].indexOf(value) >= 0)
        vpnInfo = emptyInfo(value)
      else
        vpnInfo = emptyInfo("unknown")
    }
  }

  function setMode(mode) {
    if (modeProcess.running || ["on", "off", "auto"].indexOf(mode) < 0) return
    lastError = ""
    modeProcess.command = ["/usr/bin/nulifyer-vpn", "mode", mode]
    modeProcess.running = true
  }

  function cycleMode() {
    var modes = ["off", "auto", "on"]
    var index = modes.indexOf(policyMode)
    setMode(modes[(index + 1) % modes.length])
  }

  function selectedModeIndex() {
    var index = ["off", "auto", "on"].indexOf(policyMode)
    return index < 0 ? 1 : index
  }

  function stateLabel() {
    switch (vpnInfo.state) {
    case "connected": return policyMode === "auto" ? "Auto-protected on public network" : "Tunnel ready"
    case "connecting": return "Negotiating tunnel"
    case "waiting": return "Waiting for Wi-Fi or Ethernet"
    case "failed": return "Tunnel unreachable"
    case "off": return policyMode === "auto" ? "Trusted network, VPN standing by" : "Direct networking"
    default: return "Status unavailable"
    }
  }

  function tooltipForState() {
    switch (vpnInfo.state) {
    case "connected": return "VPN connected in " + policyMode + " mode. Click for details; right-click cycles mode"
    case "connecting": return "VPN connecting. Internet is blocked"
    case "waiting": return "VPN waiting for Wi-Fi or Ethernet"
    case "failed": return "VPN handshake failed. Internet is blocked"
    case "off": return "VPN " + policyMode + " mode. Click for details; right-click cycles mode"
    default: return "VPN status is stale or unavailable"
    }
  }

  function upstreamText() {
    var name = String(vpnInfo.upstreamName || vpnInfo.upstreamInterface || "")
    if (name === "") return "None"
    if (vpnInfo.upstreamType === "wifi") return "Wi-Fi · " + name
    if (vpnInfo.upstreamType === "ethernet") return "Ethernet · " + name
    return name
  }

  function tunnelText() {
    var name = String(vpnInfo.tunnel || "wgclient")
    if (vpnInfo.vpnIp) return name + " · " + vpnInfo.vpnIp
    return name
  }

  function handshakeText() {
    var age = Number(vpnInfo.handshakeAge)
    if (!isFinite(age) || age < 0) return "--"
    if (age < 2) return "now"
    if (age < 60) return Math.round(age) + "s ago"
    if (age < 3600) return Math.floor(age / 60) + "m ago"
    return Math.floor(age / 3600) + "h ago"
  }

  function probeText() {
    if (vpnInfo.probe === "reachable") return "Reachable"
    if (vpnInfo.probe === "unreachable") return "Unreachable"
    return "--"
  }

  function trafficText() {
    if (vpnInfo.traffic === "protected") return "Protected"
    if (vpnInfo.traffic === "blocked") return "Blocked"
    if (vpnInfo.traffic === "direct") return "Direct"
    return "Unknown"
  }

  function routeText() {
    if (vpnInfo.routeMode === "full") return "Full tunnel"
    if (vpnInfo.routeMode === "blocked") return "Blocked"
    if (vpnInfo.routeMode === "direct") return "Direct"
    return "Unknown"
  }

  function dnsText() {
    if (vpnInfo.dnsMode === "vpn") return "VPN · " + (vpnInfo.dnsServer || "Private")
    if (vpnInfo.dnsMode === "doh") return "DNS over HTTPS"
    if (vpnInfo.dnsMode === "dhcp") return "DHCP"
    if (vpnInfo.dnsMode === "blocked") return "Waiting for VPN"
    if (vpnInfo.dnsMode === "unavailable") return "Unavailable"
    return "Unknown"
  }

  function guardText() {
    if (vpnInfo.guard === "ready") return "Ready"
    if (vpnInfo.guard === "connecting") return "Blocking"
    if (vpnInfo.guard === "off") return "Off"
    return "Unknown"
  }

  function trustText() {
    if (vpnInfo.networkClass === "trusted") return "Trusted"
    if (vpnInfo.networkClass === "public") return "Public"
    return "None"
  }

  function setHeaderCursor() {
    cursorActive = true
    focusSection = "header"
  }

  function setModeCursor(index) {
    cursorActive = true
    focusSection = "mode"
    modeIndex = Math.max(0, Math.min(2, index))
  }

  function activateCursor() {
    if (focusSection === "header") refresh()
    else setMode(["off", "auto", "on"][modeIndex])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()
  onOpenedChanged: {
    if (opened) {
      cursorActive = false
      focusSection = "header"
      modeIndex = selectedModeIndex()
      refresh()
      Qt.callLater(function() { if (keyCatcher) keyCatcher.forceActiveFocus() })
    }
  }

  Process {
    id: statusProcess
    command: ["/usr/bin/nulifyer-vpn-status", "--json"]
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "The VPN package isn't installed or set up. See the README."
    }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.updateStatus(text)
    }
  }

  // The policy rewrites its status file on every change; the widget reads it
  // then, instead of on a timer. While the panel is open the live tunnel
  // details (handshake age) are refreshed below as well.
  FileView {
    path: "/run/nulifyer-vpn/status"
    watchChanges: true
    printErrors: false
    onFileChanged: { reload(); root.refresh() }
  }

  FileView {
    // Omarchy's theme, or karchy's when the widget runs there.
    path: Quickshell.env("HOME") + "/.local/state/" + (Quickshell.env("KARCHY_PATH") ? "karchy" : "omarchy")
      + "/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadThemeGreen(text())
    onFileChanged: reload()
  }

  Process {
    id: modeProcess
    stderr: StdioCollector { id: modeStderr; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = modeStderr.text.trim() || "Unable to change VPN mode."
      root.refresh()
      postToggleRefresh.restart()
    }
  }

  Timer {
    id: postToggleRefresh
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 2800
    running: root.opened && root.connected
    repeat: true
    onTriggered: phraseSwap.restart()
  }

  SequentialAnimation {
    id: phraseSwap
    PropertyAnimation {
      target: heroMetaText
      property: "opacity"
      to: 0.0
      duration: 180
      easing.type: Easing.OutQuad
    }
    ScriptAction { script: root.phraseIndex = (root.phraseIndex + 1) % root.activePhrases.length }
    PropertyAnimation {
      target: heroMetaText
      property: "opacity"
      to: 1.0
      duration: 260
      easing.type: Easing.InQuad
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf132"
    active: root.connected
    activeColor: root.themeGreen
    dimmed: root.policyMode === "off"
    tooltipText: root.tooltipForState()

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.cycleMode()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          root.focusSection = "header"
          return
        }
        if (dy > 0 && root.focusSection === "header") {
          root.focusSection = "mode"
          root.modeIndex = root.selectedModeIndex()
        } else if (dy < 0 && root.focusSection === "mode") {
          root.focusSection = "header"
        } else if (dx !== 0 && root.focusSection === "mode") {
          root.modeIndex = Math.max(0, Math.min(2, root.modeIndex + dx))
        }
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") root.refresh()
        else if (text === "a" || text === "A") root.setMode("auto")
        else if (text === "o" || text === "O") root.setMode("on")
        else if (text === "f" || text === "F") root.setMode("off")
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(12)

        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, heroActions.implicitHeight)

          Text {
            id: heroIcon
            text: "\uf132"
            color: root.iconColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            opacity: root.vpnInfo.state === "off" && root.policyMode === "off" ? 0.5 : 1.0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          RowLayout {
            id: heroActions
            spacing: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter

            Button {
              id: refreshAction
              iconText: "󰑐"
              tooltipText: "Refresh VPN status"
              foreground: root.foreground
              fontFamily: root.fontFamily
              iconSize: Style.font.subtitle * 1.5
              horizontalPadding: Style.space(5)
              verticalPadding: Style.space(2)
              hasCursor: root.cursorActive && root.focusSection === "header"
              Layout.alignment: Qt.AlignVCenter
              onHovered: function(on) { if (on) root.setHeaderCursor() }
              onClicked: root.refresh()
            }
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: heroActions.left
            anchors.rightMargin: Style.space(12)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              width: parent.width
              text: "WireGuard VPN (" + String(root.vpnInfo.tunnel || "wgclient") + ")"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              id: heroMetaText
              width: parent.width
              text: root.heroMeta.toUpperCase()
              color: root.vpnInfo.state === "failed" || root.vpnInfo.state === "unknown" ? root.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
            }
          }
        }

        Row {
          id: modeRow
          width: parent.width
          spacing: Style.space(6)
          enabled: !root.busy
          opacity: root.busy ? 0.6 : 1.0

          readonly property var options: [
            { value: "off", label: "Off", tooltip: "Always use direct networking" },
            { value: "auto", label: "Auto", tooltip: "VPN on public networks, direct on trusted networks" },
            { value: "on", label: "On", tooltip: "Always require WireGuard" }
          ]
          readonly property real cellWidth: (width - spacing * (options.length - 1)) / options.length

          Repeater {
            model: modeRow.options

            Button {
              required property var modelData
              required property int index
              width: modeRow.cellWidth
              text: String(modelData.label)
              tooltipText: String(modelData.tooltip)
              fontSize: Style.font.bodySmall
              foreground: root.foreground
              accent: root.themeGreen
              fontFamily: root.fontFamily
              horizontalPadding: Style.spacing.controlPaddingX
              verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
              bordered: true
              active: root.policyMode === String(modelData.value)
              hasCursor: root.cursorActive && root.focusSection === "mode" && root.modeIndex === index
              onClicked: root.setMode(String(modelData.value))
              onHovered: function(hovered) { if (hovered) root.setModeCursor(index) }
            }
          }
        }

        Text {
          visible: root.lastError !== ""
          width: parent.width
          text: root.lastError
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        GridLayout {
          width: parent.width
          columns: 2
          columnSpacing: Style.space(20)
          rowSpacing: Style.spacing.labelGap

          InfoLabel { text: "Upstream" }
          DetailValue { text: root.upstreamText() }
          InfoLabel { text: "Network" }
          DetailValue { text: root.trustText() }
          InfoLabel { text: "Tunnel" }
          DetailValue { text: root.tunnelText() }
          InfoLabel { text: "Handshake" }
          DetailValue { text: root.handshakeText() }
          InfoLabel { text: "Probe" }
          DetailValue {
            text: root.probeText()
            color: root.vpnInfo.probe === "unreachable" ? root.urgent : root.foreground
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: "NETWORK POLICY"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: Style.space(20)
            rowSpacing: Style.spacing.labelGap

            InfoLabel { text: "Traffic" }
            DetailValue {
              text: root.trafficText()
              color: root.vpnInfo.traffic === "blocked" ? root.urgent : root.foreground
            }
            InfoLabel { text: "Route" }
            DetailValue { text: root.routeText() }
            InfoLabel { text: "DNS" }
            DetailValue { text: root.dnsText() }
            InfoLabel { text: "Guard" }
            DetailValue {
              text: root.guardText()
              color: root.vpnInfo.guard === "connecting" ? root.urgent : root.foreground
            }
          }
        }
      }
    }
  }

  component InfoLabel: Text {
    color: root.foreground
    opacity: 0.6
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  component DetailValue: Text {
    Layout.fillWidth: true
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
    horizontalAlignment: Text.AlignRight
    elide: Text.ElideRight
  }
}
