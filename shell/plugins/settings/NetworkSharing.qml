import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Network › Sharing and firewall, read-only: whether the firewall
// is on, where LocalSend may receive files, and what is open right now
// (karchy-localsend-firewall status). There is no rule editor.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.spacing.md

  property var page: null
  property var fw: ({ firewall: false, incoming: "", localsend_installed: false, port: 53317, open_on: [] })
  property bool loaded: false

  function refresh() { if (!query.running) query.running = true }
  function focusFirst() { header.focusInfo() }

  function load(text) {
    try { root.fw = JSON.parse(text); root.loaded = true } catch (e) {}
  }

  function deviceName(device) {
    var list = page ? page.connections : []
    for (var i = 0; i < list.length; i++) if (list[i].device === device) return (list[i].ssid || list[i].name) + " (" + device + ")"
    return device
  }

  readonly property int trusted: page ? page.trustedCount : 0
  readonly property var rows: [
    { label: "Firewall", value: !loaded ? "" : fw.firewall
        ? (fw.incoming === "drop" || fw.incoming === "reject" ? "On, blocking incoming connections" : "On")
        : "Off: incoming connections aren't blocked",
      color: loaded && !fw.firewall ? Commons.Color.status.warning : undefined },
    { label: "LocalSend", value: !loaded ? "" : !fw.localsend_installed ? "Not installed"
        : "Receives files on trusted networks (" + trusted + (trusted === 1 ? " network)" : " networks)") },
    { label: "Open right now", value: !loaded ? "" : (fw.open_on || []).length === 0 ? "Nothing"
        : "LocalSend (port " + fw.port + ") on " + fw.open_on.map(deviceName).join(", ") }
  ]

  Process {
    id: query
    command: ["karchy-localsend-firewall", "status"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  SettingsHeader {
    id: header
    text: "Sharing and firewall"
    info: "The firewall turns away connections from other devices. It opens only LocalSend's port, and only on trusted networks. Rules you add with ufw yourself aren't listed here."
  }

  KeyValueGrid {
    Layout.fillWidth: true
    valueColumn: Style.spacing.formControlColumn
    rows: root.rows
  }
}
