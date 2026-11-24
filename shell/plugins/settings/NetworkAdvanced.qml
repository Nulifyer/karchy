import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Network › Advanced: the Wi-Fi country (karchy-network-country,
// a password through polkit) and NetworkManager's connectivity check (on or
// off over D-Bus; local users may change it without a password).
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.spacing.md

  property var page: null
  // karchy-network-country status --json.
  property var country: ({ effective: null, override: null, timezone: null, countries: [] })
  property bool checkEnabled: true
  property string checkHost: ""
  readonly property bool wide: width >= Style.spacing.formWide

  function refresh() {
    if (!countryQuery.running) countryQuery.running = true
    if (!checkQuery.running) checkQuery.running = true
  }
  function focusFirst() { if (root.hasWifi) countryBox.takeFocus() }

  readonly property var countryOptions: {
    var auto = "Automatic, from the timezone" + (country.timezone ? ": " + country.timezone.name : "")
    return [{ value: "auto", label: auto }].concat((country.countries || []).map(function(c) {
      return { value: c.code, label: c.name + " (" + c.code + ")" }
    }))
  }

  // No Wi-Fi radio, no country to choose (an unknown answer shows it).
  readonly property bool hasWifi: country.wifi !== false
  readonly property string inForce: country.effective
    ? "In use: " + country.effective.name + " (" + country.effective.code + ")"
    : "None in use, so Wi-Fi follows the strictest rules (no 6 GHz)"

  Process {
    id: countryQuery
    command: ["karchy-network-country", "status", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: { try { root.country = JSON.parse(text) } catch (e) {} } }
  }

  // ConnectivityCheckEnabled and the address NetworkManager checks.
  Process {
    id: checkQuery
    command: ["bash", "-c", "busctl get-property org.freedesktop.NetworkManager /org/freedesktop/NetworkManager org.freedesktop.NetworkManager ConnectivityCheckEnabled ConnectivityCheckUri"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = text.trim().split("\n")
        root.checkEnabled = (lines[0] || "") !== "b false"
        var uri = /"(.*)"/.exec(lines[1] || "")
        var host = uri ? /^[a-z]+:\/\/([^\/:]+)/.exec(uri[1]) : null
        root.checkHost = host ? host[1] : ""
      }
    }
  }

  NetworkAction { id: countryAct; polkit: true }
  NetworkAction { id: checkAct }

  SettingsHeader { text: "Advanced" }

  GridLayout {
    // Hidden whole with no Wi-Fi: an empty grid would still take a row.
    visible: root.hasWifi
    Layout.fillWidth: true
    columns: root.wide ? 2 : 1
    columnSpacing: Style.spacing.xxl
    rowSpacing: Style.spacing.md

    SettingsLabel { text: "Wi-Fi country"; visible: root.hasWifi }
    SearchableDropdown {
      id: countryBox
      visible: root.hasWifi
      Layout.fillWidth: true
      showLabel: false
      enabled: !countryAct.running
      value: root.country.override || "auto"
      options: root.countryOptions
      onChanged: function(value) {
        if (value === (root.country.override || "auto")) return
        countryAct.start(["karchy-network-country", "set", value], function(ok, out) {
          if (ok) { try { root.country = JSON.parse(out) } catch (e) {} }
          // The kernel takes a moment to switch; read it again.
          countryLater.restart()
        })
      }
    }
  }
  Timer { id: countryLater; interval: 1500; onTriggered: root.refresh() }

  Text {
    visible: root.hasWifi
    Layout.fillWidth: true
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
    text: root.inForce + "."
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  InlineMessage {
    kind: "error"
    text: countryAct.error !== "" ? "Couldn't change the Wi-Fi country." : ""
    details: countryAct.error
    dismissible: true
    onDismissed: countryAct.error = ""
  }

  // Where it connects stays beside the switch; how it works is behind (i).
  SettingRow {
    label: "Connectivity check"
    info: "Finds sign-in pages and networks without internet, by fetching a small file when a network connects and every few minutes."
    note: root.checkEnabled
      ? "Contacts " + (root.checkHost || "Arch Linux's server") + ", which sees your public IP address."
      : "Sign-in pages and networks without internet aren't detected."
    checked: root.checkEnabled
    busy: checkAct.running
    onToggled: checkAct.start(["busctl", "set-property", "org.freedesktop.NetworkManager", "/org/freedesktop/NetworkManager",
      "org.freedesktop.NetworkManager", "ConnectivityCheckEnabled", "b", checked ? "false" : "true"], function() { root.refresh() })
  }
  InlineMessage {
    kind: "error"
    text: checkAct.error !== "" ? "Couldn't change the connectivity check." : ""
    details: checkAct.error
    dismissible: true
    onDismissed: checkAct.error = ""
  }
}
