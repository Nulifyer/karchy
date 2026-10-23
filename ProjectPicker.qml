import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Ui
import "Search.js" as Search

Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  readonly property string pluginId: "nulifyer.project-picker"
  readonly property string home: Quickshell.env("HOME")
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("projects.py").toString().replace(/^file:\/\//, ""))
  property string projectsRoot: Quickshell.env("Z_PROJECTS_ROOT") || home + "/Projects"
  property var editor: ["code"]
  property var projects: []
  property var scanRows: []
  property var previousProjects: []
  property var results: []
  property int selectedIndex: 0
  property string errorText: ""
  property string launchError: ""
  property bool rescanPending: false
  property var targetScreen: null
  readonly property int rowHeight: Style.space(48)
  readonly property int padding: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)
  readonly property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Color.menu.selectedBorder, 0)

  function open(payloadJson) {
    var initialQuery = ""
    try {
      var payload = JSON.parse(payloadJson || "{}")
      if (typeof payload.query === "string") initialQuery = payload.query
    } catch (error) { /* An invalid optional payload still opens the picker. */ }
    var focused = Hyprland.focusedMonitor
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++) {
      if (focused && screens[i].name === focused.name) { root.targetScreen = screens[i]; break }
    }
    root.opened = true
    root.launchError = ""
    pointerGate.reset()
    search.text = initialQuery
    root.selectedIndex = 0
    root.rebuild(false)
    root.refresh()
    Qt.callLater(function() { search.forceActiveFocus() })
  }

  function close() { root.opened = false }

  function dismiss() {
    root.close()
    if (root.shell) root.shell.hide(root.pluginId)
  }

  function loadSettings(raw) {
    try {
      var config = JSON.parse(raw)
      var entries = config.plugins || []
      var settings = ({})
      for (var i = 0; i < entries.length; i++) {
        if (entries[i].id === root.pluginId) { settings = entries[i]; break }
      }
      var nextRoot = typeof settings.projectsRoot === "string" && settings.projectsRoot
        ? settings.projectsRoot : Quickshell.env("Z_PROJECTS_ROOT") || root.home + "/Projects"
      var nextEditor = settings.editor === undefined ? ["code"] : settings.editor
      if (!Array.isArray(nextEditor) || !nextEditor.length || nextEditor.some(function(arg) {
        return typeof arg !== "string" || !arg.length
      })) throw new Error("editor must be an array, for example [\"code\"]")
      var changed = nextRoot !== root.projectsRoot
      root.projectsRoot = nextRoot
      root.editor = nextEditor
      if (changed || !root.projects.length) root.refresh()
    } catch (error) {
      root.errorText = "Project picker settings: " + error.message
    }
  }

  function refresh() {
    if (scan.running) { root.rescanPending = true; return }
    root.errorText = ""
    root.previousProjects = root.projects
    root.scanRows = []
    scan.command = ["python3", root.helper, "scan", "--home", root.home, "--root", root.projectsRoot]
    scan.running = true
  }

  function rebuild(preserveSelection) {
    pointerGate.reset()
    var selectedPath = preserveSelection && root.results[root.selectedIndex]
      ? root.results[root.selectedIndex].path : ""
    root.results = Search.rank(root.projects, search.text)
    root.selectedIndex = Math.max(0, Math.min(root.selectedIndex, root.results.length - 1))
    if (selectedPath) {
      for (var i = 0; i < root.results.length; i++) {
        if (root.results[i].path === selectedPath) { root.selectedIndex = i; break }
      }
    }
    Qt.callLater(function() {
      if (root.results.length) list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    })
  }

  function select(delta) {
    if (!root.results.length) return
    pointerGate.reset()
    root.selectedIndex = (root.selectedIndex + delta + root.results.length) % root.results.length
    list.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  function activate(action) {
    if (launcher.running || !root.results.length) return
    root.launchError = ""
    launcher.command = ["python3", root.helper, "launch", "--action", action,
      "--path", root.results[root.selectedIndex].path, "--editor-json", JSON.stringify(root.editor)]
    launcher.running = true
  }

  // Stable IPC inspection is also useful for diagnosing a failed discovery.
  function status(arg) {
    return JSON.stringify({ opened: root.opened, scanning: scan.running, count: root.projects.length,
      matches: root.results.length, query: search.text,
      selectedPath: root.results[root.selectedIndex] ? root.results[root.selectedIndex].path : "",
      error: root.launchError || root.errorText, screen: panel.screen ? panel.screen.name : "" })
  }

  FileView {
    path: (Quickshell.env("XDG_CONFIG_HOME") || root.home + "/.config") + "/omarchy/shell.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.loadSettings(text())
  }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  Process {
    id: scan
    stdout: SplitParser {
      onRead: function(line) {
        if (!line) return
        try {
          var row = JSON.parse(line)
          if (typeof row.name !== "string" || typeof row.path !== "string") return
          root.scanRows.push(row)
          if (!batch.running) batch.start()
        } catch (error) { root.errorText = "Could not read project discovery results." }
      }
    }
    stderr: StdioCollector {}
    onExited: function(code, exitStatus) {
      batch.stop()
      if (code === 0 && exitStatus === 0) root.projects = root.scanRows.slice()
      else {
        root.projects = root.previousProjects
        root.errorText = stderr.text.trim() || "Project discovery failed. Press Ctrl+R to retry."
      }
      root.rebuild(true)
      if (root.rescanPending) {
        root.rescanPending = false
        Qt.callLater(function() { root.refresh() })
      }
    }
  }

  Timer {
    id: batch
    interval: 32
    onTriggered: {
      root.projects = root.scanRows.slice()
      if (root.opened) root.rebuild(true)
    }
  }

  Timer {
    id: filterDelay
    interval: 12
    onTriggered: root.rebuild(false)
  }

  Process {
    id: launcher
    stderr: StdioCollector {}
    onExited: function(code, exitStatus) {
      if (code === 0 && exitStatus === 0) root.dismiss()
      else root.launchError = stderr.text.trim() || "Could not open the project."
    }
  }

  PanelWindow {
    id: panel
    screen: root.targetScreen || Quickshell.screens[0]
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "nulifyer-project-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle { anchors.fill: parent; color: Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: root.padding

      MouseArea { anchors.fill: parent; onClicked: search.forceActiveFocus() }

      Column {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.sm

        Item {
          id: header
          width: parent.width
          height: Math.max(Style.space(26), title.implicitHeight, resultCount.implicitHeight)
          Text {
            id: title
            text: "Projects"
            textFormat: Text.PlainText
            color: Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: resultCount
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: scan.running ? "Searching…" : root.results.length + " / " + root.projects.length
            textFormat: Text.PlainText
            color: Color.menu.text
            opacity: 0.58
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        TextField {
          id: search
          width: parent.width
          height: Math.max(Style.space(40), implicitHeight)
          foreground: Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          placeholderText: "Search projects or paths…"
          selectByMouse: true
          focus: true
          onTextChanged: { root.selectedIndex = 0; filterDelay.restart() }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            if (event.key === Qt.Key_Escape) root.dismiss()
            else if (ctrl && event.key === Qt.Key_E) { filterDelay.stop(); root.rebuild(false); root.activate("terminal") }
            else if (ctrl && event.key === Qt.Key_R) root.refresh()
            else if (event.key === Qt.Key_Down || (ctrl && event.key === Qt.Key_N)) { filterDelay.stop(); root.rebuild(true); root.select(1) }
            else if (event.key === Qt.Key_Up || (ctrl && event.key === Qt.Key_P)) { filterDelay.stop(); root.rebuild(true); root.select(-1) }
            else if (event.key === Qt.Key_PageDown) root.select(7)
            else if (event.key === Qt.Key_PageUp) root.select(-7)
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { filterDelay.stop(); root.rebuild(true); root.activate("editor") }
            else return
            event.accepted = true
          }
        }

        ListView {
          id: list
          width: parent.width
          height: Math.max(0, card.height - card.contentTopInset - card.contentBottomInset
            - header.height - search.height - footer.height - errorLabel.height - parent.spacing * 4)
          clip: true
          model: root.results
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.selectedIndex
          delegate: BorderSurface {
            id: row
            required property var modelData
            required property int index
            width: list.width
            height: Math.max(root.rowHeight, rowContent.implicitHeight + Style.spacing.controlPaddingY * 2
              + Border.top(root.selectedBorderSpec) + Border.bottom(root.selectedBorderSpec))
            radius: Style.cornerRadius
            color: index === root.selectedIndex ? Color.menu.selectedBackground : "transparent"
            borderSpec: index === root.selectedIndex ? root.selectedBorderSpec : Border.none()

            Column {
              id: rowContent
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.spacing.md + Border.left(root.selectedBorderSpec)
              anchors.rightMargin: Style.spacing.md + Border.right(root.selectedBorderSpec)
              anchors.verticalCenterOffset: (Border.top(root.selectedBorderSpec) - Border.bottom(root.selectedBorderSpec)) / 2
              spacing: Style.spacing.xxs
              Text {
                width: parent.width
                text: Search.plainLabel(row.modelData.name)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.index === root.selectedIndex ? Color.menu.selectedText : Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                width: parent.width
                text: Search.plainLabel(row.modelData.displayPath)
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: Color.menu.text
                opacity: 0.52
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
              }
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onPositionChanged: function(mouse) {
                if (pointerGate.moved(row, mouse)) root.selectedIndex = row.index
              }
              onClicked: { root.selectedIndex = row.index; root.activate("editor") }
            }
          }

          Text {
            anchors.centerIn: parent
            visible: root.results.length === 0
            text: scan.running ? "Looking for projects…" : search.text.length ? "No matching projects" : "Add a folder to ~/Projects to get started"
            textFormat: Text.PlainText
            color: Color.menu.text
            opacity: 0.58
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }

        Text {
          id: errorLabel
          width: parent.width
          height: text.length ? implicitHeight : 0
          text: root.launchError || root.errorText
          textFormat: Text.PlainText
          color: Color.urgent
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        Text {
          id: footer
          width: parent.width
          text: "Enter  editor     Ctrl+E  terminal     Ctrl+R  refresh     Esc  close"
          textFormat: Text.PlainText
          color: Color.menu.text
          opacity: 0.58
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
