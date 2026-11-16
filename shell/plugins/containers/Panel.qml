import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Containers in the bar (D-63): an icon with a count that shows only while
// containers run, so one left running in the background is never forgotten.
// Its panel answers "what runs, and is it OK?": up to six running containers
// with their run switch and "Open <port>". Enter (or "Manage containers…")
// opens the window (Window.qml) at the container under the cursor; logs,
// Compose projects, images, removing and pruning live there. Both read the
// same Model.js and draw the same ContainerRow. Everything goes through
// `karchy-containers`, which answers for Podman, or Docker when that is the
// engine.
//
// No polling while closed: `karchy-containers watch` streams container
// events, and the count is read again after each burst. With neither engine
// installed the watcher exits at once and the icon stays hidden until
// `karchy-shell karchy.containers refresh` (the Containers feature calls it).
Panel {
  id: root
  moduleName: "karchy.containers"
  ipcTarget: "karchy.containers"
  // manageIpc: false so this panel can own the target's one IpcHandler —
  // needed for refresh below.
  manageIpc: false

  property bool engineAvailable: false
  property string engine: ""
  property var running: []
  // The full list, read only while the panel is open.
  property var containers: []
  // Container id or project name -> the action under way.
  property var busy: ({})
  property int watchBackoff: 5000
  property bool watchRestartNow: false
  property int cursorIndex: -1
  // Which of the cursor row's controls the keyboard is on (h/l); -1 the row
  // itself, where Enter opens the window at that container.
  property int actionIndex: -1
  property int lastRow: -1

  readonly property int runningCount: running.length
  readonly property bool shown: runningCount > 0 || opened
  // The panel lists at most this many; the window has the rest.
  readonly property int maxRows: 6
  readonly property var allRows: Model.sorted(containers).filter(Model.isRunning)
  readonly property var rows: allRows.slice(0, maxRows)
  readonly property int moreCount: Math.max(0, allRows.length - rows.length)

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  function refresh() {
    if (!watchProc.running && !watchRestart.running && !watchRestartNow) watchProc.running = true
    summaryProc.request()
    if (opened) listProc.request()
  }

  function setBusy(key, action) {
    var next = Object.assign({}, busy)
    if (action) next[key] = action
    else delete next[key]
    busy = next
  }

  function act(key, args) {
    setBusy(key, Model.busyLabel(args))
    var proc = actionComponent.createObject(root, { key: key, command: ["karchy-containers"].concat(args) })
    proc.running = true
  }

  // Pages open in their own windows, which take the focus.
  function openPort(c) {
    if (!c || !c.ports || c.ports.length === 0) return
    Quickshell.execDetached(["xdg-open", Model.portUrl(c.ports[0])])
    root.close()
  }
  function power(c) {
    if (!c || busy[c.id]) return
    act(c.id, [Model.switchAction(c), c.id])
  }
  // The window, at the container the cursor is (or last was) on.
  function manage() {
    var c = lastRow >= 0 && lastRow < rows.length ? rows[lastRow] : null
    Quickshell.execDetached(["karchy-containers", "open"].concat(c ? [c.name] : []))
    root.close()
  }

  function actionsFor(c) {
    if (!c) return []
    return (c.ports && c.ports.length > 0 ? ["open"] : []).concat(["power"])
  }

  // The Manage button closes the list.
  function moveCursor(dy) {
    var count = rows.length + 1
    cursorIndex = cursorIndex < 0 ? 0 : (cursorIndex + dy + count) % count
    actionIndex = -1
  }
  function moveAction(dx) {
    var c = cursorContainer()
    if (!c) return
    actionIndex = Math.max(-1, Math.min(actionsFor(c).length - 1, actionIndex + dx))
  }
  function cursorContainer() {
    return cursorIndex >= 0 && cursorIndex < rows.length ? rows[cursorIndex] : null
  }
  function activateCursor() {
    if (cursorIndex === rows.length) { manage(); return }
    var c = cursorContainer()
    if (!c) return
    var action = actionIndex >= 0 ? actionsFor(c)[actionIndex] : ""
    if (action === "open") openPort(c)
    else if (action === "power") power(c)
    else manage()
  }

  onCursorIndexChanged: if (cursorIndex >= 0 && cursorIndex < rows.length) lastRow = cursorIndex
  onOpenedChanged: {
    cursorIndex = -1
    actionIndex = -1
    lastRow = -1
    if (opened) refresh()
  }
  onRowsChanged: if (cursorIndex > rows.length) cursorIndex = rows.length

  ShellIpc {
    target: "karchy.containers"

    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { if (root.shown) root.toggle() }
    // An engine was added or removed: start watching afresh.
    function refresh() {
      root.watchBackoff = 5000
      watchRestart.stop()
      if (watchProc.running) {
        root.watchRestartNow = true
        watchProc.running = false
      }
      root.refresh()
    }
  }

  // Streams one line per container event; "ready" first.
  Process {
    id: watchProc
    command: ["karchy-containers", "watch"]
    running: true
    stdout: SplitParser {
      onRead: function(line) {
        if (line === "ready") {
          root.engineAvailable = true
          root.watchBackoff = 5000
          root.refresh()
        } else {
          eventSettle.restart()
        }
      }
    }
    onExited: function(code) {
      if (root.watchRestartNow) {
        root.watchRestartNow = false
        watchProc.running = true
        return
      }
      if (code === 3) {
        // No engine: nothing can run, so nothing to show or watch.
        root.engineAvailable = false
        root.running = []
        root.containers = []
        return
      }
      watchRestart.interval = root.watchBackoff
      root.watchBackoff = Math.min(root.watchBackoff * 2, 300000)
      watchRestart.start()
    }
  }

  Timer { id: watchRestart; onTriggered: watchProc.running = true }
  // Compose starts and stops several containers at once; read once after.
  Timer { id: eventSettle; interval: 400; onTriggered: root.refresh() }
  // Status text ("Up 5 minutes") only changes with time, so only an open
  // panel reads it again.
  Timer { interval: 10000; repeat: true; running: root.opened; onTriggered: root.refresh() }

  Query {
    id: summaryProc
    command: ["karchy-containers", "summary"]
    onResult: function(text) {
      // No answer means no engine (any more): nothing runs.
      var data = Model.parse(text, null)
      root.engine = data ? data.engine || "" : ""
      root.running = data ? data.running || [] : []
    }
  }

  Query {
    id: listProc
    command: ["karchy-containers", "list"]
    onResult: function(text) {
      var data = Model.parse(text, null)
      root.containers = data ? data.containers || [] : []
    }
  }

  Component {
    id: actionComponent
    Process {
      property string key: ""
      onExited: {
        root.setBusy(key, "")
        root.refresh()
        destroy()
      }
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Icons.glyph("containers")
    labelText: root.runningCount > 0 && !vertical ? Commons.I18n.formatNumber(root.runningCount) : ""
    slotSize: Style.bar.iconSlot * (labelText !== "" ? 1.6 : 1)
    tooltipText: root.opened ? "" : Model.tooltip(root.running)
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
      onTextKey: function(t) {
        if (t === "m") root.manage()
        else if (t === "o") root.openPort(root.cursorContainer())
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        PanelHero {
          iconText: Icons.glyph("containers")
          title: "Containers"
          meta: (root.runningCount === 0 ? "Nothing running" : root.runningCount + " running")
            + (root.engine ? " · " + root.engine : "")
          metaColor: root.runningCount > 0 ? Commons.Color.status.success : dim
          fontFamily: root.bar.fontFamily
        }

        PanelSeparator { foreground: root.panelText }

        Column {
          visible: root.rows.length > 0
          width: parent.width
          spacing: Style.spacing.md

          PanelSectionHeader {
            text: "Running"
            foreground: root.panelText
            surface: root.panelSurface
            fontFamily: root.bar.fontFamily
          }

          Repeater {
            model: root.rows
            delegate: ContainerRow {
              required property var modelData
              required property int index
              width: parent.width
              container: modelData
              busyText: root.busy[modelData.id] || ""
              hasCursor: root.cursorIndex === index
              // The pointer on a row hovers the row; only the keyboard cursor
              // marks which of its controls Enter would use.
              actionCursor: root.cursorIndex === index && InputMode.keyboard ? root.actionIndex : -1
              foreground: root.panelText
              surface: root.panelSurface
              fontFamily: root.bar.fontFamily
              onPointerEntered: { root.cursorIndex = index; root.actionIndex = -1 }
              onActionHovered: function(i) { root.cursorIndex = index; root.actionIndex = i }
              onClicked: { root.cursorIndex = index; root.manage() }
              onOpenRequested: root.openPort(modelData)
              onPowerToggled: root.power(modelData)
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
          iconName: "containers"
          title: listProc.loaded ? "Nothing is running" : "Reading containers…"
          body: listProc.loaded ? "Containers you start with docker run or docker compose up show here." : ""
          foreground: root.panelText
          surface: root.panelSurface
          fontFamily: root.bar.fontFamily
        }

        PanelSeparator { foreground: root.panelText }

        Button {
          width: parent.width
          text: "Manage containers…"
          iconText: Icons.glyph("ui.open-external")
          bordered: true
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
          hasCursor: root.cursorIndex === root.rows.length
          onClicked: root.manage()
          onHovered: function(h) { if (h) root.cursorIndex = root.rows.length }
        }
      }
    }
  }

  // A read that can be asked for again while running; it runs once more
  // after, so the newest state always lands.
  component Query: Process {
    id: query
    property bool again: false
    property bool loaded: false
    signal result(string text)

    function request() {
      if (running) again = true
      else running = true
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        query.loaded = true
        query.result(text)
      }
    }
    onExited: if (again) {
      again = false
      running = true
    }
  }
}
