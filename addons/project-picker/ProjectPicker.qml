import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
// Colors always come through the namespace: a bare `Color` can resolve to
// another module's type of that name, which has none of the shell's roles.
import qs.Commons as Commons
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
  readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config")
    + "/karchy/shell.json"
  property string projectsRoot: Quickshell.env("Z_PROJECTS_ROOT") || home + "/Projects"
  readonly property string projectsRootLabel: displayPath(projectsRoot)
  property var editor: ["code"]
  readonly property string editorLabel: editor[0] === "code" ? "VS Code" : editor[0]
  property var projects: []
  property var scanRows: []
  property var previousProjects: []
  property var results: []
  property int matchCount: 0
  property int selectedIndex: 0
  property string errorText: ""
  property string launchError: ""
  property bool rescanPending: false
  property bool creating: false
  property var targetScreen: null
  readonly property int rowHeight: Style.space(48)
  readonly property int padding: Style.spacing.panelPadding
  readonly property int cardWidth: Math.min(Style.space(720), panel.width - Style.gapsOut * 2)
  readonly property int cardHeight: Math.min(Style.space(500), panel.height - Style.gapsOut * 2)
  readonly property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", Commons.Color.menu.selectedBorder, 0)
  // Secondary text and errors use the shell's derived roles where it has them
  // (karchy), else the menu text at reduced opacity and the theme's red.
  readonly property color quietText: typeof Commons.Color.secondaryText === "function"
    ? Commons.Color.secondaryText(Commons.Color.menu.text, Commons.Color.menu.background)
    : Util.alpha(Commons.Color.menu.text, 0.55)
  readonly property color errorColor: Commons.Color.status ? Commons.Color.status.error : Commons.Color.urgent
  readonly property var newProjectRow: ({ newProject: true, name: "", path: "", displayPath: "" })

  function displayPath(path) {
    var value = String(path || "")
    if (value === root.home) return "~"
    if (value.indexOf(root.home + "/") === 0) return "~" + value.slice(root.home.length)
    return value
  }

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
    root.creating = false
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
    // "New project" is always the last row: one Up from the top reaches it,
    // and it is the only row when nothing matches.
    var ranked = Search.rank(root.projects, search.text)
    root.matchCount = ranked.length
    root.results = ranked.concat([root.newProjectRow])
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
    var row = root.results[root.selectedIndex]
    if (row.newProject) { root.beginCreate(); return }
    root.launchError = ""
    launcher.command = ["python3", root.helper, "launch", "--action", action,
      "--path", row.path, "--editor-json", JSON.stringify(root.editor)]
    launcher.running = true
  }

  // New project: ask for a name (the search text, when there is one), then
  // create the folder in the projects root and open it in the editor.
  function beginCreate() {
    if (launcher.running) return
    root.launchError = ""
    root.creating = true
    projectName.text = search.text.trim()
    projectName.selectAll()
    Qt.callLater(function() { projectName.forceActiveFocus() })
  }

  function cancelCreate() {
    root.creating = false
    root.launchError = ""
    Qt.callLater(function() { search.forceActiveFocus() })
  }

  function create() {
    if (launcher.running || !projectName.text.trim().length) return
    root.launchError = ""
    // One argument each, so a name that starts with "-" stays a name.
    launcher.command = ["python3", root.helper, "create", "--root=" + root.projectsRoot,
      "--name=" + projectName.text.trim(), "--editor-json=" + JSON.stringify(root.editor)]
    launcher.running = true
  }

  // Stable IPC inspection is also useful for diagnosing a failed discovery.
  function status(arg) {
    var row = root.results[root.selectedIndex]
    return JSON.stringify({ opened: root.opened, scanning: scan.running, count: root.projects.length,
      matches: root.matchCount, query: search.text, creating: root.creating,
      selectedPath: row && !row.newProject ? row.path : "", newProjectSelected: !!(row && row.newProject),
      error: root.launchError || root.errorText, screen: panel.screen ? panel.screen.name : "" })
  }

  FileView {
    path: root.settingsPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadSettings(text())
    // No settings file: the shell runs on its defaults, and so does the picker.
    onLoadFailed: root.loadSettings("{}")
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

    Rectangle { anchors.fill: parent; color: Commons.Color.menu.scrim }
    MouseArea { anchors.fill: parent; onClicked: root.dismiss() }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: root.cardWidth
      height: root.cardHeight
      radius: Style.cornerRadius
      color: Commons.Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Commons.Color.menu.border, Math.max(1, Style.space(2)))
      padding: root.padding

      MouseArea {
        anchors.fill: parent
        onClicked: (root.creating ? projectName : search).forceActiveFocus()
      }

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
            text: root.creating ? "New project" : "Projects"
            textFormat: Text.PlainText
            color: Commons.Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.title
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            id: resultCount
            visible: !root.creating
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: scan.running ? "Searching…" : root.matchCount + " / " + root.projects.length
            textFormat: Text.PlainText
            color: root.quietText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        TextField {
          id: search
          visible: !root.creating
          width: parent.width
          height: visible ? Math.max(Style.space(40), implicitHeight) : 0
          foreground: Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          placeholderText: "Search projects or paths…"
          selectByMouse: true
          focus: true
          onTextChanged: { root.selectedIndex = 0; filterDelay.restart() }
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            var ctrl = (event.modifiers & Qt.ControlModifier) !== 0
            var shift = (event.modifiers & Qt.ShiftModifier) !== 0
            if (event.key === Qt.Key_Escape) root.dismiss()
            else if (ctrl && shift && event.key === Qt.Key_N) { filterDelay.stop(); root.beginCreate() }
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

        TextField {
          id: projectName
          visible: root.creating
          width: parent.width
          height: visible ? Math.max(Style.space(40), implicitHeight) : 0
          foreground: Commons.Color.menu.text
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.body
          placeholderText: "Project name"
          selectByMouse: true
          onTextChanged: root.launchError = ""
          Keys.priority: Keys.BeforeItem
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) root.cancelCreate()
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.create()
            else return
            event.accepted = true
          }
        }

        Item {
          id: createHint
          visible: root.creating
          width: parent.width
          height: visible ? list.height : 0

          Text {
            width: parent.width
            text: projectName.text.trim().length
              ? "Creates " + root.projectsRootLabel + "/" + projectName.text.trim() + " and opens it in " + root.editorLabel + "."
              : "Type a name for the new folder in " + root.projectsRootLabel + "."
            textFormat: Text.PlainText
            color: root.quietText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.Wrap
          }
        }

        ListView {
          id: list
          visible: !root.creating
          width: parent.width
          height: Math.max(0, card.height - card.contentTopInset - card.contentBottomInset
            - header.height - Math.max(search.height, projectName.height) - footer.height
            - (errorLabel.visible ? errorLabel.implicitHeight + parent.spacing : 0) - parent.spacing * 3)
          clip: true
          model: root.results
          boundsBehavior: Flickable.StopAtBounds
          currentIndex: root.selectedIndex
          delegate: BorderSurface {
            id: row
            required property var modelData
            required property int index
            readonly property bool isNew: modelData.newProject === true
            readonly property string query: search.text.trim()
            width: list.width
            height: Math.max(root.rowHeight, rowContent.implicitHeight + Style.spacing.controlPaddingY * 2
              + Border.top(root.selectedBorderSpec) + Border.bottom(root.selectedBorderSpec))
            radius: Style.cornerRadius
            color: index === root.selectedIndex ? Commons.Color.menu.selectedBackground : "transparent"
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
                text: row.isNew
                  ? (row.query.length ? "+  New project “" + row.query + "”" : "+  New project…")
                  : Search.plainLabel(row.modelData.name)
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: row.index === root.selectedIndex ? Commons.Color.menu.selectedText : Commons.Color.menu.text
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.body
                font.bold: true
              }
              Text {
                width: parent.width
                text: row.isNew
                  ? "Create a folder in " + root.projectsRootLabel + " and open it in " + root.editorLabel
                  : Search.plainLabel(row.modelData.displayPath)
                textFormat: Text.PlainText
                elide: Text.ElideMiddle
                color: root.quietText
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
            visible: root.matchCount === 0 && !scan.running
            text: search.text.length ? "No matching projects" : "No projects in " + root.projectsRootLabel + " yet"
            textFormat: Text.PlainText
            color: root.quietText
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
          }
        }

        Text {
          id: errorLabel
          // Hidden rather than zero height: an explicit height makes the
          // multi-line elide below depend on itself.
          visible: text.length > 0
          width: parent.width
          text: root.launchError || root.errorText
          textFormat: Text.PlainText
          color: root.errorColor
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
          maximumLineCount: 3
          elide: Text.ElideRight
        }

        Text {
          id: footer
          width: parent.width
          text: root.creating
            ? "Enter  create and open     Esc  back"
            : "Enter  editor     Ctrl+E  terminal     Ctrl+Shift+N  new project     Ctrl+R  refresh     Esc  close"
          textFormat: Text.PlainText
          color: root.quietText
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.Wrap
        }
      }
    }
  }
}
