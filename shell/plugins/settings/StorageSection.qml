import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "StorageModel.js" as Model

// Settings › Storage: every disk in the computer with what is on it, the
// network shares kept mounted, and the drives plugged in, through
// karchy-settings-storage.
//
//   a card per disk      its health (SMART, read when the page opens),
//                        then each volume: where it is mounted, how full it
//                        is right now, and what can be done with it
//                        (StorageVolume)
//   btrfs filesystems    also what the files hold against what they take on
//                        the disk, which has to be counted file by file:
//                        only "Measure now" does that, and the result
//                        carries its date. Nothing is shown that was not
//                        counted.
//   the system disk      the switch for background deduplication (bees) and
//                        how far it is
//   Network shares       the shares kept at /mnt; a share whose server is
//                        away says so and never holds the page up
//   USB drives           mount, unmount, eject
//
// The page reads again when a disk, a mount, /etc/fstab, the measurement or
// a disk warning changes (karchy-settings-storage watch). What has no event
// is asked for again, only while the page is in view: how full each volume
// is every two seconds (the filesystem's own totals, nothing is walked),
// bees' progress every ten, and whether a connected share still answers
// every half minute.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null

  // karchy-settings-storage usage: the newest space figures, by filesystem
  // UUID. Empty until the first reading; `status` carries the same figures
  // as of its own reading.
  property var usage: ({})
  // karchy-settings-storage health: each disk's SMART health, and whether
  // it was read at all.
  property var healthList: []
  property bool healthLoaded: false
  // karchy-settings-storage status.
  property var measurement: ({ time: null, running: false, available: false })
  // The disks by name; the two lists of names are replaced only when the set
  // of disks changes, so a refresh doesn't rebuild the cards (and take the
  // keyboard out of them).
  property var diskMap: ({})
  property var internalNames: []
  property var removableNames: []
  property bool loaded: false
  // karchy-settings-storage shares, and whether they were read at all.
  property var shares: []
  property bool sharesLoaded: false
  // karchy-settings-storage bees.
  property var bees: ({ available: false, on: false, active: false })
  // The time the page was last read at, for "Measured today at …".
  property double nowMs: Date.now()

  // The action under way ("unmount /dev/sdb1"); "" when none.
  property string acting: ""
  // Why the last action didn't work, and the volume, disk or share it is
  // shown under (its path); "" shows it at the top of the page.
  property string error: ""
  property string errorKey: ""

  function refresh() {
    statusQuery.request()
    healthQuery.request()
    sharesQuery.request()
    beesQuery.request()
  }

  function loadStatus(text) {
    var status
    try { status = JSON.parse(text) } catch (e) { return }
    var map = {}
    var parts = Model.split(status.disks || [])
    ;(status.disks || []).forEach(function(disk) { map[disk.name] = disk })
    var names = function(list) { return list.map(function(disk) { return disk.name }) }
    root.nowMs = Date.now()
    root.measurement = status.measurement || { time: null, running: false, available: false }
    root.diskMap = map
    // The figures of this reading are the newest now.
    root.usage = ({})
    // A disk came or went: its health is read with the others'.
    var changed = names(parts.internal).concat(names(parts.removable)).join(" ") !== root.internalNames.concat(root.removableNames).join(" ")
    if (names(parts.internal).join(" ") !== root.internalNames.join(" ")) root.internalNames = names(parts.internal)
    if (names(parts.removable).join(" ") !== root.removableNames.join(" ")) root.removableNames = names(parts.removable)
    if (changed && root.loaded) healthQuery.request()
    root.loaded = true
  }

  function loadUsage(text) {
    try { root.usage = JSON.parse(text) } catch (e) {}
  }

  function loadHealth(text) {
    try { root.healthList = JSON.parse(text); root.healthLoaded = true } catch (e) {}
  }

  function loadShares(text) {
    try { root.shares = JSON.parse(text); root.sharesLoaded = true } catch (e) {}
  }

  function loadBees(text) {
    try { root.bees = JSON.parse(text); root.nowMs = Date.now() } catch (e) {}
  }

  // One change at a time: `key` names it for the button that spins, `where`
  // is the path its error is shown under.
  function act(key, where, args, onDone) {
    if (actionProc.running) return
    root.error = ""
    root.errorKey = where
    root.acting = key
    actionProc.failed = false
    actionProc.said = ""
    actionProc.onDone = onDone || null
    actionProc.command = ["karchy-settings-storage"].concat(args)
    actionProc.running = true
  }

  function inTerminal(words) {
    Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation"].concat(words))
  }

  function measure(where) {
    root.act("measure", where, ["measure"], function() { statusQuery.request() })
  }

  function setBees(on, where) {
    root.act("bees", where, ["bees", on ? "on" : "off"])
  }

  function volumeAction(action, volume, disk) {
    var name = Model.volumeName(volume)
    switch (action) {
      case "open": Quickshell.execDetached(["xdg-open", Model.mainMount(volume)]); break
      case "mount": root.act("mount " + volume.path, volume.path, ["mount", volume.path]); break
      case "unmount": root.act("unmount " + volume.path, volume.path, ["unmount", volume.path]); break
      case "unlock": root.inTerminal(["karchy-settings-storage", "unlock", volume.path]); break
      case "keep": root.act("keep " + volume.path, volume.path, ["keep", volume.path]); break
      case "unkeep":
        // Takes it out of /etc/fstab, so it asks first; the terminal then
        // only asks for the password.
        if (root.settings) root.settings.ask("Stop keeping " + name + " mounted at " + volume.kept + "? It is unmounted and no longer mounts at startup. The files on it are not touched.",
          "Stop keeping", function() { root.inTerminal(["karchy-disk-keep", "--remove", "--yes", volume.path]) })
        break
      case "check": root.inTerminal(["karchy-settings-storage", "check", Model.mainMount(volume)]); break
      case "speedtest":
        Quickshell.execDetached(["karchy-shell", "shell", "summon", "karchy.disk-speedtest",
          JSON.stringify(volume.role === "system" ? {} : { dir: volume.writable })])
        break
      case "password": root.inTerminal(["karchy-drive-password"]); break
    }
  }

  function stopKeepingShare(share) {
    var names = Model.shareName(share)
    if (root.settings) root.settings.ask("Stop keeping " + names.name + " on " + names.server + " mounted at " + share.target + "? Its saved password is removed. Files on the server are not touched.",
      "Stop keeping", function() { root.inTerminal(["karchy-mount-keep", "--remove", "--yes", share.target]) })
  }

  Component.onCompleted: refresh()

  // A read that can be asked for again while it runs; it runs once more
  // after, so the newest state always lands.
  component Query: Process {
    id: query
    property bool again: false
    signal result(string text)
    function request() {
      if (running) again = true
      else running = true
    }
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: query.result(text) }
    onExited: if (again) { again = false; running = true }
  }

  Query { id: statusQuery; command: ["karchy-settings-storage", "status"]; onResult: function(text) { root.loadStatus(text) } }
  Query { id: usageQuery; command: ["karchy-settings-storage", "usage"]; onResult: function(text) { root.loadUsage(text) } }
  // Apart from the disks too: it asks each disk, and one that is slow to
  // answer doesn't hold the rest up.
  Query { id: healthQuery; command: ["karchy-settings-storage", "health"]; onResult: function(text) { root.loadHealth(text) } }
  // Apart from the disks: a share that doesn't answer takes two seconds to
  // say so, and the rest of the page doesn't wait for it.
  Query { id: sharesQuery; command: ["karchy-settings-storage", "shares"]; onResult: function(text) { root.loadShares(text) } }
  Query { id: beesQuery; command: ["karchy-settings-storage", "bees"]; onResult: function(text) { root.loadBees(text) } }

  // A change prints nothing, or bees' new state; when it fails, stderr says
  // why. The exit and the end of stderr arrive in either order.
  Process {
    id: actionProc
    property var onDone: null
    property bool failed: false
    property string said: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim().charAt(0) === "{") root.loadBees(text)
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        actionProc.said = text.trim()
        if (actionProc.failed && actionProc.said !== "") root.error = actionProc.said
      }
    }
    onExited: function(exitCode) {
      var done = actionProc.onDone
      var wasBees = root.acting === "bees"
      root.acting = ""
      actionProc.failed = exitCode !== 0
      if (actionProc.failed) root.error = actionProc.said !== "" ? actionProc.said : "That didn't work, and nothing said why."
      else if (typeof done === "function") done()
      // A refused change puts the switch back where it is.
      if (wasBees && actionProc.failed) beesQuery.request()
      statusQuery.request()
    }
  }

  // The kernel, udev and inotify say when anything changes. A burst of
  // events (a drive being plugged in) is read once, a moment after.
  Process {
    running: root.visible
    command: ["karchy-settings-storage", "watch"]
    stdout: SplitParser { onRead: function(line) { changes.restart() } }
  }
  Timer {
    id: changes
    interval: 500
    onTriggered: { statusQuery.request(); sharesQuery.request() }
  }

  // How full a volume is has no event to wait on, and neither has bees'
  // progress (root's to read), so both are asked for again and again, only
  // while the page is in view. The same goes for a connected share, whose
  // server can go away without a word, and for a measurement that ends
  // without a new result.
  Timer {
    interval: 2000
    repeat: true
    running: root.visible && root.loaded
    onTriggered: usageQuery.request()
  }
  Timer {
    interval: 10000
    repeat: true
    running: root.visible && root.bees.active === true
    onTriggered: beesQuery.request()
  }
  Timer {
    interval: 30000
    repeat: true
    running: root.visible && root.shares.some(function(share) { return share.state !== "idle" })
    onTriggered: sharesQuery.request()
  }
  Timer {
    interval: 3000
    repeat: true
    running: root.visible && root.measurement.running === true
    onTriggered: statusQuery.request()
  }

  // A disk: what it is and how healthy, then its volumes.
  component DiskCard: Card {
    id: card
    property string diskName: ""
    readonly property var disk: root.diskMap[diskName] || ({ name: diskName, volumes: [], warnings: [] })
    readonly property var health: Model.health({ health: Model.healthFor(disk, root.healthList) })
    // Replaced only when the volumes change, as the lists of disks are.
    property var volumePaths: []
    function syncVolumes() {
      var next = (disk.volumes || []).map(function(volume) { return volume.path })
      if (next.join(" ") !== volumePaths.join(" ")) volumePaths = next
    }
    onDiskChanged: syncVolumes()
    Component.onCompleted: syncVolumes()
    function volumeAt(path) {
      var list = disk.volumes || []
      for (var i = 0; i < list.length; i++) if (list[i].path === path) return list[i]
      return {}
    }

    Layout.fillWidth: true
    title: Model.diskTitle(disk)
    subtitle: Model.diskKind(disk) + (health.state === "" ? ""
      : health.state === "unknown" ? " · This disk reports no health data"
      : health.state === "asleep" ? " · Asleep, so its health was not checked" + (health.facts !== "" ? " (" + health.facts + ")" : "")
      : " · Health " + health.text + (health.facts !== "" ? ", " + health.facts : ""))

    trailing: Button {
      visible: card.disk.removable === true
      focusable: true
      bordered: true
      text: "Eject"
      accessibleName: "Eject " + card.title
      enabled: root.acting === "" || busy
      busy: root.acting === "eject " + card.disk.path
      onClicked: root.act("eject " + card.disk.path, card.disk.path, ["eject", card.disk.path])
    }

    InlineMessage {
      Layout.fillWidth: true
      kind: "warning"
      text: card.health.state === "warning" ? card.health.details : ""
    }

    // What smartd reported since (karchy-disk-health's warnings).
    Repeater {
      model: card.disk.warnings || []
      delegate: InlineMessage {
        required property var modelData
        Layout.fillWidth: true
        kind: "warning"
        text: modelData.summary
        actionText: "Details…"
        onAction: root.inTerminal(["karchy-disk-health", "details", modelData.name])
      }
    }

    InlineMessage {
      Layout.fillWidth: true
      kind: "error"
      text: root.errorKey === card.disk.path ? root.error : ""
      dismissible: true
      onDismissed: root.error = ""
    }

    Text {
      visible: card.volumePaths.length === 0
      Layout.fillWidth: true
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: "Nothing on this disk that can be mounted."
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Repeater {
      model: card.volumePaths
      delegate: StorageVolume {
        required property string modelData
        page: root
        disk: card.disk
        volume: card.volumeAt(modelData)
      }
    }
  }

  component Note: Text {
    Layout.fillWidth: true
    Layout.maximumWidth: Style.space(620)
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    lineHeight: 1.15
  }

  PageHeader {
    title: "Storage"
    explanation: "How full each volume is comes from the filesystem itself and follows what you do. \"Measure now\" under a btrfs volume counts more: what your files add up to, and what sharing, compression and snapshots account for. It reads every file's layout, which can take minutes, so it runs only when you ask. 1 GB is a thousand MB, as disks are sold."
  }

  InlineMessage {
    Layout.fillWidth: true
    kind: "error"
    text: root.errorKey === "" ? root.error : ""
    dismissible: true
    onDismissed: root.error = ""
  }

  Repeater {
    model: root.internalNames
    delegate: DiskCard {
      required property string modelData
      diskName: modelData
    }
  }

  SettingsHeader { text: "Network shares" }

  Note {
    visible: root.sharesLoaded && root.shares.length === 0
    text: "No shares kept mounted."
  }

  Repeater {
    model: root.shares
    delegate: ColumnLayout {
      id: shareRow
      required property var modelData
      required property int index
      readonly property var names: Model.shareName(modelData)
      Layout.fillWidth: true
      spacing: Style.spacing.md

      PanelSeparator { visible: shareRow.index > 0; Layout.fillWidth: true }

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.xxs
          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg
            Text {
              textFormat: Text.PlainText
              text: shareRow.names.name
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              font.bold: true
              Layout.maximumWidth: Style.space(260)
              elide: Text.ElideRight
            }
            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: "on " + shareRow.names.server + " · " + Model.shareState(shareRow.modelData)
              color: shareRow.modelData.state === "unreachable" ? Commons.Color.status.warning : Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              elide: Text.ElideRight
            }
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: shareRow.modelData.state === "connected"
              ? Model.bytes(shareRow.modelData.size - shareRow.modelData.avail) + " used of " + Model.bytes(shareRow.modelData.size) + " · " + shareRow.modelData.target
              : shareRow.modelData.target
            color: Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.features: { "tnum": 1 }
            elide: Text.ElideMiddle
          }
        }

        Button {
          focusable: true
          bordered: true
          // Opening a share whose server is away would make the file manager
          // wait for it.
          enabled: shareRow.modelData.state !== "unreachable"
          text: "Open"
          accessibleName: "Open " + shareRow.names.name + " in Files"
          onClicked: Quickshell.execDetached(["xdg-open", shareRow.modelData.target])
        }
        Button {
          focusable: true
          bordered: true
          text: "Stop keeping…"
          accessibleName: "Stop keeping " + shareRow.names.name + " mounted"
          onClicked: root.stopKeepingShare(shareRow.modelData)
        }
      }
    }
  }

  RowLayout {
    spacing: Style.spacing.md

    Button {
      focusable: true
      bordered: true
      text: "Keep a share mounted…"
      onClicked: root.inTerminal(["karchy-mount-keep"])
    }
    InfoTip {
      subject: "kept shares"
      text: "A kept share appears under /mnt and connects when it is opened."
    }
  }

  SettingsHeader { text: "USB drives" }

  Note {
    visible: root.loaded && root.removableNames.length === 0
    text: "No USB drives plugged in."
  }

  Repeater {
    model: root.removableNames
    delegate: DiskCard {
      required property string modelData
      diskName: modelData
    }
  }
}
