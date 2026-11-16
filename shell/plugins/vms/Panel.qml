import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// VMs in the bar (D-63): an icon that is there only while a VM runs, so one
// running in the background is never forgotten, and a panel that answers
// "what runs, and is it OK?": up to six VMs (running first) with their run
// switch and "Show its screen". "Manage virtual machines…" opens the window
// (Window.qml) at the VM under the cursor; creating, settings, snapshots,
// forcing off and deleting live there. Both read the same Model.js and draw
// the same VmRow.
//
// Nothing polls while the panel is closed: karchy-vm tells the shell over
// `karchy-shell karchy.vms refresh` whenever a VM starts, stops or changes,
// and the widget reads `karchy-vm list --json` once at load, which catches
// VMs that kept running across a shell restart.
Panel {
  id: root
  moduleName: "karchy.vms"
  ipcTarget: "karchy.vms"
  // Owns its IpcHandler for the refresh method below.
  manageIpc: false

  property var vms: []
  property var cpuPercent: ({})
  property var cpuPrev: ({})
  // name -> what the panel asked for ("Starting…"), until the state moves.
  property var pending: ({})
  property bool refreshQueued: false
  property int cursorIndex: -1
  property int actionIndex: 0

  // The panel lists at most this many; the window has the rest.
  readonly property int maxRows: 6
  readonly property var allRows: Model.sorted(vms)
  readonly property var rows: allRows.slice(0, maxRows)
  readonly property int moreCount: Math.max(0, allRows.length - rows.length)
  readonly property var running: Model.runningNames(vms)
  readonly property bool anyRunning: running.length > 0
  // Stays while open, so shutting the last VM down doesn't pull the panel
  // away mid-look.
  readonly property bool shown: anyRunning || opened
  // The count widens the button; center the open-panel mark on all of it.
  readonly property Item openPanelIndicatorItem: opened ? button : null

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  function refresh() {
    if (listProc.running) { refreshQueued = true; return }
    listProc.running = true
  }

  // A stop's ExecStopPost calls refresh while systemd still reports the unit
  // as stopping, so look once more when that has settled.
  function refreshAll() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    for (var i = 0; i < items.length; i++) {
      if (items[i] && typeof items[i].refresh === "function") {
        items[i].refresh()
        items[i].settleRefresh()
      }
    }
  }

  function settleRefresh() { settleTimer.restart() }

  function update(text) {
    var list = Model.parse(text)
    if (list === null) return
    var sample = Model.sampleCpu(list, cpuPrev, Date.now())
    cpuPercent = sample.percent
    cpuPrev = sample.prev
    // Keep a pending label until the VM leaves the state it was in.
    var nextPending = {}
    for (var name in pending) {
      var vm = Model.find(list, name)
      if (vm && vm.state === pending[name].from && Date.now() - pending[name].at < 120000) nextPending[name] = pending[name]
    }
    pending = nextPending
    vms = list
  }

  function setPending(name, label, from) {
    var next = Object.assign({}, pending)
    next[name] = { label: label, from: from, at: Date.now() }
    pending = next
  }

  function act(vm, action) {
    if (!vm) return
    if (action === "open") {
      Quickshell.execDetached(["karchy-vm", "open", vm.name])
      close()
      return
    }
    if (action === "power") action = Model.switchAction(vm)
    if (pending[vm.name]) return
    setPending(vm.name, Model.pendingLabel(action), vm.state)
    // Detached: stop waits for the guest, and the refresh comes back over IPC.
    Quickshell.execDetached(["karchy-vm", action, vm.name])
  }

  // The window, at the VM the cursor is (or last was) on.
  property int lastRow: -1
  onCursorIndexChanged: if (cursorIndex >= 0 && cursorIndex < rows.length) lastRow = cursorIndex
  function manage() {
    var vm = lastRow >= 0 && lastRow < rows.length ? rows[lastRow] : null
    close()
    Quickshell.execDetached(["karchy-vm", "manage"].concat(vm ? [vm.name] : []))
  }

  // Enter does the first: show a running VM's screen, start a stopped one.
  // Shutting down takes l (or the pointer) first, so Enter never stops a VM.
  function actionsFor(vm) {
    if (!vm) return []
    if (vm.state === "running") return ["open", "power"]
    return ["power"]
  }

  function moveCursor(dy) {
    var count = rows.length + 1  // the Manage button closes the list
    cursorIndex = cursorIndex < 0 ? 0 : (cursorIndex + dy + count) % count
    actionIndex = 0
  }

  function moveAction(dx) {
    if (cursorIndex < 0 || cursorIndex >= rows.length) return
    var n = actionsFor(rows[cursorIndex]).length
    actionIndex = Math.max(0, Math.min(n - 1, actionIndex + dx))
  }

  function activateCursor() {
    if (cursorIndex === rows.length) { manage(); return }
    var vm = rows[cursorIndex]
    var actions = actionsFor(vm)
    if (actions.length > 0) act(vm, actions[Math.min(actionIndex, actions.length - 1)])
  }

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      cursorIndex = -1
      lastRow = -1
      refresh()
    }
  }

  Process {
    id: listProc
    command: ["karchy-vm", "list", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.update(text) }
    onExited: {
      if (root.refreshQueued) {
        root.refreshQueued = false
        Qt.callLater(root.refresh)
      }
    }
  }

  // Live figures only while someone is looking.
  Timer { interval: 2000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  Timer { id: settleTimer; interval: 1500; onTriggered: root.refresh() }

  ShellIpc {
    target: "karchy.vms"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { if (root.shown) root.toggle() }
    function refresh(): void { root.refreshAll() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Icons.glyph("vms")
    labelText: root.running.length > 0 && !vertical ? String(root.running.length) : ""
    slotSize: Style.bar.iconSlot * (labelText !== "" ? 1.6 : 1)
    tooltipText: root.running.length === 1
      ? "VM running: " + root.running[0]
      : "VMs running: " + root.running.join(", ")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.manage()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.spacing.panelWidth)
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveAction(dx)
      }
      onActivateRequested: if (root.cursorIndex >= 0) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "m") root.manage() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        PanelHero {
          iconText: Icons.glyph("vms")
          title: "Virtual machines"
          meta: root.running.length > 0 ? root.running.length + " running" : (root.vms.length > 0 ? "None running" : "")
          metaColor: root.running.length > 0 ? Commons.Color.status.success : dim
          fontFamily: root.bar.fontFamily
        }

        PanelSeparator { foreground: root.panelText }

        Column {
          visible: root.rows.length > 0
          width: parent.width
          spacing: Style.spacing.md

          Repeater {
            model: root.rows
            delegate: Column {
              id: entry
              required property var modelData
              required property int index
              // A header where a section starts: running, then stopped.
              readonly property bool firstOfSection: index === 0
                || Model.isRunning(root.rows[index - 1]) !== Model.isRunning(modelData)
              width: parent.width
              spacing: Style.spacing.md

              PanelSectionHeader {
                visible: entry.firstOfSection
                topPadding: entry.index > 0 ? Style.spacing.lg : Math.ceil(fontSize * 0.15)
                text: Model.isRunning(entry.modelData) ? "Running" : "Stopped"
                foreground: root.panelText
                surface: root.panelSurface
                fontFamily: root.bar.fontFamily
              }

              VmRow {
                width: parent.width
                vm: entry.modelData
                cpuPercent: root.cpuPercent[entry.modelData.name]
                pending: root.pending[entry.modelData.name] ? root.pending[entry.modelData.name].label : ""
                hasCursor: root.cursorIndex === entry.index
                // The pointer on a row hovers the row; only the keyboard
                // cursor marks which of its controls Enter would use.
                actionCursor: root.cursorIndex === entry.index && InputMode.keyboard ? root.actionIndex : -1
                foreground: root.panelText
                surface: root.panelSurface
                fontFamily: root.bar.fontFamily
                onPointerEntered: { root.cursorIndex = entry.index; root.actionIndex = 0 }
                onActionHovered: function(i) { root.cursorIndex = entry.index; root.actionIndex = i }
                onClicked: if (entry.modelData.state === "running") root.act(entry.modelData, "open")
                onOpenRequested: root.act(entry.modelData, "open")
                onPowerToggled: root.act(entry.modelData, "power")
              }
            }
          }

          Text {
            visible: root.moreCount > 0
            width: parent.width
            textFormat: Text.PlainText
            text: root.moreCount + " more in the window"
            color: Commons.Color.secondaryText(root.panelText, root.panelSurface)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }
        }

        EmptyState {
          visible: root.rows.length === 0
          width: parent.width
          iconName: "vms"
          title: "No virtual machines yet"
          body: "Create one in the window: pick an installer ISO and it boots."
          foreground: root.panelText
          surface: root.panelSurface
          fontFamily: root.bar.fontFamily
        }

        PanelSeparator { foreground: root.panelText }

        Button {
          width: parent.width
          text: "Manage virtual machines…"
          iconText: Icons.glyph("ui.open-external")
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
          bordered: true
          hasCursor: root.cursorIndex === root.rows.length
          onClicked: root.manage()
          onHovered: function(h) { if (h) root.cursorIndex = root.rows.length }
        }
      }
    }
  }
}
