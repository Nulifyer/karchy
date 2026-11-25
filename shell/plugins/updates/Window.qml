import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// The Updates window: what `karchy update` would install, read before it
// runs, and the release channel. Opened by the bar's updates indicator, the
// menu (Update), Settings › About and `karchy updates`.
//
// It checks with `karchy-update --plan` (no root, nothing installed) when it
// opens and on Check now (F5). Install runs `karchy update` in the floating
// terminal, which keeps the password prompt, AUR build review, config merges
// and the restart question where they work today; the window closes then.
// Switching channel runs `karchy channel set` the same way, after asking.
//
// Page: a PageHeader with the release, channel and check time, Check now and
// the one primary action; then Arch news (read before updating), karchy,
// apps, system components (the ones that need a restart first) and AUR
// packages, each a Section; then firmware (run by itself in a terminal) and
// the channel last.
//
// Narrow (a tile beside other windows): less padding at the sides, the
// header's buttons under the title, and a row keeps the name and the new
// version; the version it replaces and the package behind a friendly name
// are what a narrow row leaves out.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false

  property var plan: null
  property bool checking: false
  property double now: Date.now()
  // Channels with a release, from `karchy channel available`.
  property var channels: []
  property bool showAllSystem: false
  // System rows shown before "Show all".
  readonly property int systemShown: 8
  property var pendingConfirm: null

  readonly property string channel: plan && plan.channel ? plan.channel : ""
  readonly property bool hasError: plan !== null && !!plan.error
  readonly property int total: Model.count(plan)
  readonly property var karchyChanges: Model.ofKind(plan, "karchy")
  readonly property var appChanges: Model.apps(plan)
  readonly property var systemChanges: Model.system(plan)
  readonly property var aurChanges: Model.ofKind(plan, "aur")
  readonly property var retiredRemove: Model.retired(plan, "remove")
  readonly property var retiredKeep: Model.retired(plan, "keep")
  readonly property var restartParts: Model.restartParts(plan)

  // Less room at the sides in a narrow window, where the lists need it.
  readonly property bool narrow: window.width < Style.spacing.windowNarrow
  readonly property int pagePadding: narrow ? Style.spacing.panelPadding : Style.spacing.panelPadding * 2

  // `karchy-updates firmware` opens the window at its Firmware part.
  function open(payloadJson) {
    var payload = {}
    try { payload = JSON.parse(payloadJson || "{}") } catch (e) {}
    root.opened = true
    root.showAllSystem = false
    if (payload && payload.section === "firmware") revealFirmware.restart()
    // A check a minute old is still the answer; otherwise check again.
    if (!root.plan || root.hasError || Date.now() - Date.parse(root.plan.checked || "") > 60000) root.check()
    if (root.channels.length === 0) channelsProc.running = true
  }

  function close() {
    // shell.hide() calls back into close(); stop the second time round.
    if (!root.opened) return
    root.opened = false
    root.pendingConfirm = null
    if (root.shell && root.manifest) root.shell.hide(root.manifest.id)
  }

  function check() {
    if (planProc.running) return
    root.checking = true
    planProc.running = true
  }

  function install() {
    if (root.total === 0) return
    // Detached: the update reloads the shell, which ends its own children.
    Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", "karchy-update"])
    root.close()
  }

  function askSwitch(to) {
    if (to === root.channel) return
    root.pendingConfirm = {
      message: Model.switchMessage(root.channel, to),
      confirmText: "Switch to " + to,
      channel: to
    }
  }

  Process {
    id: planProc
    command: ["karchy-update", "--plan"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.plan = Model.parse(text)
        root.checking = false
        root.now = Date.now()
      }
    }
    onExited: function(code) {
      if (code !== 0 && root.checking) {
        root.plan = { error: "The update check stopped before it finished.", changes: [], news: [], release: {} }
        root.checking = false
      }
    }
  }

  // Firmware updates come through fwupd, which needs UEFI firmware to talk
  // to (or is already installed for some other device).
  property bool firmwareApplies: false
  Process {
    running: true
    command: ["sh", "-c", "[ -d /sys/firmware/efi ] || command -v fwupdmgr >/dev/null"]
    onExited: function(code) { root.firmwareApplies = code === 0 }
  }

  // Once the window is laid out: the keyboard on the Firmware button, and
  // the button in view.
  Timer {
    id: revealFirmware
    interval: 150
    onTriggered: {
      if (!root.firmwareApplies) return
      firmwareButton.forceActiveFocus()
      var top = firmwareSection.mapToItem(page, 0, 0).y
      content.contentY = Math.max(0, Math.min(top, content.contentHeight - content.height))
    }
  }

  Process {
    id: channelsProc
    command: ["karchy-channel", "available"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.channels = text.split("\n").filter(function(c) { return c !== "" })
    }
  }

  // "Checked 5 min ago" stays true while the window is open.
  Timer {
    interval: 30000
    repeat: true
    running: root.opened
    onTriggered: root.now = Date.now()
  }

  // One row of a list: the name (and, quieter, the package behind a friendly
  // name), then old → new (or `detail`, such as a news post's date), and a
  // restart note.
  component ChangeRow: RowLayout {
    property string name: ""
    property string secondary: ""
    property string oldVersion: ""
    property string newVersion: ""
    property string detail: ""
    property bool restart: false
    // The page's width (`page` below), from the window: the columns are
    // sized from it and not from the row's own width, which the layout sets
    // from those very sizes ("recursive rearrange" in the log).
    readonly property real room: Math.max(0, Math.min(Window.width - root.pagePadding * 2, Style.spacing.pageMaxWidth))
    // Too narrow for a pair of versions beside the name: the new one stays.
    readonly property bool compact: room < Style.spacing.formWide
    Layout.fillWidth: true
    spacing: Style.spacing.lg
    Text {
      id: nameText
      text: parent.name
      color: Commons.Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      // Long names (a news title) give way before the version column does;
      // beside a pair of versions the name keeps what they leave.
      // In a narrow row the name has what the rest leaves, and gives way first.
      Layout.fillWidth: parent.compact
      Layout.maximumWidth: parent.compact ? Number.POSITIVE_INFINITY : Math.round(parent.room * (parent.detail !== "" ? 0.65 : 0.36))
    }
    Text {
      visible: parent.secondary !== "" && !parent.compact
      text: parent.secondary
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
    Item { visible: !parent.compact; Layout.fillWidth: true }
    Text {
      visible: parent.restart
      text: "Restart"
      color: Commons.Color.status.warning
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
    }
    // A news post's date, or anything else that isn't a pair of versions.
    Text {
      visible: parent.detail !== ""
      text: parent.detail
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      font.features: { "tnum": 1 }
    }
    // Old and new are two texts, each cut at its own end: one text elided in
    // the middle ran a long version's tail into the next one's head, and the
    // arrow between them was the part that went.
    RowLayout {
      id: versions
      visible: parent.detail === ""
      spacing: Style.spacing.md
      readonly property var pair: Model.versionPair(parent.oldVersion, parent.newVersion)
      // Room for a nightly version (0.1.0rc5.r149.g8e001de-1) in each column.
      readonly property real column: parent.compact ? Math.round(parent.room * 0.4)
        : Math.max(Style.space(96), Math.round((parent.room * 0.6 - arrow.implicitWidth) / 2 - spacing))
      Text {
        visible: !versions.parent.compact
        text: versions.pair.old !== "" ? versions.pair.old : "new"
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.features: { "tnum": 1 }
        Layout.maximumWidth: versions.column
        elide: versions.pair.tails ? Text.ElideLeft : Text.ElideRight
      }
      Text {
        id: arrow
        visible: !versions.parent.compact
        textFormat: Text.PlainText
        text: Icons.glyph("ui.arrow.right")
        color: Commons.Color.textSecondary
        font.family: Icons.family
        font.pixelSize: Style.font.iconSmall
      }
      Text {
        text: versions.pair.next
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.features: { "tnum": 1 }
        Layout.maximumWidth: versions.column
        elide: versions.pair.tails ? Text.ElideLeft : Text.ElideRight
      }
    }
  }

  // The shell brings the window to the front by this title when it is asked
  // for while open (shell.qml, summon), and Hyprland's rules match it.
  readonly property string windowTitle: "Updates"

  // On a floating workspace the window opens at its own size (D-175).
  OwnSize {
    title: root.windowTitle
    active: root.opened
    width: window.implicitWidth
    height: window.implicitHeight
  }

  FloatingWindow {
    id: window
    visible: root.opened
    title: root.windowTitle
    color: Commons.Color.background
    readonly property var fitScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
      ? Hyprland.focusedMonitor.lastIpcObject : null
    readonly property real screenWidth: fitScreen ? fitScreen.width / fitScreen.scale : 1280
    readonly property real screenHeight: fitScreen ? fitScreen.height / fitScreen.scale : 800
    implicitWidth: Math.round(Math.min(Style.space(760), screenWidth * 0.85))
    implicitHeight: Math.round(Math.min(Style.space(640), screenHeight * 0.85))

    onVisibleChanged: {
      if (!visible && root.opened) root.close()
      if (visible) Qt.callLater(function() { (primaryButton.visible ? primaryButton : checkButton).forceActiveFocus() })
    }

    Shortcut {
      sequence: "F5"
      enabled: root.opened && !confirmDialog.opened
      onActivated: root.check()
    }

    ColumnLayout {
      id: frame
      anchors.fill: parent
      spacing: 0
      Keys.onEscapePressed: root.close()

      // The header stays put while the lists scroll: the action is always in reach.
      PageHeader {
        Layout.fillWidth: true
        Layout.leftMargin: root.pagePadding
        Layout.rightMargin: root.pagePadding
        Layout.maximumWidth: Style.spacing.pageMaxWidth
        Layout.topMargin: Style.spacing.panelPadding
        Layout.bottomMargin: Style.spacing.lg
        iconName: "update"
        title: "Updates"
        status: {
          var parts = []
          if (root.plan && root.plan.release.installed) parts.push("karchy " + Model.shortVersion(root.plan.release.installed))
          if (root.channel !== "") parts.push(root.channel + " channel")
          if (root.checking) parts.push("checking…")
          else if (root.plan && root.plan.checked) parts.push("checked " + Model.ago(root.plan.checked, root.now))
          return Model.statusLine(parts)
        }
        explanation: "Install runs karchy update in a terminal: it asks for your password once, takes a snapshot before and after (both appear in the boot menu), lets you review AUR build files, and offers a restart when the kernel or drivers changed."

        Button {
          id: checkButton
          focusable: true
          text: "Check now"
          tooltipText: "Check for updates again (F5)"
          busy: root.checking
          onClicked: root.check()
        }
        Button {
          id: primaryButton
          // Nothing to install: the page says so instead.
          visible: root.total > 0
          focusable: true
          variant: "primary"
          text: Model.installLabel(root.plan)
          enabled: !root.checking
          onClicked: root.install()
        }
      }

      Flickable {
        id: content
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: page.implicitHeight + Style.spacing.panelPadding * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ListScrollBar {}

        ColumnLayout {
          id: page
          x: root.pagePadding
          y: Style.spacing.lg
          width: Math.min(content.width - root.pagePadding * 2, Style.spacing.pageMaxWidth)
          spacing: Style.spacing.xxl

          InlineMessage {
            Layout.fillWidth: true
            kind: "error"
            text: root.hasError ? root.plan.error : ""
            details: root.hasError && root.plan.details ? root.plan.details : ""
            actionText: "Try again"
            onAction: root.check()
          }

          // First check, nothing to show yet.
          EmptyState {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(60)
            visible: root.plan === null
            centered: true
            busy: true
            title: "Checking for updates"
            body: ""
          }

          EmptyState {
            Layout.fillWidth: true
            Layout.topMargin: Style.space(40)
            visible: root.plan !== null && !root.hasError && root.total === 0
            centered: true
            iconName: "update"
            title: "Everything is up to date"
            body: root.plan && root.plan.checked ? "Checked " + Model.ago(root.plan.checked, root.now) + ". karchy checks by itself every 6 hours." : ""
          }

          // Arch's own announcements: some ask for a manual step before or
          // after updating, so they come first.
          Section {
            Layout.fillWidth: true
            visible: root.total > 0 && root.plan.news.length > 0
            title: "Arch news since your last update"
            subtitle: "Read these before installing; some need a step by hand."
            trailing: Button {
              focusable: true
              text: "Open Arch news"
              onClicked: Quickshell.execDetached(["xdg-open", "https://archlinux.org/news/"])
            }
            Repeater {
              model: root.plan ? root.plan.news : []
              delegate: ChangeRow {
                required property var modelData
                name: modelData.title
                detail: modelData.date
              }
            }
          }

          Section {
            Layout.fillWidth: true
            visible: root.karchyChanges.length > 0
            title: root.plan && root.plan.release.available ? "karchy " + root.plan.release.installed : "karchy"
            titleTo: root.plan && root.plan.release.available ? root.plan.release.available : ""
            subtitle: Model.plural(root.karchyChanges.length, "package", "packages")
              + (root.plan && root.plan.release.available ? ": a new release" : ": updated parts of this release")
            trailing: Button {
              focusable: true
              visible: !!(root.plan && root.plan.release.notes)
              text: "Release notes"
              onClicked: Quickshell.execDetached(["xdg-open", root.plan.release.notes])
            }
            Repeater {
              model: root.karchyChanges
              delegate: ChangeRow {
                required property var modelData
                name: modelData.name
                oldVersion: modelData.old
                newVersion: modelData.new
              }
            }
          }

          Section {
            Layout.fillWidth: true
            visible: root.appChanges.length > 0
            title: "Apps"
            subtitle: Model.plural(root.appChanges.length, "app", "apps")
            Repeater {
              model: root.appChanges
              delegate: ChangeRow {
                required property var modelData
                name: modelData.app
                oldVersion: modelData.old
                newVersion: modelData.new
              }
            }
          }

          // Usually the longest list: the restart ones show, the rest one click away.
          Section {
            Layout.fillWidth: true
            visible: root.systemChanges.length > 0
            title: "System"
            subtitle: Model.plural(root.systemChanges.length, "component", "components")
              + (root.restartParts.length > 0 ? ". Restart afterwards: " + root.restartParts.join(", ") + "." : "")
            trailing: Button {
              focusable: true
              visible: root.systemChanges.length > root.systemShown
              text: root.showAllSystem ? "Show fewer" : "Show all " + root.systemChanges.length
              onClicked: root.showAllSystem = !root.showAllSystem
            }
            Repeater {
              model: root.showAllSystem ? root.systemChanges : root.systemChanges.slice(0, root.systemShown)
              delegate: ChangeRow {
                required property var modelData
                name: modelData.label
                secondary: modelData.label !== modelData.name ? modelData.name : ""
                oldVersion: modelData.old
                newVersion: modelData.new
                restart: modelData.restart
              }
            }
          }

          Section {
            Layout.fillWidth: true
            visible: root.aurChanges.length > 0
            title: "AUR"
            subtitle: "Built on this computer. The terminal shows each package's build files to review first."
            Repeater {
              model: root.aurChanges
              delegate: ChangeRow {
                required property var modelData
                name: modelData.name
                oldVersion: modelData.old
                newVersion: modelData.new
              }
            }
          }

          // Packages karchy no longer uses (D-108): removed by the update
          // when nothing else needs them; one you installed yourself stays.
          Section {
            Layout.fillWidth: true
            visible: root.retiredRemove.length + root.retiredKeep.length > 0
            title: "No longer part of karchy"
            subtitle: root.retiredKeep.length > 0
              ? "Removed by karchy when nothing else needs them. The ones you installed yourself stay."
              : "Removed by karchy when nothing else needs them."
            Repeater {
              model: root.retiredRemove
              delegate: ChangeRow {
                required property var modelData
                name: modelData
                detail: "Removed by karchy"
              }
            }
            Repeater {
              model: root.retiredKeep
              delegate: ChangeRow {
                required property var modelData
                name: modelData
                detail: "Kept: you installed it"
              }
            }
          }

          Text {
            visible: root.total > 0 && !!(root.plan && root.plan.size)
            text: root.plan && root.plan.size ? root.plan.size + " to download" : ""
            color: Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          // Not part of `karchy update`: firmware comes from the makers, is
          // rare, and can need a restart into the firmware's own updater, so
          // it runs by itself in a terminal, which lists what there is and
          // asks before installing.
          Section {
            id: firmwareSection
            Layout.fillWidth: true
            visible: root.firmwareApplies
            title: "Firmware"
            info: "For this computer's own firmware (BIOS) and its devices, from their makers through fwupd. The terminal lists what is available and asks before it installs anything."
            Button {
              id: firmwareButton
              focusable: true
              bordered: true
              text: "Check for firmware updates…"
              onClicked: Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", "karchy-update-firmware"])
            }
          }

          // Not on a dev checkout, which has no channel.
          Section {
            Layout.fillWidth: true
            visible: root.channel !== ""
            title: "Release channel"
            // A channel with no description of its own (dev) adds nothing.
            subtitle: (Model.channelText[root.channel] ? Model.channelText[root.channel] + ". " : "")
              + "Only karchy's own parts follow the channel; Arch, CachyOS and AUR packages update as usual."
            ButtonGroup {
              options: root.channels.length > 0 ? root.channels : [root.channel]
              value: root.channel
              // The group keeps showing the channel in use until a switch succeeds.
              onChanged: function(value) { root.askSwitch(value) }
            }
            Text {
              Layout.fillWidth: true
              visible: root.channels.length > 0 && root.channels.indexOf("stable") < 0
              text: "Stable appears here from karchy's first release."
              color: Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      ownsKeys: true
      destructive: false
      opened: root.pendingConfirm !== null
      message: root.pendingConfirm ? root.pendingConfirm.message : ""
      confirmText: root.pendingConfirm ? root.pendingConfirm.confirmText : ""
      onCanceled: root.pendingConfirm = null
      onConfirmed: {
        var to = root.pendingConfirm ? root.pendingConfirm.channel : ""
        root.pendingConfirm = null
        if (to === "") return
        // Detached: the switch reloads the shell, which ends its own children.
        Quickshell.execDetached(["karchy-launch-floating-terminal-with-presentation", "karchy-channel", "set", to])
        root.close()
      }
    }
  }
}
