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

// The Containers window (D-63): every container including stopped ones,
// Compose projects, images, logs, remove and prune. A normal application
// window like Settings, so it tiles, floats and closes like any other.
// Open it with `karchy containers open [name]` or "Manage containers…" in the
// bar panel, which opens it at the container under the panel's cursor.
// It reads through `karchy-containers` while open: on container events, and
// every 15 seconds for the status text.
//
// The engine is the person's choice (D-164): the window works with Podman or
// Docker, whichever is installed. With neither it says so and opens Quick
// install at the two; with both it shows Podman's and says why under its
// name; with one that doesn't answer (Docker before its group applies) it
// shows karchy-containers' sentence about it.
//
// Layout (docs/architecture.md, "Panels and windows"): a sidebar of
// containers drawn with the bar panel's ContainerRow (same names, icons,
// status lines and run switch), with Compose projects and images below it;
// then the page: a PageHeader with its one primary action, Cards, and what
// can't be undone apart at the bottom, confirmed with Cancel focused.
//
// Keyboard: Tab walks the filter, the container list, the Compose projects
// and Images buttons, then the page; j/k or Up/Down move through the list;
// Ctrl+F filters; Escape closes.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  // "container" (the one in `selectedId`), "projects" or "images".
  property string section: "container"
  property string selectedId: ""
  // A name asked for by `open`, picked once the list has it.
  property string wanted: ""
  property string filter: ""

  property string engine: ""
  // The other engine, when both are installed, and the command to type for
  // the one in use (karchy-containers list).
  property string also: ""
  property string cli: ""
  property bool noEngine: false
  // Why the installed engine gave no list; "" while it answers.
  property string engineError: ""
  property bool loaded: false
  property var containers: []
  property var projects: []
  property var images: []
  // Container id, project or image -> the action under way.
  property var busy: ({})
  property string errorText: ""
  property string errorDetails: ""
  property string logsText: ""
  property string logsId: ""
  property bool logsFollow: true
  property double now: Date.now()
  // The action the confirmation dialog runs.
  property var pendingConfirm: null

  // New log text arrived for the container on the page.
  signal logsUpdated()

  readonly property int runningCount: Model.runningCount(containers)
  readonly property var rows: Model.sorted(containers)
  readonly property var listRows: Model.filtered(rows, filter)
  readonly property var current: section === "container" ? Model.find(containers, selectedId) : null

  function open(payloadJson) {
    var payload = Model.parse(payloadJson || "{}", {})
    root.filter = ""
    if (payload.section) root.section = String(payload.section)
    if (payload.container) {
      root.section = "container"
      root.wanted = String(payload.container)
      root.pickWanted()
    }
    root.opened = true
    root.refresh()
  }

  function close() {
    // shell.hide() calls back into close(); stop the second time round.
    if (!root.opened) return
    root.opened = false
    root.pendingConfirm = null
    if (root.shell && root.manifest) root.shell.hide(root.manifest.id)
  }

  function refresh() {
    root.now = Date.now()
    listProc.request()
    imagesProc.request()
    if (root.current) logsProc.request()
  }

  function select(c) {
    root.section = "container"
    root.selectedId = c ? c.id : ""
  }

  // The container `dy` places from the selected one in the (filtered) list.
  function step(dy) {
    var list = root.listRows
    if (list.length === 0) return
    var i = -1
    for (var j = 0; j < list.length; j++) if (list[j].id === root.selectedId) i = j
    i = i < 0 ? 0 : Math.max(0, Math.min(list.length - 1, i + dy))
    root.select(list[i])
  }

  function pickWanted() {
    if (root.wanted === "") return
    var c = Model.find(root.containers, root.wanted)
    if (c) { root.select(c); root.wanted = "" }
  }

  // The run switch and the page's primary action: start or stop.
  function power(c) {
    if (!c || root.busy[c.id]) return
    var action = Model.switchAction(c)
    root.act(c.id, [action, c.id], action + " " + c.name)
  }

  onCurrentChanged: {
    var id = root.current ? root.current.id : ""
    if (id === root.logsId) return
    root.logsId = id
    root.logsText = ""
    if (id !== "") {
      logsProc.command = ["karchy-containers", "logs", id, "300"]
      logsProc.request()
    }
  }

  function setBusy(key, action) {
    var next = Object.assign({}, busy)
    if (action) next[key] = action
    else delete next[key]
    busy = next
  }

  function act(key, args, label) {
    root.errorText = ""
    root.errorDetails = ""
    setBusy(key, Model.busyLabel(args))
    var proc = actionComponent.createObject(root, { key: key, label: label || args[0], command: ["karchy-containers"].concat(args) })
    proc.running = true
  }

  // The confirmed action is kept as data: a function inside a var property
  // does not survive QML's conversion.
  function confirm(message, confirmText, key, args, label) {
    root.pendingConfirm = { message: message, confirmText: confirmText, key: key, args: args, label: label }
  }


  // ---------------------------------------------------------------- data

  onOpenedChanged: {
    if (opened) engineProc.running = true
    else watchProc.running = false
  }

  // Which engine, if any; then container events while the window is open.
  Process {
    id: engineProc
    command: ["karchy-containers", "engine"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.engine = text.trim() }
    onExited: function(code) {
      var arrived = root.noEngine && code === 0
      root.noEngine = code !== 0
      if (root.noEngine || !root.opened) return
      if (!watchProc.running) watchProc.running = true
      // An engine was installed while the window said there was none.
      if (arrived) root.refresh()
    }
  }

  Process {
    id: watchProc
    command: ["karchy-containers", "watch"]
    stdout: SplitParser { onRead: function(line) { if (line !== "ready") eventSettle.restart() } }
  }
  Timer { id: eventSettle; interval: 400; onTriggered: root.refresh() }
  // With no engine, the same tick looks for one instead (Quick install may
  // be adding it right now).
  Timer {
    interval: 15000; repeat: true; running: root.opened
    onTriggered: {
      if (root.noEngine) engineProc.running = true
      else root.refresh()
    }
  }
  Timer { interval: 3000; repeat: true; running: root.opened && root.current !== null && root.logsFollow; onTriggered: logsProc.request() }

  Query {
    id: listProc
    command: ["karchy-containers", "list"]
    onFailed: function(code, reason) {
      // 3: the engine was removed while the window was open.
      if (code === 3) { root.noEngine = true; root.engine = ""; root.also = "" }
      else root.engineError = reason || (Model.engineName(root.engine) || "The engine") + " did not answer."
      root.containers = []
      root.projects = []
    }
    onResult: function(text) {
      var data = Model.parse(text, null)
      if (!data) return
      root.noEngine = false
      root.engineError = ""
      root.engine = data.engine || root.engine
      root.also = data.also || ""
      root.cli = data.cli || ""
      root.containers = data.containers || []
      root.projects = data.projects || []
      root.loaded = true
      root.pickWanted()
      // Nothing chosen yet, or the chosen one is gone: the first in the list.
      if (root.section === "container" && !root.current) {
        var first = root.rows.length > 0 ? root.rows[0] : null
        root.selectedId = first ? first.id : ""
      }
    }
  }

  Query {
    id: imagesProc
    command: ["karchy-containers", "images"]
    onResult: function(text) { root.images = Model.parse(text, []) }
  }

  Query {
    id: logsProc
    onResult: function(text) {
      root.logsText = text
      root.logsUpdated()
    }
  }

  Component {
    id: actionComponent
    Process {
      id: action
      property string key: ""
      property string label: ""
      stderr: StdioCollector { id: actionErr; waitForEnd: true }
      onExited: function(code) {
        root.setBusy(action.key, "")
        if (code !== 0) {
          root.errorText = "Couldn't " + action.label + "."
          root.errorDetails = actionErr.text.trim()
        }
        root.refresh()
        action.destroy()
      }
    }
  }

  // --------------------------------------------------------------- window

  // Keep the focused control on screen as Tab walks down a long page.
  function revealFocused(item) {
    var p = item
    while (p && p !== pages) p = p.parent
    if (!p) return
    var margin = Style.spacing.panelPadding
    var top = item.mapToItem(content.contentItem, 0, 0).y
    var bottom = top + item.height
    var maxY = Math.max(0, content.contentHeight - content.height)
    if (top - margin < content.contentY) content.contentY = Math.max(0, top - margin)
    else if (bottom + margin > content.contentY + content.height)
      content.contentY = Math.min(maxY, bottom + margin - content.height)
  }

  // The shell brings the window to the front by this title when it is asked
  // for while open (shell.qml, summon), and Hyprland's rules match it.
  readonly property string windowTitle: "Containers"

  FloatingWindow {
    id: window
    visible: root.opened
    title: root.windowTitle
    color: Commons.Color.background
    // Fit the screen it opens on: 1000×680 where there is room, less where not.
    readonly property var fitScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
      ? Hyprland.focusedMonitor.lastIpcObject : null
    readonly property real screenWidth: fitScreen ? fitScreen.width / fitScreen.scale : 1280
    readonly property real screenHeight: fitScreen ? fitScreen.height / fitScreen.scale : 800
    implicitWidth: Math.round(Math.min(Style.space(1000), screenWidth * 0.85))
    implicitHeight: Math.round(Math.min(Style.space(680), screenHeight * 0.85))

    onVisibleChanged: {
      if (!visible && root.opened) root.close()
      // Start in the list, so j/k, Tab and Escape work at once.
      if (visible) Qt.callLater(function() { containerList.forceActiveFocus() })
    }

    Shortcut {
      sequence: "Ctrl+F"
      enabled: root.opened && !confirmDialog.opened
      onActivated: filterField.forceActiveFocus(Qt.ShortcutFocusReason)
    }
    Shortcut {
      sequence: "F5"
      enabled: root.opened
      onActivated: root.refresh()
    }

    RowLayout {
      id: frame
      anchors.fill: parent
      spacing: 0
      readonly property Item focusedItem: frame.Window.activeFocusItem
      onFocusedItemChanged: root.revealFocused(focusedItem)
      // Keys the focused control leaves unhandled end up here.
      Keys.onEscapePressed: root.close()

      // ---------- Sidebar ----------
      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: Style.space(270)
        color: Util.alpha(Commons.Color.foreground, 0.04)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.lg

          // The window's name, quieter than the page title beside it.
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.xxs
            Text {
              text: "Containers"
              color: Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              visible: root.engine !== ""
              Layout.fillWidth: true
              // No count from an engine that didn't answer.
              text: (root.engineError !== "" ? root.engine : root.runningCount + " running · " + root.engine).toUpperCase()
              color: root.runningCount > 0 ? Commons.Color.status.success : Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.font.labelSpacing
              elide: Text.ElideRight
            }
            // Both engines: which one this is, and why.
            Text {
              visible: text !== ""
              Layout.fillWidth: true
              Layout.topMargin: Style.spacing.xs
              text: Model.bothNote(root.engine, root.also)
              wrapMode: Text.Wrap
              color: Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
          }

          TextField {
            id: filterField
            visible: !root.noEngine && root.containers.length > 1
            Layout.fillWidth: true
            placeholderText: "Filter  (Ctrl+F)"
            onTextChanged: root.filter = text
            Keys.onEscapePressed: function(event) {
              if (text !== "") text = ""
              else containerList.forceActiveFocus(Qt.TabFocusReason)
            }
            Keys.onDownPressed: containerList.forceActiveFocus(Qt.TabFocusReason)
            onAccepted: {
              if (root.listRows.length > 0) root.select(root.listRows[0])
              containerList.forceActiveFocus(Qt.TabFocusReason)
            }
          }

          // One Tab stop; j/k or the arrows move the selection, and the page
          // follows it.
          Item {
            id: containerList
            Layout.fillWidth: true
            Layout.fillHeight: true
            activeFocusOnTab: !root.noEngine
            Accessible.role: Accessible.List
            Accessible.name: "Containers"

            Keys.onPressed: function(event) {
              InputMode.keyPressed()
              if (event.key === Qt.Key_Down || event.text === "j") { root.step(1); event.accepted = true }
              else if (event.key === Qt.Key_Up || event.text === "k") { root.step(-1); event.accepted = true }
              else if (event.key === Qt.Key_Home) { root.step(-100000); event.accepted = true }
              else if (event.key === Qt.Key_End) { root.step(100000); event.accepted = true }
            }

            Flickable {
              id: listFlick
              anchors.fill: parent
              clip: true
              contentHeight: listColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds

              Column {
                id: listColumn
                width: listFlick.width
                spacing: Style.spacing.sm

                Repeater {
                  model: root.listRows
                  delegate: ContainerRow {
                    required property var modelData
                    width: listColumn.width
                    container: modelData
                    busyText: root.busy[modelData.id] || ""
                    showOpen: false
                    current: root.section === "container" && root.selectedId === modelData.id
                    hasCursor: pointerOver || (containerList.activeFocus && current)
                    foreground: Commons.Color.foreground
                    surface: Commons.Color.background
                    onCurrentChanged: if (current) listFlick.contentY = Math.max(0, Math.min(y, listFlick.contentHeight - listFlick.height))
                    onClicked: {
                      root.select(modelData)
                      containerList.forceActiveFocus(Qt.MouseFocusReason)
                    }
                    onPowerToggled: root.power(modelData)
                  }
                }

                Text {
                  visible: root.loaded && root.containers.length > 0 && root.listRows.length === 0
                  width: parent.width
                  wrapMode: Text.Wrap
                  text: "No container matches “" + root.filter + "”."
                  color: Commons.Color.textSecondary
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }
          }

          PanelSeparator { Layout.fillWidth: true; visible: !root.noEngine }

          Button {
            Layout.fillWidth: true
            visible: !root.noEngine
            focusable: true
            leftAlign: true
            iconText: Icons.glyph("containers.compose")
            text: "Compose projects" + (root.projects.length > 0 ? "  " + root.projects.length : "")
            selected: root.section === "projects"
            onClicked: root.section = "projects"
          }
          Button {
            Layout.fillWidth: true
            visible: !root.noEngine
            focusable: true
            leftAlign: true
            iconText: Icons.glyph("containers.image")
            text: "Images" + (root.images.length > 0 ? "  " + root.images.length : "")
            selected: root.section === "images"
            onClicked: root.section = "images"
          }
        }
      }

      // ---------- Page ----------
      Flickable {
        id: content
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentWidth: width
        contentHeight: pages.implicitHeight + Style.spacing.panelPadding * 2
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ListScrollBar {}

        ColumnLayout {
          id: pages
          x: Style.spacing.panelPadding * 2
          y: Style.spacing.panelPadding
          width: content.width - Style.spacing.panelPadding * 4
          spacing: Style.spacing.xxl

          Loader {
            Layout.fillWidth: true
            active: root.opened
            sourceComponent: root.noEngine ? noEnginePage
              : root.engineError !== "" ? engineErrorPage
              : root.section === "projects" ? projectsPage
              : root.section === "images" ? imagesPage
              : root.current ? containerPage
              : emptyPage
          }
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      ownsKeys: true
      property Item returnFocus: null
      opened: root.pendingConfirm !== null
      onOpenedChanged: if (opened) returnFocus = frame.Window.activeFocusItem
      message: root.pendingConfirm ? root.pendingConfirm.message : ""
      confirmText: root.pendingConfirm ? root.pendingConfirm.confirmText : ""
      onCanceled: {
        root.pendingConfirm = null
        if (returnFocus) returnFocus.forceActiveFocus()
      }
      onConfirmed: {
        var action = root.pendingConfirm
        root.pendingConfirm = null
        if (returnFocus) returnFocus.forceActiveFocus()
        if (action) root.act(action.key, action.args, action.label)
      }
    }
  }

  // ----------------------------------------------------------------- pages

  Component {
    id: noEnginePage
    EmptyState {
      centered: true
      Layout.fillWidth: true
      iconName: "containers"
      title: "No container engine is installed"
      body: "Install Podman or Docker from Quick install › System, and your containers show here."
      actionText: "Open Quick install"
      // A search that finds exactly the two.
      onAction: Quickshell.execDetached(["karchy-quick-install", "window", "container engine"])
    }
  }

  Component {
    id: engineErrorPage
    EmptyState {
      centered: true
      Layout.fillWidth: true
      iconName: "containers"
      title: (Model.engineName(root.engine) || "The engine") + " isn't answering"
      body: root.engineError
      actionText: "Try again"
      onAction: root.refresh()
    }
  }

  Component {
    id: emptyPage
    EmptyState {
      centered: true
      Layout.fillWidth: true
      iconName: "containers"
      title: root.loaded ? "No containers yet" : "Reading containers…"
      body: root.loaded ? "Start one with " + Model.startHint(root.cli) + " and it shows here." : ""
    }
  }

  Component {
    id: containerPage
    ColumnLayout {
      id: page
      spacing: Style.spacing.xxl
      // The page outlives a removed container by a moment.
      readonly property var c: root.current || ({ id: "", name: "", state: "", ports: [] })
      readonly property bool running: Model.isRunning(c)
      readonly property string busyText: root.busy[c.id] || ""
      readonly property string role: Model.statusRole(c)

      PageHeader {
        iconName: Model.stateIcon(page.c.state)
        iconColor: page.role === "success" ? Commons.Color.status.success
          : page.role === "warning" ? Commons.Color.status.warning : Commons.Color.textSecondary
        title: page.c.name
        status: page.busyText !== "" ? page.busyText : (page.c.status || page.c.state)
        statusColor: page.busyText !== "" ? Commons.Color.status.warning
          : page.role === "success" ? Commons.Color.status.success
          : page.role === "warning" ? Commons.Color.status.warning : Commons.Color.textSecondary

        Button {
          visible: page.running
          focusable: true
          text: "Restart"
          iconText: Icons.glyph("ui.refresh")
          bordered: true
          enabled: page.busyText === ""
          onClicked: root.act(page.c.id, ["restart", page.c.id], "restart " + page.c.name)
        }
        Button {
          focusable: true
          variant: "primary"
          text: page.running ? "Stop" : "Start"
          iconText: Icons.glyph(page.running ? "media.stop" : "media.play")
          busy: page.busyText !== ""
          onClicked: root.power(page.c)
        }
      }

      Messages {}

      Section {
        title: "Overview"
        KeyValueGrid {
          Layout.fillWidth: true
          rows: [
            { label: "Image", value: Model.shortImage(page.c.image) },
            { label: "Compose project", value: page.c.project ? page.c.project + (page.c.service ? " · " + page.c.service : "") : "None" },
            { label: "Created", value: Model.ago(page.c.created, root.now) },
            { label: "ID", value: String(page.c.id || "").slice(0, 12) }
          ]
        }
      }

      Section {
        visible: page.c.ports && page.c.ports.length > 0
        title: "Ports"
        subtitle: page.running ? "" : "Start the container to open these."
        Flow {
          Layout.fillWidth: true
          spacing: Style.spacing.md
          Repeater {
            model: page.c.ports || []
            delegate: Button {
              required property var modelData
              focusable: true
              bordered: true
              iconText: Icons.glyph("app.browser")
              text: "Open " + Model.portUrl(modelData).replace(/^https?:\/\//, "")
              tooltipText: Model.portLabel(modelData)
              enabled: page.running
              onClicked: Quickshell.execDetached(["xdg-open", Model.portUrl(modelData)])
            }
          }
        }
      }

      Section {
        id: logsCard
        title: "Logs"
        subtitle: "The last 300 lines" + (root.logsFollow ? ", read again every few seconds." : ".")
        trailing: [
          Button {
            focusable: true
            iconText: Icons.glyph("ui.arrow.down")
            text: "Follow"
            selected: root.logsFollow
            onClicked: root.logsFollow = !root.logsFollow
          },
          Button {
            focusable: true
            text: "Open in terminal"
            iconText: Icons.glyph("ui.open-external")
            bordered: true
            onClicked: Quickshell.execDetached(["karchy-containers", "follow", page.c.name])
          }
        ]

        BorderSurface {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(260)
          radius: Style.radius.control
          color: Util.alpha(Commons.Color.foreground, 0.03)
          borderSpec: Border.flat(Style.normalBorderColor, Style.border.control)

          Flickable {
            id: logsView
            anchors.fill: parent
            anchors.margins: Style.spacing.lg
            clip: true
            contentWidth: width
            contentHeight: logsBody.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ListScrollBar {}

            // Following, the view stays at the end as lines arrive.
            Connections {
              target: root
              function onLogsUpdated() {
                if (root.logsFollow || logsView.atYEnd)
                  Qt.callLater(function() { logsView.contentY = Math.max(0, logsView.contentHeight - logsView.height) })
              }
            }

            TextEdit {
              id: logsBody
              width: logsView.width
              readOnly: true
              selectByMouse: true
              wrapMode: TextEdit.WrapAnywhere
              textFormat: TextEdit.PlainText
              text: root.logsText !== "" ? root.logsText : (logsProc.running ? "Reading logs…" : "No output yet.")
              color: root.logsText !== "" ? Commons.Color.foreground : Commons.Color.textSecondary
              selectionColor: Style.selectionFill
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
            }
          }
        }
      }

      // Apart at the bottom: what can't be undone, asked about first.
      Section {
        title: "Can't be undone"
        DangerRow {
          title: "Remove this container"
          description: "Deletes the container and what it wrote outside its volumes. Its image and named volumes are kept."
            + (page.running ? " Stop it first." : "")
          actionText: "Remove…"
          actionEnabled: !page.running && page.busyText === ""
          onTriggered: root.confirm("Remove the container " + page.c.name + "?", "Remove", page.c.id, ["remove", page.c.id], "remove it")
        }
      }

      Item { Layout.preferredHeight: Style.spacing.lg }
    }
  }

  Component {
    id: projectsPage
    ColumnLayout {
      spacing: Style.spacing.xxl

      PageHeader {
        iconName: "containers.compose"
        title: "Compose projects"
        explanation: "Projects started with docker compose. One taken down stays listed, so it can be brought up again from here."
      }

      Messages {}

      EmptyState {
        visible: root.projects.length === 0
        centered: true
        Layout.fillWidth: true
        iconName: "containers.compose"
        title: "No Compose projects yet"
        body: "Run docker compose up in a project's folder and it shows here."
      }

      Repeater {
        model: root.projects
        delegate: Card {
          id: projectCard
          required property var modelData
          readonly property string busyAction: root.busy[modelData.name] || ""
          title: modelData.name
          subtitle: [
            busyAction !== "" ? busyAction
              : (modelData.total === 0 ? "Down" : modelData.running + " of " + modelData.total + " running"),
            modelData.workdir
          ].filter(function(s) { return s }).join(" · ")
          trailing: [
            // Always offered: up also recreates services whose containers
            // were removed, which the list can't see.
            Button {
              focusable: true
              text: "Up"
              bordered: true
              busy: projectCard.busyAction !== ""
              onClicked: root.act(projectCard.modelData.name, ["compose", "up", projectCard.modelData.name], "bring it up")
            },
            Button {
              visible: projectCard.modelData.running > 0
              focusable: true
              text: "Restart"
              bordered: true
              enabled: projectCard.busyAction === ""
              onClicked: root.act(projectCard.modelData.name, ["compose", "restart", projectCard.modelData.name], "restart it")
            },
            Button {
              visible: projectCard.modelData.total > 0
              focusable: true
              variant: "destructive"
              text: "Take down…"
              enabled: projectCard.busyAction === ""
              onClicked: root.confirm(
                "Take " + projectCard.modelData.name + " down? Its containers are stopped and removed; volumes are kept.",
                "Take down", projectCard.modelData.name, ["compose", "down", projectCard.modelData.name], "take it down")
            },
            Button {
              visible: projectCard.modelData.total === 0
              focusable: true
              text: "Forget"
              tooltipText: "Remove it from this list; its folder is left alone"
              bordered: true
              enabled: projectCard.busyAction === ""
              onClicked: root.act(projectCard.modelData.name, ["forget", projectCard.modelData.name], "forget it")
            }
          ]
        }
      }
    }
  }

  Component {
    id: imagesPage
    ColumnLayout {
      spacing: Style.spacing.xxl

      PageHeader {
        iconName: "containers.image"
        title: "Images"
      }

      Messages {}

      EmptyState {
        visible: root.images.length === 0
        centered: true
        Layout.fillWidth: true
        iconName: "containers.image"
        title: "No images yet"
        body: "Images are downloaded when a container first needs them."
      }

      Repeater {
        model: root.images
        delegate: Card {
          id: imageCard
          required property var modelData
          readonly property string busyAction: root.busy[modelData.id] || ""
          readonly property bool used: modelData.containers > 0
          title: Model.shortImage(modelData.name) + (modelData.tags > 1 ? "  +" + (modelData.tags - 1) + " tags" : "")
          subtitle: busyAction !== "" ? busyAction : [
            modelData.size, Model.ago(modelData.created, root.now),
            used ? "used by " + modelData.containers + " container" + (modelData.containers === 1 ? "" : "s") + ", so it can't be removed" : "unused"
          ].filter(function(s) { return s }).join(" · ")
          trailing: Button {
            focusable: true
            variant: "destructive"
            text: "Remove…"
            enabled: imageCard.busyAction === "" && !imageCard.used
            onClicked: root.confirm("Remove the image " + Model.shortImage(imageCard.modelData.name) + "?", "Remove",
              imageCard.modelData.id, ["remove-image", imageCard.modelData.id], "remove the image")
          }
        }
      }

      Section {
        title: "Can't be undone"
        DangerRow {
          title: "Prune"
          description: "Removes every stopped container, unused network and dangling image. Volumes and tagged images are kept."
          actionText: "Prune…"
          actionEnabled: !root.busy["prune"]
          onTriggered: root.confirm(
            "Remove all stopped containers, unused networks and dangling images? Volumes and tagged images are kept.",
            "Prune", "prune", ["prune"], "prune")
        }
      }
    }
  }

  // ----------------------------------------------------------- components

  // The last action's error, kept until dismissed or the next action.
  component Messages: InlineMessage {
    kind: "error"
    text: root.errorText
    details: root.errorDetails
    dismissible: true
    onDismissed: { root.errorText = ""; root.errorDetails = "" }
  }


  // One destructive action with what it does, in a "Can't be undone" section.
  component DangerRow: RowLayout {
    id: danger
    property string title: ""
    property string description: ""
    property string actionText: ""
    property bool actionEnabled: true
    signal triggered()
    Layout.fillWidth: true
    spacing: Style.spacing.xxl
    ColumnLayout {
      Layout.fillWidth: true
      spacing: Style.spacing.xxs
      Text {
        Layout.fillWidth: true
        text: danger.title
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
      }
      Text {
        Layout.fillWidth: true
        text: danger.description
        wrapMode: Text.Wrap
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
      }
    }
    Button {
      focusable: true
      variant: "destructive"
      text: danger.actionText
      enabled: danger.actionEnabled
      onClicked: danger.triggered()
    }
  }

  // A read that can be asked for again while running; it runs once more
  // after, so the newest state always lands.
  component Query: Process {
    id: query
    property bool again: false
    signal result(string text)
    // The command failed: its exit code and what it said, which for
    // karchy-containers is one sentence for a person.
    signal failed(int code, string reason)

    function request() {
      if (running) again = true
      else if (command.length > 0) running = true
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: query.result(text)
    }
    stderr: StdioCollector { id: queryError; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0) query.failed(code, queryError.text.trim())
      if (again) {
        again = false
        running = true
      }
    }
  }
}
