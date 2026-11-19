import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "StorageModel.js" as Model

// One volume of a disk on Settings › Storage: its name, where it is mounted
// and how full it is right now (the filesystem's own totals, read again
// every two seconds while the page is open), then what can be done with it.
// A btrfs filesystem can also show the breakdown that "Measure now" counts:
// what its files hold against what they take on the disk. That part carries
// its date and never a figure that was not counted. The system disk carries
// the switch for background deduplication.
ColumnLayout {
  id: root

  // The Storage page: `usage`, `measurement`, `bees`, `nowMs`, `acting`, `error`,
  // `errorKey` and the functions that carry out each action.
  property var page: null
  property var disk: ({})
  property var volume: ({})

  readonly property bool mounted: (volume.mounts || []).length > 0
  readonly property bool btrfs: volume.fstype === "btrfs" && mounted
  // Now: size, bytes on the disk, room left. null when not mounted.
  readonly property var live: mounted ? Model.live(volume, page && volume.uuid ? page.usage[volume.uuid] : null) : null
  // As of the last "Measure now".
  readonly property var figures: Model.figures(volume.measured)
  readonly property var bars: Model.bars(volume)
  readonly property bool measuring: !!page && page.measurement.running === true
  readonly property string name: Model.volumeName(volume)
  // Replaced only when the set of actions changes, so a refresh doesn't
  // rebuild the buttons (and take the keyboard out of them).
  property var actions: []
  function syncActions() {
    var next = Model.volumeActions(root.volume, root.disk)
    if (next.join(" ") === root.actions.join(" ")) return
    // The keyboard was on one of the buttons (Unmount, just pressed): it
    // goes to the first of the new ones instead of nowhere.
    var inside = false
    for (var item = root.Window.activeFocusItem; item; item = item.parent)
      if (item === buttons) { inside = true; break }
    root.actions = next
    if (inside) Qt.callLater(function() {
      var first = buttonRepeater.itemAt(0)
      if (first) first.forceActiveFocus(Qt.TabFocusReason)
    })
  }
  onVolumeChanged: syncActions()
  onDiskChanged: syncActions()
  Component.onCompleted: syncActions()

  readonly property var actionLabels: ({
    open: "Open in Files", mount: "Mount", unmount: "Unmount", unlock: "Unlock…",
    keep: "Keep mounted…", unkeep: "Stop keeping mounted…", check: "Check for errors…",
    speedtest: "Speed test", password: "Change password…"
  })

  Layout.fillWidth: true
  spacing: Style.spacing.lg

  component Quiet: Text {
    textFormat: Text.PlainText
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  component Figure: Text {
    Layout.preferredWidth: Style.space(84)
    Layout.alignment: Qt.AlignVCenter
    horizontalAlignment: Text.AlignRight
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    font.features: { "tnum": 1 }
  }

  component RowLabel: Text {
    Layout.preferredWidth: Style.space(110)
    Layout.alignment: Qt.AlignVCenter
    textFormat: Text.PlainText
    color: Commons.Color.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  // A saving or a cost under the bars: its name (and what it means, behind
  // the (i)), then the amount in the figures' column.
  component Amount: RowLayout {
    id: amount
    property string label: ""
    property string explanation: ""
    property string value: ""
    property color valueColor: Commons.Color.foreground
    Layout.fillWidth: true
    spacing: Style.spacing.sm
    Text {
      textFormat: Text.PlainText
      text: amount.label
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
    InfoTip {
      visible: amount.explanation !== ""
      subject: amount.label
      text: amount.explanation
    }
    Item { Layout.fillWidth: true; implicitHeight: 1 }
    Figure { text: amount.value; color: amount.valueColor }
  }

  PanelSeparator { Layout.fillWidth: true }

  // Name, what it is and where, and the room left.
  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.lg

    Text {
      textFormat: Text.PlainText
      text: root.name
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.bold: true
      Layout.maximumWidth: Style.space(220)
      elide: Text.ElideRight
    }
    Quiet {
      Layout.fillWidth: true
      text: Model.volumeDetail(root.volume)
      elide: Text.ElideMiddle
    }
    BorderSurface {
      visible: !!root.volume.kept
      implicitWidth: keptText.implicitWidth + Style.spacing.md * 2
      implicitHeight: keptText.implicitHeight + Style.spacing.xxs * 2
      color: "transparent"
      borderSpec: Border.flat(Style.normalBorderColor, Style.border.control)
      Quiet { id: keptText; anchors.centerIn: parent; text: root.mounted ? "kept mounted" : "mounts at startup" }
    }
    Text {
      textFormat: Text.PlainText
      text: root.live && root.live.free !== null
        ? Model.bytes(root.live.free) + " free" : Model.bytes(root.volume.size)
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.features: { "tnum": 1 }
    }
  }

  // Now: how much of it is taken, from the filesystem itself.
  StorageMeter {
    visible: root.live !== null
    value: root.live ? root.live.share : 0
  }
  Quiet {
    visible: root.live !== null
    Layout.fillWidth: true
    Layout.topMargin: -Style.spacing.sm
    wrapMode: Text.Wrap
    font.features: { "tnum": 1 }
    text: Model.liveLine(root.live)
  }

  // The breakdown, which has to be counted: when it was, and counting again.
  RowLayout {
    visible: root.btrfs && !!root.page
    Layout.fillWidth: true
    spacing: Style.spacing.lg

    Quiet {
      Layout.fillWidth: true
      wrapMode: Text.Wrap
      text: {
        if (!root.page) return ""
        if (root.measuring) return "Counting what the files hold…"
        if (root.figures) return "Breakdown as counted " + Model.when(root.page.measurement.time, root.page.nowMs)
        if (root.volume.measured && root.volume.measured.error)
          return "The count " + Model.when(root.page.measurement.time, root.page.nowMs) + " failed here: this filesystem " + root.volume.measured.error + "."
        return "What sharing, compression and snapshots account for is counted only when you ask."
      }
    }
    Button {
      visible: !!root.page && root.page.measurement.available === true
      focusable: true
      bordered: true
      busy: root.measuring
      text: root.measuring ? "Measuring" : "Measure now"
      accessibleName: "Measure now, " + root.name
      onClicked: root.page.measure(root.volume.path)
    }
  }

  // Counted: what the files hold, what that takes, and where the disk ends,
  // on one scale.
  GridLayout {
    visible: root.figures !== null
    Layout.fillWidth: true
    columns: 3
    columnSpacing: Style.spacing.xl
    rowSpacing: Style.spacing.md

    RowLabel { text: "Your files" }
    StorageMeter { value: root.bars ? root.bars.files : 0; track: false; fillColor: Commons.Color.textSecondary }
    Figure { text: root.figures ? Model.bytes(root.figures.files) : "" }

    RowLabel { text: "Files on disk" }
    StorageMeter { value: root.bars ? root.bars.stored : 0 }
    Figure { text: root.figures ? Model.bytes(root.figures.stored) : "" }

    RowLabel { text: "Disk size"; color: Commons.Color.textSecondary }
    StorageMeter { value: root.bars ? root.bars.size : 0; mark: true }
    Figure { text: Model.bytes(root.volume.fsSize); color: Commons.Color.textSecondary }
  }

  ColumnLayout {
    visible: root.figures !== null
    Layout.fillWidth: true
    spacing: Style.spacing.sm

    Amount {
      label: "Saved by sharing"
      explanation: "Files that hold the same data store it once: copies made in the file manager or with cp, and what background deduplication finds. Counted over your files as they are now, not over snapshots."
      value: root.figures ? (root.figures.sharing > 0 || root.figures.overhead === 0 ? Model.bytes(root.figures.sharing) : "none") : ""
      valueColor: root.figures && root.figures.sharing > 0 ? Commons.Color.status.success : Commons.Color.foreground
    }
    Amount {
      visible: !!root.figures && root.figures.overhead > 0
      label: "Kept by partly rewritten files"
      explanation: "btrfs keeps a whole block of data while any part of it is in use, so files that were partly overwritten take more room than they hold. Right now that is more than sharing saves."
      value: root.figures ? Model.bytes(root.figures.overhead) : ""
    }
    Amount {
      label: "Saved by compression"
      value: root.figures ? Model.bytes(root.figures.compression) : ""
      valueColor: root.figures && root.figures.compression > 0 ? Commons.Color.status.success : Commons.Color.foreground
    }
    Amount {
      label: "Held only by snapshots"
      explanation: "On the disk only because a read-only snapshot still points at it, such as the snapshots taken before updates. Deleting snapshots frees it."
      value: !root.figures ? "" : root.figures.snapshots === null ? "not counted" : Model.bytes(root.figures.snapshots)
    }
  }

  // Background deduplication, on the system disk.
  RowLayout {
    visible: root.volume.role === "system" && !!root.page && root.page.bees.available === true
    Layout.fillWidth: true
    spacing: Style.spacing.lg

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs
      RowLayout {
        spacing: Style.spacing.sm
        Text {
          textFormat: Text.PlainText
          text: "Background deduplication"
          color: Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }
        InfoTip {
          subject: "Background deduplication"
          text: "Finds the same data in different files and stores it once (bees), while the computer is idle. The amount under it is bees' own running count since it started: an estimate of its work, not of what is saved now, because it starts again with bees and doesn't go down when those files are deleted. \"Measure now\" counts what sharing saves exactly."
        }
      }
      Quiet {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.page ? Model.beesLine(root.page.bees) : ""
      }
      Quiet {
        visible: text !== ""
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: root.page ? Model.beesTotal(root.page.bees, root.page.nowMs) : ""
      }
    }

    ButtonGroup {
      id: beesSwitch
      Layout.alignment: Qt.AlignVCenter
      enabled: !!root.page && !root.page.bees.lockedOff && root.page.acting === ""
      opacity: enabled ? 1 : 0.5
      spacing: Style.spacing.sm
      options: [{ value: "off", label: "Off" }, { value: "on", label: "On" }]
      value: root.page && root.page.bees.on ? "on" : "off"
      onChanged: function(value) { if (root.page && value !== beesSwitch.value) root.page.setBees(value === "on", root.volume.path) }
    }
  }

  // What a check of this filesystem found (karchy-disk-health's warnings).
  Repeater {
    model: root.volume.warnings || []
    delegate: InlineMessage {
      required property var modelData
      Layout.fillWidth: true
      kind: "warning"
      text: "The last check found errors: " + modelData.summary
      actionText: "Details…"
      onAction: root.page.inTerminal(["karchy-disk-health", "details", modelData.name])
    }
  }

  InlineMessage {
    Layout.fillWidth: true
    kind: "error"
    text: root.page && root.page.errorKey === root.volume.path ? root.page.error : ""
    dismissible: true
    onDismissed: root.page.error = ""
  }

  Flow {
    id: buttons
    visible: root.actions.length > 0
    Layout.fillWidth: true
    spacing: Style.spacing.md

    Repeater {
      id: buttonRepeater
      model: root.actions
      delegate: Button {
        required property string modelData
        focusable: true
        bordered: true
        text: root.actionLabels[modelData] || modelData
        accessibleName: text.replace("…", "") + ", " + root.name
        enabled: !!root.page && (root.page.acting === "" || busy)
        busy: !!root.page && root.page.acting === modelData + " " + root.volume.path
        onClicked: root.page.volumeAction(modelData, root.volume, root.disk)
      }
    }
  }
}
