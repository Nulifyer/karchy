import Quickshell
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Settings › Network › Saved networks: the one in use first, then the rest
// by name. A row opens in place with everything about that network; one row
// is open at a time. "Join hidden network…" follows the list.
ColumnLayout {
  id: root
  Layout.fillWidth: true
  spacing: Style.spacing.md

  property var page: null
  readonly property bool wide: width >= Style.spacing.formWide
  readonly property var profiles: page ? page.profiles : []
  // The UUID of the open row, "" for none.
  property string expanded: ""
  property bool joining: false
  property bool refocus: false

  function focusFirst() {
    var row = rows.itemAt(0)
    if (row) row.focusHeader()
    else joinButton.forceActiveFocus()
  }

  // The form goes away; the keyboard goes back to the button that opened it.
  function closeJoin() {
    joining = false
    Qt.callLater(function() { joinButton.forceActiveFocus() })
  }

  // Opened at a network (the panel's footer, `karchy-settings network X`).
  function openAt(uuid) {
    expanded = uuid
    for (var i = 0; i < rows.count; i++) {
      var row = rows.itemAt(i)
      if (row && row.profile.uuid === uuid) { Qt.callLater(row.focusHeader); return }
    }
  }

  SettingsHeader { text: "Saved networks" }

  EmptyState {
    visible: root.page && root.page.profilesLoaded && root.profiles.length === 0
    Layout.fillWidth: true
    iconName: "net.network"
    title: "No saved networks yet"
    body: "Networks you connect to appear here."
  }

  Repeater {
    id: rows
    model: root.page ? root.page.profileIds : []

    SavedNetworkRow {
      required property var modelData
      Layout.fillWidth: true
      page: root.page
      profile: root.page && root.page.profileMap[modelData] ? root.page.profileMap[modelData] : ({})
      trust: root.page && root.page.trust[modelData] ? root.page.trust[modelData] : null
      open: root.expanded === modelData
      onToggleRequested: root.expanded = open ? "" : modelData
      onForgotten: root.refocus = true
    }
    // A forgotten network's row is gone: the keyboard goes to the first row.
    onCountChanged: if (root.refocus) { root.refocus = false; Qt.callLater(root.focusFirst) }
  }

  Button {
    id: joinButton
    visible: !root.joining
    focusable: true
    bordered: true
    text: "Join hidden network…"
    onClicked: {
      root.joining = true
      Qt.callLater(function() { joinName.forceActiveFocus() })
    }
  }

  // A network that doesn't announce its name: its name, its security and
  // the password, then Join.
  Card {
    id: joinCard
    visible: root.joining
    title: "Join a hidden network"
    subtitle: "Type its name exactly."

    property string security: "wpa"

    function join() {
      if (joinAct.running) return
      // The password goes over stdin, never argv.
      joinAct.start(["karchy-network-profile", "join-hidden", joinName.text.trim(), joinCard.security], function(ok) {
          if (!ok) return
          root.closeJoin()
          joinName.text = ""
          joinPassword.text = ""
          if (root.page) root.page.refreshConnections()
        }, joinCard.security === "wpa" ? joinPassword.text : "")
    }

    GridLayout {
      Layout.fillWidth: true
      columns: root.wide ? 2 : 1
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "Network name" }
      TextField {
        id: joinName
        Layout.fillWidth: true
        placeholderText: "Exactly as the router has it"
        onAccepted: joinPassword.visible ? joinPassword.forceActiveFocus() : joinCard.join()
        Keys.onEscapePressed: root.closeJoin()
      }

      SettingsLabel { text: "Security" }
      Dropdown {
        Layout.fillWidth: true
        showLabel: false
        value: joinCard.security
        options: [{ value: "wpa", label: "WPA or WPA2 password" }, { value: "open", label: "None (open network)" }]
        onChanged: function(value) { joinCard.security = value }
      }

      SettingsLabel { visible: joinCard.security === "wpa"; text: "Password" }
      TextField {
        id: joinPassword
        visible: joinCard.security === "wpa"
        Layout.fillWidth: true
        password: true
        onAccepted: joinCard.join()
        Keys.onEscapePressed: root.closeJoin()
      }
    }

    InlineMessage {
      kind: "error"
      text: joinAct.error
    }

    RowLayout {
      spacing: Style.spacing.controlGap
      Button {
        focusable: true
        variant: "primary"
        text: "Join"
        busy: joinAct.running
        enabled: joinName.text.trim() !== "" && (joinCard.security === "open" || joinPassword.text.length >= 8)
        onClicked: joinCard.join()
      }
      Button {
        focusable: true
        bordered: true
        text: "Cancel"
        onClicked: root.closeJoin()
      }
    }

    NetworkAction { id: joinAct }
  }
}
