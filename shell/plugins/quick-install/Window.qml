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
import "Search.js" as Search

// The Quick install window (D-70): common apps and karchy's optional
// features from default/karchy/quick-install.json, by category or searched
// like fzf, each installed, opened or removed in one step. A normal
// application window like Settings and Containers.
//
// Open it with `karchy quick-install [search]`, `karchy quick-install
// window @<category>` or Packages › Quick install in the menu; the summon
// payload takes optional `query` and `category`. Install and remove run
// `karchy-quick-install` in a floating terminal, so pacman's questions,
// paru's build and the password prompt are visible; the command asks this
// window to read the status again when it is done (`karchy-shell -q
// karchy.quick-install refresh`), and so does the terminal closing.
//
// Layout: a sidebar of categories with counts, All and Installed first;
// then the search field, the list and the keys. A category lists its apps
// under headings that say what they are for (D-158: "Coding agents", "Chat
// apps"), by name under each; All and Installed use the categories' names;
// search results are ranked and have none. The heading of the rows in view
// stays at the top of the list. The focused row opens in place to say what
// it installs and from where, its size, what else it sets up, and Remove for
// an installed app, confirmed with Cancel focused.
//
// Keyboard: typing goes to the search, which spans every category; Up/Down
// (and j/k outside the search field) move through the list, from row to row
// across the headings; Enter installs
// or opens the focused app, or installs the picked apps when some are
// picked (D-151); Space picks it, except in the middle of typing
// a search, where it is a space and Ctrl+Space picks (`spacePicks`); Tab
// walks the search, the category list (one stop, j/k or the arrows to
// choose), the focused row's buttons and the bar under the list (Install N
// apps for what was picked); Escape clears the search, then closes.
Item {
  id: root

  property var shell: null
  property var manifest: null
  property bool opened: false
  property string karchyPath: Quickshell.env("KARCHY_PATH")

  property var catalog: ({ categories: [], apps: [] })
  property bool catalogFailed: false
  // id -> desktop file ("" when it has no window), for what is installed.
  property var installed: ({})
  property bool statusLoaded: false
  // `karchy-quick-install status` gave no answer: nothing is shown as
  // installed, and the header says so.
  property bool statusFailed: false
  property string category: "all"
  property string query: ""
  property string currentId: ""
  // id -> `karchy-quick-install info` answer, or "loading".
  property var infos: ({})
  // The app whose install or removal runs in the terminal. One at a time:
  // pacman holds one lock, so the other Install and Remove buttons wait.
  // Picked apps (D-109): id -> true. Install or remove them in one go; a
  // failed one stays picked, so trying again is one click.
  property var selected: ({})
  // What `karchy-quick-install apply` reported: id -> { state, reason }, with
  // state queued, working, done, failed, cancelled (the password prompt was
  // closed) or terminal (AUR apps and karchy's features, which continue in a
  // terminal).
  property var progress: ({})
  // The ids of the last install or removal, for the bar's sentence about it.
  property var lastRun: []
  readonly property string lastRunText: Model.runText(root.lastRun.map(function(id) {
    var app = Model.find(root.apps, id)
    return { name: app ? app.name : id, state: root.progress[id] ? root.progress[id].state : "" }
  }), root.applyVerb)
  property bool applying: false
  property string applyVerb: ""
  // The running install is the picked apps' (the bar's button spins for it),
  // not one row's.
  property bool applyingPicked: false
  property string logPath: ""
  property bool multilibOn: false
  property var pendingRemove: null

  readonly property var apps: catalog.apps || []
  readonly property bool searching: query.trim() !== ""
  // Space picks the highlighted app (D-109) wherever it can't be part of a
  // search: outside the search field, in an empty one, and once the arrows
  // have moved the highlight (`browsing`, until the text is edited again).
  // So "visual studio" types as it reads, and Down, Space, Down, Space picks
  // two results. The footer names the key that picks right now.
  property bool browsing: false
  property bool searchFocused: true
  readonly property bool spacePicks: !searchFocused || !searching || browsing
  readonly property var categoryRows: Model.categories(catalog, installed)
  // Each row is { app, positions, section }. A category lists its apps under
  // headings that say what they are for (D-158); All, Installed and Picked
  // under the categories' names; search results are ranked, so they have none.
  readonly property var results: searching
    ? Search.search(apps, query).map(function(r) { return { app: r.app, positions: r.positions, section: "" } })
    : Model.rows(catalog, apps, category, installed, category === "picked" ? root.selected : null)
  readonly property var sectionCounts: Model.sectionCounts(results)
  readonly property int currentIndex: {
    for (var i = 0; i < results.length; i++) if (results[i].app.id === currentId) return i
    return -1
  }
  readonly property var current: currentIndex >= 0 ? results[currentIndex].app : null
  readonly property int installedCount: Object.keys(installed).length

  function open(payloadJson) {
    var payload = Model.parse(payloadJson || "{}", {})
    if (payload.category) {
      // The first summon can come before the catalog has loaded, when no
      // category is known yet; the catalog's onLoaded checks it then.
      var catalogLoaded = (root.catalog.categories || []).length > 0
      root.category = !catalogLoaded || root.knownCategory(String(payload.category)) ? String(payload.category) : "all"
      searchField.text = ""
    }
    if (payload.query !== undefined && String(payload.query) !== "") {
      root.category = "all"
      searchField.text = String(payload.query)
    }
    root.currentId = ""
    root.pickFirst()
    root.opened = true
    root.refresh()
    if (window.visible) Qt.callLater(function() { searchField.forceActiveFocus() })
  }

  function close() {
    // shell.hide() calls back into close(); stop the second time round.
    if (!root.opened) return
    root.opened = false
    root.pendingRemove = null
    if (root.shell && root.manifest) root.shell.hide(root.manifest.id)
  }

  function refresh() {
    statusProc.request()
    pacmanConf.reload()
  }

  function knownCategory(id) {
    if (id === "all" || id === "installed" || id === "picked") return true
    var cats = root.catalog.categories || []
    for (var i = 0; i < cats.length; i++) if (cats[i].id === id) return true
    return false
  }

  // `karchy-quick-install` calls this when its install or removal is done,
  // before the terminal waits for a key, so the row and the other buttons
  // don't wait for the terminal to close.
  // The terminal that took the AUR apps and features says "terminal" when it
  // is through with them all: a status read after that is the last word.
  function finished(what) {
    if (String(what || "") === "terminal") settleProc.request()
    else root.refresh()
  }

  function takeStatus(text, terminalEnded) {
    var data = Model.parse(text, null)
    root.statusFailed = !data
    var before = Object.keys(root.installed).sort().join(" ")
    root.installed = data ? (data.installed || {}) : {}
    // Sizes say what installing would add, or what is installed: read again
    // once something was installed or removed.
    if (before !== Object.keys(root.installed).sort().join(" ")) {
      root.infos = ({})
      infoTimer.restart()
    }
    root.statusLoaded = true
    if (data) root.settleTerminal(terminalEnded)
  }

  // An app handed to the terminal is done once the status shows it; what the
  // status doesn't show once the terminal is through didn't happen.
  function settleTerminal(terminalEnded) {
    var next = Object.assign({}, root.progress), changed = false
    for (var id in next) {
      var p = next[id]
      if (p.state !== "terminal") continue
      var there = root.installed[id] !== undefined
      if (there === (p.verb === "install")) next[id] = { state: "done", reason: "", verb: p.verb }
      else if (terminalEnded) next[id] = { state: "cancelled", reason: "the terminal showed why", verb: p.verb }
      else continue
      changed = true
    }
    if (changed) root.progress = next
  }

  function isBusy(id) {
    var p = root.progress[id]
    return !!p && (p.state === "queued" || p.state === "working")
  }

  function isSelected(id) {
    return root.selected[id] === true
  }

  function toggleSelected(app) {
    if (!app || root.applying || app.required) return
    var next = Object.assign({}, root.selected)
    if (next[app.id]) delete next[app.id]
    else next[app.id] = true
    root.selected = next
  }

  function clearSelected() {
    root.selected = ({})
  }

  readonly property var selectedApps: root.apps.filter(function(a) { return root.selected[a.id] === true })
  readonly property var selectedToInstall: root.selectedApps.filter(function(a) { return !root.isInstalled(a) })
  readonly property var selectedToRemove: root.selectedApps.filter(function(a) { return root.isInstalled(a) && !a.required })
  readonly property int selectedInTerminal: root.selectedToInstall.filter(function(a) { return a.source === "aur" || !!a.feature }).length

  // Installs or removes the apps in one run of `karchy-quick-install apply`,
  // which reports each one's progress here, line by line.
  function applyIds(verb, ids) {
    if (root.applying || ids.length === 0) return
    var next = Object.assign({}, root.progress)
    ids.forEach(function(id) { next[id] = { state: "queued", reason: "", verb: verb } })
    root.progress = next
    root.lastRun = ids.slice()
    root.applying = true
    root.applyVerb = verb
    applyComponent.createObject(root, {
      command: ["karchy-quick-install", "apply", verb].concat(ids)
    }).running = true
  }

  function applyLine(line) {
    var m = String(line).match(/^(\S+)(?: (\S+))?(?: (.*))?$/)
    if (!m) return
    if (m[1] === "log") { root.logPath = m[2] || ""; return }
    if (m[1] === "finished") return
    if (["queued", "working", "done", "failed", "cancelled", "terminal"].indexOf(m[1]) < 0 || !m[2]) return
    var next = Object.assign({}, root.progress)
    next[m[2]] = { state: m[1], reason: m[3] || "", verb: root.applyVerb }
    root.progress = next
    // Done (or handed to the terminal) leaves the selection; a failure stays.
    if ((m[1] === "done" || m[1] === "terminal") && root.selected[m[2]]) {
      var sel = Object.assign({}, root.selected)
      delete sel[m[2]]
      root.selected = sel
    }
  }

  function installSelected() {
    if (root.applying || root.selectedToInstall.length === 0) return
    root.applyIds("install", root.selectedToInstall.map(function(a) { return a.id }))
    root.applyingPicked = true
  }

  function showLog() {
    if (root.logPath !== "") Quickshell.execDetached(["xdg-terminal-exec", "--app-id=org.karchy.terminal", "less", "+G", root.logPath])
  }

  // The first row becomes the focused one when the list changes under it.
  function pickFirst() {
    if (root.currentIndex >= 0) return
    root.currentId = root.results.length > 0 ? root.results[0].app.id : ""
  }

  function select(id) {
    root.currentId = id
  }

  function step(dy) {
    var list = root.results
    if (list.length === 0) return
    var i = root.currentIndex
    i = i < 0 ? 0 : Math.max(0, Math.min(list.length - 1, i + dy))
    root.currentId = list[i].app.id
  }

  function setCategory(id) {
    root.category = id
    root.browsing = false
    searchField.text = ""
    root.currentId = ""
    root.pickFirst()
  }

  function stepCategory(dy) {
    var rows = root.categoryRows
    var i = 0
    for (var j = 0; j < rows.length; j++) if (rows[j].id === root.category) i = j
    i = Math.max(0, Math.min(rows.length - 1, i + dy))
    root.setCategory(rows[i].id)
  }

  function isInstalled(app) {
    return !!app && root.installed[app.id] !== undefined
  }

  // Enter in the search or the list: with apps picked to install, install
  // those (D-151); otherwise open the focused app, or install it.
  function activate(app) {
    if (root.selectedToInstall.length > 0) {
      if (!root.applying && root.statusLoaded) root.installSelected()
      return
    }
    // Until status answers, an installed app would look installable.
    if (!app || root.isBusy(app.id) || !root.statusLoaded) return
    if (root.isInstalled(app)) {
      if (root.installed[app.id] !== "") root.openApp(app)
    } else if (!root.applying) {
      root.run(app, "install")
    }
  }

  function openApp(app) {
    Quickshell.execDetached(["karchy-quick-install", "open", app.id])
  }

  // The terminal runs under a shell that outlives it here, so closing this
  // window (which unloads the plugin and kills its processes) leaves a
  // running install alone.
  function run(app, action) {
    root.applyIds(action, [app.id])
  }

  function askRemove(app) {
    if (!app || root.applying) return
    root.pendingRemove = { ids: [app.id], names: [app.name] }
  }

  function askRemoveSelected() {
    var apps = root.selectedToRemove
    if (apps.length === 0 || root.applying) return
    root.pendingRemove = { ids: apps.map(function(a) { return a.id }), names: apps.map(function(a) { return a.name }) }
  }

  onResultsChanged: root.pickFirst()
  onCurrentIdChanged: infoTimer.restart()

  // ---------------------------------------------------------------- data

  FileView {
    id: catalogFile
    path: root.karchyPath + "/default/karchy/quick-install.json"
    watchChanges: true
    onFileChanged: reload()
    onLoadFailed: root.catalogFailed = true
    onLoaded: {
      root.catalog = Model.parse(text(), { categories: [], apps: [] })
      root.catalogFailed = (root.catalog.apps || []).length === 0
      if (!root.knownCategory(root.category)) root.category = "all"
      root.pickFirst()
    }
  }

  // Whether Arch's 32-bit repository is on already, for the setup text.
  FileView {
    id: pacmanConf
    path: "/etc/pacman.conf"
    onLoaded: root.multilibOn = /^\[multilib\]/m.test(text())
  }

  Query {
    id: statusProc
    command: ["karchy-quick-install", "status"]
    onResult: function(text) { root.takeStatus(text, false) }
  }

  // Asked for only when the terminal is through, so its answer is from after.
  Query {
    id: settleProc
    command: ["karchy-quick-install", "status"]
    onResult: function(text) { root.takeStatus(text, true) }
  }

  // One per install or removal. A terminal it opens for AUR apps and
  // features runs on its own (setsid), so this ends when the window's part
  // is done. Closing the window kills it; the root helper it started keeps
  // going (pkexec runs it apart), and the next status shows the result.
  Component {
    id: applyComponent
    Process {
      id: applyProc
      stdout: SplitParser { onRead: function(line) { root.applyLine(line) } }
      onExited: {
        root.applying = false
        root.applyingPicked = false
        // A run that ended without a word for an app leaves nothing hanging.
        var next = Object.assign({}, root.progress), changed = false
        for (var id in next) {
          if (next[id].state === "queued" || next[id].state === "working") {
            next[id] = { state: "failed", reason: "It stopped before this app; see the log", verb: next[id].verb }
            changed = true
          }
        }
        if (changed) root.progress = next
        root.refresh()
        applyProc.destroy()
      }
    }
  }

  // Sizes for the focused row, read once it has stayed focused a moment.
  Timer {
    id: infoTimer
    interval: 150
    onTriggered: {
      var app = root.current
      if (!app || root.infos[app.id] !== undefined) return
      // Sizes come from the repositories: not for a feature's script, nor
      // for an AUR app unless part of it comes from them.
      if (app.feature || (app.source === "aur" && (app.packages || []).length < 2)) return
      var next = Object.assign({}, root.infos)
      next[app.id] = "loading"
      root.infos = next
      infoComponent.createObject(root, { appId: app.id }).running = true
    }
  }

  Component {
    id: infoComponent
    Process {
      id: infoProc
      property string appId: ""
      command: ["karchy-quick-install", "info", appId]
      stdout: StdioCollector { id: infoOut; waitForEnd: true }
      onExited: {
        var next = Object.assign({}, root.infos)
        next[infoProc.appId] = Model.parse(infoOut.text, {})
        root.infos = next
        infoProc.destroy()
      }
    }
  }

  ShellIpc {
    target: "karchy.quick-install"
    function refresh(): void { root.refresh() }
  }

  // --------------------------------------------------------------- window

  // The shell brings the window to the front by this title when it is asked
  // for while open (shell.qml, summon), and Hyprland's rules match it.
  readonly property string windowTitle: "Quick install"

  FloatingWindow {
    id: window
    visible: root.opened
    title: root.windowTitle
    color: Commons.Color.background
    // Fit the screen it opens on: 1000×740 where there is room, less where not.
    readonly property var fitScreen: Hyprland.focusedMonitor && Hyprland.focusedMonitor.lastIpcObject
      ? Hyprland.focusedMonitor.lastIpcObject : null
    readonly property real screenWidth: fitScreen ? fitScreen.width / fitScreen.scale : 1280
    readonly property real screenHeight: fitScreen ? fitScreen.height / fitScreen.scale : 800
    implicitWidth: Math.round(Math.min(Style.space(1000), screenWidth * 0.85))
    // 740 shows every category without scrolling the sidebar.
    implicitHeight: Math.round(Math.min(Style.space(740), screenHeight * 0.85))

    onVisibleChanged: {
      if (!visible && root.opened) root.close()
      if (visible) Qt.callLater(function() { searchField.forceActiveFocus() })
    }

    Shortcut {
      sequence: "Ctrl+F"
      enabled: root.opened && !confirmDialog.opened
      onActivated: searchField.forceActiveFocus(Qt.ShortcutFocusReason)
    }
    // Picking from anywhere (`spacePicks`). The search field handles its own
    // Space, as a text field keeps plain keys from shortcuts; on a row's
    // button or the category list this comes before the control's Space.
    Shortcut {
      sequence: "Ctrl+Space"
      enabled: root.opened && !confirmDialog.opened
      onActivated: root.toggleSelected(root.current)
    }
    Shortcut {
      sequence: "Space"
      enabled: root.opened && !confirmDialog.opened && !root.searchFocused
      onActivated: root.toggleSelected(root.current)
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

      // A focused button that goes away (Remove after a removal, a row that
      // leaves the list) would leave the keyboard nowhere: back to the search.
      readonly property Item focusedItem: frame.Window.activeFocusItem
      onFocusedItemChanged: Qt.callLater(function() {
        if (!root.opened || confirmDialog.opened) return
        var item = frame.Window.activeFocusItem
        if (!item || item === frame.Window.contentItem || !item.visible) searchField.forceActiveFocus()
      })

      // Keys the focused control leaves unhandled end up here: Escape
      // clears the search, then closes; typing goes to the search.
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (searchField.text !== "") {
            searchField.text = ""
            searchField.forceActiveFocus()
          } else {
            root.close()
          }
          event.accepted = true
          return
        }
        if (event.text.length === 1 && event.text >= " " && event.text !== "\x7f"
            && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
          searchField.forceActiveFocus(Qt.ShortcutFocusReason)
          searchField.insert(searchField.cursorPosition, event.text)
          event.accepted = true
        }
      }

      // ---------- Sidebar ----------
      Rectangle {
        Layout.fillHeight: true
        Layout.preferredWidth: Style.space(250)
        color: Util.alpha(Commons.Color.foreground, 0.04)

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.spacing.panelPadding
          spacing: Style.spacing.lg

          // The window's name, quieter than the list beside it.
          ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumHeight: searchField.implicitHeight
            spacing: Style.spacing.xxs
            Text {
              text: "Quick install"
              color: Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
            }
            Text {
              Layout.fillWidth: true
              text: (root.apps.length + " apps · " + (root.statusFailed ? "installed apps unknown" : root.statusLoaded ? root.installedCount + " installed" : "reading…")).toUpperCase()
              color: Commons.Color.textSecondary
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: Style.font.labelSpacing
              elide: Text.ElideRight
            }
          }

          // One Tab stop; j/k or the arrows choose a category.
          Item {
            id: categoryList
            Layout.fillWidth: true
            Layout.fillHeight: true
            activeFocusOnTab: true
            Accessible.role: Accessible.List
            Accessible.name: "Categories"

            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Down || event.text === "j") { root.stepCategory(1); event.accepted = true }
              else if (event.key === Qt.Key_Up || event.text === "k") { root.stepCategory(-1); event.accepted = true }
              else if (event.key === Qt.Key_Home) { root.stepCategory(-1000); event.accepted = true }
              else if (event.key === Qt.Key_End) { root.stepCategory(1000); event.accepted = true }
              else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.focusActions(true); event.accepted = true }
              else if (event.key === Qt.Key_Tab) { root.focusActions(true); event.accepted = true }
              else if (event.key === Qt.Key_Backtab) { searchField.forceActiveFocus(Qt.BacktabFocusReason); event.accepted = true }
            }

            Flickable {
              id: categoryFlick
              anchors.fill: parent
              clip: true
              contentHeight: categoryColumn.implicitHeight
              boundsBehavior: Flickable.StopAtBounds
              // On a low screen the list is longer than the window: the bar
              // says there is more, with room beside the counts.
              readonly property bool scrolls: contentHeight > height
              ScrollBar.vertical: ListScrollBar {}

              // The chosen category in view: after a click or a key, and
              // when the window opens at one (`window @system`), which is
              // before the rows exist.
              function reveal() {
                var rows = root.categoryRows
                for (var i = 0; i < rows.length; i++) {
                  if (rows[i].id !== root.category) continue
                  var item = categoryRepeater.itemAt(i)
                  if (!item) return
                  if (item.y < contentY) contentY = item.y
                  else if (item.y + item.height > contentY + height)
                    contentY = Math.min(item.y + item.height, contentHeight) - height
                  return
                }
              }
              onHeightChanged: Qt.callLater(reveal)
              onContentHeightChanged: Qt.callLater(reveal)
              Connections {
                target: root
                function onCategoryChanged() { Qt.callLater(categoryFlick.reveal) }
              }

              Column {
                id: categoryColumn
                width: categoryFlick.width - (categoryFlick.scrolls ? Style.spacing.md : 0)
                spacing: Style.spacing.xxs

                Repeater {
                  id: categoryRepeater
                  model: root.categoryRows
                  delegate: Item {
                    id: categoryRow
                    required property var modelData
                    required property int index
                    readonly property bool chosen: !root.searching && root.category === modelData.id
                    width: categoryColumn.width
                    height: categoryButton.implicitHeight + (index === 1 ? Style.spacing.lg * 2 + Style.spacing.hairline : 0)

                    Button {
                      id: categoryButton
                      width: parent.width
                      leftAlign: true
                      iconText: Icons.glyph(categoryRow.modelData.iconName)
                      text: categoryRow.modelData.name
                      selected: categoryRow.chosen
                      hasCursor: categoryList.activeFocus && root.category === categoryRow.modelData.id
                      onClicked: {
                        root.setCategory(categoryRow.modelData.id)
                        categoryList.forceActiveFocus(Qt.MouseFocusReason)
                      }

                      Text {
                        id: count
                        anchors.right: parent.right
                        anchors.rightMargin: Style.spacing.controlPaddingX
                        anchors.verticalCenter: parent.verticalCenter
                        text: categoryRow.modelData.id === "installed" && !root.statusLoaded ? "…" : String(categoryRow.modelData.count)
                        color: categoryRow.chosen ? Commons.Color.focus : Commons.Color.textSecondary
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        font.features: { "tnum": 1 }
                      }
                    }

                    // All and Installed apart from the categories.
                    PanelSeparator {
                      visible: categoryRow.index === 1
                      anchors.left: parent.left
                      anchors.right: parent.right
                      anchors.bottom: parent.bottom
                      anchors.bottomMargin: Style.spacing.lg
                    }
                  }
                }
              }
            }
          }
        }
      }

      // ---------- Page ----------
      ColumnLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.margins: Style.spacing.panelPadding
        Layout.leftMargin: Style.spacing.panelPadding * 1.5
        spacing: Style.spacing.lg

        RowLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.lg

          TextField {
            id: searchField
            Layout.fillWidth: true
            placeholderText: "Search " + root.apps.length + " apps"
            onTextChanged: {
              root.query = text
              root.browsing = false
              root.currentId = ""
              root.pickFirst()
            }
            onActiveFocusChanged: root.searchFocused = activeFocus
            // Moving the text cursor is editing again.
            onCursorPositionChanged: root.browsing = false
            function browse(dy) {
              root.step(dy)
              root.browsing = true
            }
            Keys.onUpPressed: browse(-1)
            Keys.onDownPressed: browse(1)
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_PageDown) { browse(8); event.accepted = true }
              else if (event.key === Qt.Key_PageUp) { browse(-8); event.accepted = true }
              else if (event.key === Qt.Key_Tab) { categoryList.forceActiveFocus(Qt.TabFocusReason); event.accepted = true }
              else if (event.key === Qt.Key_Backtab) { if (!root.focusBar(false)) root.focusActions(false); event.accepted = true }
              else if (event.key === Qt.Key_Space && root.spacePicks
                       && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))) {
                root.toggleSelected(root.current)
                event.accepted = true
              }
            }
            onAccepted: root.activate(root.current)
          }
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          Layout.topMargin: Style.spacing.sm
          text: (root.searching ? "All results" : Model.categoryName(root.catalog, root.category)) + " · " + root.results.length
        }

        ListView {
          id: appList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          spacing: Style.spacing.md
          boundsBehavior: Flickable.StopAtBounds
          model: root.results
          cacheBuffer: Style.space(400)
          ScrollBar.vertical: ListScrollBar {}

          // Row buttons hand Up/Down and j/k to the list; the keyboard stays
          // on the focused row's first button. Space is the window's
          // shortcut above, which comes before a button's own Space.
          Keys.onPressed: function(event) {
            var dy = event.key === Qt.Key_Down || event.text === "j" ? 1
              : event.key === Qt.Key_Up || event.text === "k" ? -1
              : event.key === Qt.Key_PageDown ? 8 : event.key === Qt.Key_PageUp ? -8 : 0
            if (dy === 0) return
            root.step(dy)
            Qt.callLater(function() { root.focusActions(true) })
            event.accepted = true
          }

          delegate: AppRow {}

          // The headings are the list's sections, not rows: Up and Down step
          // over them, and the row numbers stay those of `results`. The
          // heading of the rows in view stays at the top of the list.
          section.property: "section"
          section.criteria: ViewSection.FullString
          section.labelPositioning: ViewSection.InlineLabels | ViewSection.CurrentLabelAtStart
          section.delegate: GroupHeading {}

          // The focused row in view, clear of the heading that stays at the
          // top: a row moved to from below would otherwise stop under it.
          function reveal(i) {
            positionViewAtIndex(i, ListView.Contain)
            var rows = root.results
            if (i < 0 || i >= rows.length || rows[i].section === "") return
            var item = itemAtIndex(i)
            if (!item) return
            var top = item.y - headingHeight(rows[i].section === rows[0].section)
            if (contentY > top) contentY = top
          }

          // A heading's height: room above it (less at the top of the list),
          // its line, and a little below.
          readonly property real headingLine: headingMetrics.height
          function headingHeight(first) {
            return (first ? 0 : Style.spacing.lg) + headingLine + Style.spacing.md
          }
          FontMetrics {
            id: headingMetrics
            font.family: Style.font.family
            font.pixelSize: Style.font.subtitle
            font.bold: true
          }

          Connections {
            target: root
            function onCurrentIndexChanged() {
              var i = root.currentIndex
              if (i >= 0) Qt.callLater(function() { appList.reveal(i) })
            }
          }

          // The focused row opens in place and gets taller: at once for what
          // it installs, again when its size has been read. While it is on
          // screen, all of it stays there, up to the heading at the top.
          function follow(item) {
            if (item.y < contentY || item.y >= contentY + height) return
            var over = item.y + item.height - (contentY + height)
            var room = item.y - contentY - (root.results.length > 0 && root.results[0].section !== "" ? headingHeight(false) : 0)
            if (over > 0 && room > 0) contentY += Math.min(over, room)
          }

          EmptyState {
            visible: root.apps.length === 0 && root.catalogFailed
            anchors.centerIn: parent
            width: parent.width
            centered: true
            iconName: "quick-install"
            title: "The Quick install list couldn't be read"
            body: "It should be at " + catalogFile.path + ". Updating karchy puts it back."
          }

          EmptyState {
            visible: root.results.length === 0 && catalogFile.loaded && !root.catalogFailed
            anchors.centerIn: parent
            width: parent.width
            centered: true
            iconName: root.searching ? "quick-install" : Model.categoryIcon(root.category)
            title: root.searching ? "No app matches “" + root.query.trim() + "”"
              : root.category === "installed" ? (root.statusLoaded ? "Nothing from this list is installed yet" : "Reading what's installed…")
              : "This category is empty"
            body: root.searching ? "Any other package can be installed from the menu: Packages › Install Package." : ""
            actionText: root.searching ? "Search all packages…" : ""
            onAction: Quickshell.execDetached(["xdg-terminal-exec", "--app-id=org.karchy.terminal", "karchy-pkg-install"])
          }
        }

        // The picked apps and what to do with them (D-109).
        BorderSurface {
          Layout.fillWidth: true
          visible: root.selectedApps.length > 0 || root.logPath !== ""
          implicitHeight: selectionRow.implicitHeight + Style.spacing.md * 2
          radius: Style.radius.surface
          color: Style.selectedFill
          borderSpec: Border.flat(Style.normalBorderColor, Style.border.control)

          RowLayout {
            id: selectionRow
            anchors.fill: parent
            anchors.margins: Style.spacing.md
            anchors.leftMargin: Style.spacing.rowPaddingX
            spacing: Style.spacing.lg

            Text {
              Layout.fillWidth: true
              textFormat: Text.PlainText
              text: Model.selectionText(root.selectedApps.length, root.selectedInTerminal, root.applying, root.applyVerb, root.lastRunText)
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              wrapMode: Text.Wrap
            }
            // Tab stops after the focused row's buttons, so what was picked
            // with Space can be installed without the mouse.
            Button {
              id: logButton
              visible: root.logPath !== ""
              focusable: true
              bordered: true
              text: "Show log"
              Keys.onTabPressed: function(event) { root.tabFromBar(logButton, event) }
              Keys.onBacktabPressed: function(event) { root.tabFromBar(logButton, event) }
              onClicked: root.showLog()
            }
            Button {
              id: reviewButton
              visible: root.selectedApps.length > 0 && root.category !== "picked"
              focusable: true
              bordered: true
              text: "Review"
              Keys.onTabPressed: function(event) { root.tabFromBar(reviewButton, event) }
              Keys.onBacktabPressed: function(event) { root.tabFromBar(reviewButton, event) }
              onClicked: root.setCategory("picked")
            }
            Button {
              id: clearButton
              visible: root.selectedApps.length > 0
              enabled: !root.applying
              focusable: true
              bordered: true
              text: "Clear"
              Keys.onTabPressed: function(event) { root.tabFromBar(clearButton, event) }
              Keys.onBacktabPressed: function(event) { root.tabFromBar(clearButton, event) }
              onClicked: root.clearSelected()
            }
            Button {
              id: removePickedButton
              visible: root.selectedToRemove.length > 0
              enabled: !root.applying
              focusable: true
              bordered: true
              variant: "destructive"
              text: "Remove " + root.selectedToRemove.length
              Keys.onTabPressed: function(event) { root.tabFromBar(removePickedButton, event) }
              Keys.onBacktabPressed: function(event) { root.tabFromBar(removePickedButton, event) }
              onClicked: root.askRemoveSelected()
            }
            Button {
              id: installPickedButton
              // Kept while its run goes on, though the apps leave the
              // selection as they finish; busy, it takes no clicks itself,
              // so it stays enabled and draws its spinner in full color.
              visible: root.selectedToInstall.length > 0 || busy
              enabled: !root.applying || busy
              focusable: true
              busy: root.applyingPicked
              bordered: true
              variant: "primary"
              text: busy ? "Installing…" : "Install " + Model.plural(root.selectedToInstall.length, "app", "apps")
              Keys.onTabPressed: function(event) { root.tabFromBar(installPickedButton, event) }
              Keys.onBacktabPressed: function(event) { root.tabFromBar(installPickedButton, event) }
              onClicked: root.installSelected()
            }
          }
        }

        // The keys, as in the menu's footer.
        Flow {
          Layout.fillWidth: true
          spacing: Style.spacing.xxl
          KeyHint { keys: "type"; label: "search" }
          KeyHint { icons: [Icons.glyph("ui.arrow.up"), Icons.glyph("ui.arrow.down")]; label: "move" }
          KeyHint {
            keys: "Enter"
            label: root.applyingPicked ? "installing picked…"
              : root.selectedToInstall.length > 0
                ? (root.applying ? "install picked, once this is done" : "install " + root.selectedToInstall.length + " picked")
              : !root.current ? "install or open"
              : root.isBusy(root.current.id) ? (root.applyVerb === "remove" ? "removing…" : "installing…")
              : root.isInstalled(root.current) ? (root.installed[root.current.id] !== "" ? "open" : "installed")
              : root.applying ? "install, once this is done"
              : "install"
          }
          KeyHint { keys: root.spacePicks ? "Space" : "Ctrl+Space"; label: "pick" }
          KeyHint { keys: "Tab"; label: "categories, buttons" }
          KeyHint { keys: "Esc"; label: root.searching ? "clear search" : "close" }
        }
      }
    }

    ConfirmDialog {
      id: confirmDialog
      anchors.fill: parent
      ownsKeys: true
      property Item returnFocus: null
      opened: root.pendingRemove !== null
      onOpenedChanged: if (opened) returnFocus = frame.Window.activeFocusItem
      message: root.pendingRemove
        ? "Remove " + Model.namesText(root.pendingRemove.names) + (root.pendingRemove.names.length === 1
            ? "? It is uninstalled; what it saved in your home folder is kept. You can install it again later."
            : "? They are uninstalled; what they saved in your home folder is kept. You can install them again later.")
        : ""
      confirmText: "Remove"
      onCanceled: {
        root.pendingRemove = null
        if (returnFocus) returnFocus.forceActiveFocus()
      }
      onConfirmed: {
        var pending = root.pendingRemove
        root.pendingRemove = null
        if (returnFocus) returnFocus.forceActiveFocus()
        if (pending) root.applyIds("remove", pending.ids)
      }
    }
  }

  // The focused row's buttons, in Tab order: its action, then Remove. Then
  // the bar under the list, then the search again.
  function focusActions(first) {
    var row = appList.itemAtIndex(root.currentIndex)
    var buttons = row ? row.actionButtons() : []
    if (buttons.length === 0) {
      if (!first) categoryList.forceActiveFocus(Qt.BacktabFocusReason)
      else if (!root.focusBar(true)) searchField.forceActiveFocus(Qt.TabFocusReason)
      return
    }
    buttons[first ? 0 : buttons.length - 1].forceActiveFocus(first ? Qt.TabFocusReason : Qt.BacktabFocusReason)
  }

  // The bar's buttons that can be pressed now, left to right.
  function barButtons() {
    return [logButton, reviewButton, clearButton, removePickedButton, installPickedButton].filter(function(b) {
      return b.visible && b.enabled && !b.busy
    })
  }

  function focusBar(first) {
    var buttons = root.barButtons()
    if (buttons.length === 0) return false
    buttons[first ? 0 : buttons.length - 1].forceActiveFocus(first ? Qt.TabFocusReason : Qt.BacktabFocusReason)
    return true
  }

  function tabFromBar(button, event) {
    var buttons = root.barButtons()
    var i = buttons.indexOf(button)
    if (event.key === Qt.Key_Tab) {
      if (i >= 0 && i < buttons.length - 1) buttons[i + 1].forceActiveFocus(Qt.TabFocusReason)
      else searchField.forceActiveFocus(Qt.TabFocusReason)
    } else {
      if (i > 0) buttons[i - 1].forceActiveFocus(Qt.BacktabFocusReason)
      else root.focusActions(false)
    }
    event.accepted = true
  }

  // ------------------------------------------------------------ components

  component AppRow: BorderSurface {
    id: row
    required property var modelData
    required property int index
    readonly property var app: modelData.app
    readonly property bool current: root.currentId === app.id
    readonly property bool installedHere: root.installed[app.id] !== undefined
    readonly property bool hasWindow: installedHere && root.installed[app.id] !== ""
    readonly property bool running: root.isBusy(app.id)
    readonly property bool otherRunning: root.applying && !running
    readonly property var progressState: root.progress[app.id]
    readonly property bool picked: root.isSelected(app.id)
    readonly property var info: root.infos[app.id]

    function actionButtons() {
      var out = []
      if (actionButton.visible && actionButton.enabled && !actionButton.busy) out.push(actionButton)
      if (details.item && details.item.removeButton.visible && details.item.removeButton.enabled) out.push(details.item.removeButton)
      return out
    }

    // Tab from the last button goes on to the bar under the list, or back
    // to the search; Shift+Tab from the first to the categories.
    function tabFrom(button, event) {
      var buttons = row.actionButtons()
      var i = buttons.indexOf(button)
      if (event.key === Qt.Key_Tab) {
        if (i >= 0 && i < buttons.length - 1) buttons[i + 1].forceActiveFocus(Qt.TabFocusReason)
        else if (!root.focusBar(true)) searchField.forceActiveFocus(Qt.TabFocusReason)
      } else {
        if (i > 0) buttons[i - 1].forceActiveFocus(Qt.BacktabFocusReason)
        else categoryList.forceActiveFocus(Qt.BacktabFocusReason)
      }
      event.accepted = true
    }

    width: ListView.view ? ListView.view.width - Style.spacing.md : 0
    implicitHeight: body.implicitHeight + Style.spacing.lg * 2
    radius: Style.radius.surface
    color: current ? Style.selectedFill : hover.hovered ? Style.hoverFill : "transparent"
    borderSpec: Border.flat(current ? Commons.Color.focus : Style.normalBorderColor, Style.border.control)

    HoverHandler { id: hover }
    TapHandler { onTapped: root.select(row.app.id) }
    onHeightChanged: if (current && ListView.view) ListView.view.follow(row)

    ColumnLayout {
      id: body
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.margins: Style.spacing.lg
      anchors.leftMargin: Style.spacing.rowPaddingX
      spacing: Style.spacing.lg

      RowLayout {
        Layout.fillWidth: true
        spacing: Style.spacing.xxl

        // Pick it for "Install N apps" (or Remove); Space does the same.
        PickBox {
          picked: row.picked
          enabled: !root.applying && !row.app.required
          onToggled: {
            root.select(row.app.id)
            root.toggleSelected(row.app)
          }
        }

        AppIcon { app: row.app }

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.xxs

          // The name, then its AUR tag right after it.
          Item {
            Layout.fillWidth: true
            implicitHeight: Math.max(nameText.implicitHeight, aurTag.implicitHeight)
            Text {
              id: nameText
              anchors.verticalCenter: parent.verticalCenter
              width: Math.min(implicitWidth, parent.width - (aurTag.visible ? aurTag.width + Style.spacing.md : 0))
              textFormat: Text.StyledText
              text: Search.highlighted(row.app.name, row.modelData.positions, Commons.Color.focus)
              color: Commons.Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }
            Tag {
              id: aurTag
              x: nameText.width + Style.spacing.md
              anchors.verticalCenter: parent.verticalCenter
              visible: row.app.source === "aur"
              text: "AUR"
            }
          }

          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: row.app.description || ""
            color: Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            // The focused row shows all of it.
            wrapMode: row.current ? Text.Wrap : Text.NoWrap
            maximumLineCount: row.current ? 4 : 1
          }

          // This app's part of the last install or removal.
          Text {
            Layout.fillWidth: true
            visible: !!row.progressState
            textFormat: Text.PlainText
            text: row.progressState ? Model.progressText(row.progressState, row.progressState.verb) : ""
            color: !row.progressState ? Commons.Color.textSecondary
              : row.progressState.state === "failed" ? Commons.Color.status.error
              : row.progressState.state === "done" ? Commons.Color.status.success
              : Commons.Color.textSecondary
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
          }
        }

        // Every installed app says so, before its Open button when it has a
        // window: Open alone reads like Install at a glance.
        RowLayout {
          visible: row.installedHere && !row.running
          spacing: Style.spacing.sm
          Text {
            text: Icons.glyph("ui.check")
            color: Commons.Color.status.success
            font.family: Icons.family
            font.pixelSize: Style.font.icon
          }
          Text {
            text: "Installed"
            color: Commons.Color.status.success
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
        }

        Button {
          id: actionButton
          visible: !row.installedHere || row.hasWindow || row.running
          focusable: row.current
          bordered: true
          // With apps picked, the bar's Install N apps is the main action.
          variant: row.current && !row.running && root.selectedToInstall.length === 0 ? "primary" : "neutral"
          busy: row.running
          text: row.running ? (root.applyVerb === "remove" ? "Removing…" : "Installing…")
            : row.installedHere ? "Open" : "Install"
          tooltipText: ""
          enabled: row.installedHere || !row.otherRunning
          Keys.onTabPressed: function(event) { row.tabFrom(actionButton, event) }
          Keys.onBacktabPressed: function(event) { row.tabFrom(actionButton, event) }
          onClicked: {
            root.select(row.app.id)
            if (row.installedHere) root.openApp(row.app)
            else root.run(row.app, "install")
          }
        }
      }

      Loader {
        id: details
        Layout.fillWidth: true
        // Line up with the name, past the icon.
        Layout.leftMargin: Style.space(34) + Style.spacing.xxl
        active: row.current
        visible: active
        sourceComponent: AppDetails {
          app: row.app
          info: row.info
          installedHere: row.installedHere
          removeEnabled: !root.applying
          onRemove: root.askRemove(row.app)
          onTabOut: function(button, event) { row.tabFrom(button, event) }
        }
      }
    }
  }

  // What the rows under it are for ("Coding agents"), or their category in
  // All and Installed, with how many there are.
  component GroupHeading: Item {
    id: heading
    required property string section
    readonly property bool first: root.results.length > 0 && root.results[0].section === section
    width: ListView.view ? ListView.view.width - Style.spacing.md : 0
    height: ListView.view ? ListView.view.headingHeight(first) : 0
    Accessible.role: Accessible.Heading
    Accessible.name: section

    // Rows scroll under the heading that stays at the top of the list.
    Rectangle {
      anchors.fill: parent
      color: Commons.Color.background
    }

    Row {
      anchors.left: parent.left
      anchors.bottom: parent.bottom
      anchors.bottomMargin: Style.spacing.md
      spacing: Style.spacing.md
      Text {
        id: headingName
        textFormat: Text.PlainText
        text: heading.section
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.subtitle
        font.bold: true
      }
      Text {
        anchors.baseline: headingName.baseline
        textFormat: Text.PlainText
        text: String(root.sectionCounts[heading.section] || "")
        color: Commons.Color.textSecondary
        font.family: Style.font.family
        font.pixelSize: Style.font.bodySmall
        font.features: { "tnum": 1 }
      }
    }
  }

  // What the focused row installs, from where, how big, and what else.
  component AppDetails: ColumnLayout {
    id: detailsView
    property var app: ({})
    property var info: undefined
    property bool installedHere: false
    property bool removeEnabled: true
    property alias removeButton: removeButton
    signal remove()
    signal tabOut(Item button, var event)

    readonly property var setup: Model.setupLines(app, root.multilibOn)
    readonly property string size: info === "loading" ? "Reading…"
      : Model.sizeText(info, app.source === "aur", !!app.multilib && !root.multilibOn)
    readonly property var rows: {
      var out = [{ label: installedHere ? "Installed" : "Installs", value: Model.installsText(app, info) }]
      if (!app.feature && size !== "") out.push({ label: "Size", value: size })
      out.push({ label: "Setup", value: setup.length > 0 ? setup.join(" ") : "Nothing else to set up." })
      if (app.setup && app.setup.note) out.push({ label: "Note", value: app.setup.note })
      // The apps karchy ships (D-71): removable like any other, except the
      // few karchy itself needs.
      if (app.required) out.push({ label: "Comes with karchy", value: "It can't be removed: " + app.required + "." })
      else if (app.default) out.push({ label: "Comes with karchy", value: "You can remove it, and install it again here later." })
      return out
    }

    spacing: Style.spacing.lg

    PanelSeparator { Layout.fillWidth: true }

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.sm

      Repeater {
        model: detailsView.rows.length * 2
        delegate: Text {
          required property int index
          readonly property var pair: detailsView.rows[Math.floor(index / 2)]
          readonly property bool isLabel: index % 2 === 0
          Layout.fillWidth: !isLabel
          Layout.alignment: Qt.AlignTop
          textFormat: Text.PlainText
          text: isLabel ? pair.label : pair.value
          color: isLabel ? Commons.Color.textSecondary : Commons.Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: isLabel ? Text.NoWrap : Text.Wrap
        }
      }
    }

    Button {
      id: removeButton
      Layout.alignment: Qt.AlignRight
      visible: detailsView.installedHere && !detailsView.app.required
      focusable: true
      variant: "destructive"
      bordered: true
      text: "Remove…"
      enabled: detailsView.removeEnabled
      Keys.onTabPressed: function(event) { detailsView.tabOut(removeButton, event) }
      Keys.onBacktabPressed: function(event) { detailsView.tabOut(removeButton, event) }
      onClicked: detailsView.remove()
    }
  }

  // The app's own icon from the icon theme (Papirus), or its first letter
  // on a tile tinted from the theme's palette.
  // A checkbox: the theme's border and fill, a check glyph when picked.
  component PickBox: BorderSurface {
    id: box
    property bool picked: false
    signal toggled()
    implicitWidth: Style.space(18)
    implicitHeight: Style.space(18)
    radius: Style.radius.control
    opacity: enabled ? 1 : 0.4
    color: picked ? Commons.Color.focus : "transparent"
    borderSpec: Border.flat(picked ? Commons.Color.focus : Style.normalBorderColor, Style.border.control)
    Text {
      anchors.centerIn: parent
      visible: box.picked
      text: Icons.glyph("ui.check")
      color: Commons.Color.background
      font.family: Icons.family
      font.pixelSize: Style.font.iconSmall
    }
    TapHandler { enabled: box.enabled; onTapped: box.toggled() }
    HoverHandler { cursorShape: Qt.PointingHandCursor }
  }

  component AppIcon: Item {
    id: icon
    property var app: ({})
    readonly property string source: app.icon ? Quickshell.iconPath(app.icon, true) : ""
    // Kept readable on the window's background, as a letter in light and dark themes.
    readonly property color tint: {
      var keys = Model.tileKeys(app.name)
      var hex = Commons.Color.paletteValues[keys[0]] || Commons.Color.paletteValues[keys[1]]
      return Commons.Color.ensureContrastToward(hex ? Qt.color(hex) : Commons.Color.accent,
        Commons.Color.foreground, Commons.Color.background, 3.0)
    }
    Layout.preferredWidth: Style.space(34)
    Layout.preferredHeight: Style.space(34)
    Layout.alignment: Qt.AlignVCenter

    Image {
      id: image
      anchors.fill: parent
      visible: icon.source !== "" && status === Image.Ready
      source: icon.source
      fillMode: Image.PreserveAspectFit
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      asynchronous: true
    }

    Rectangle {
      anchors.fill: parent
      visible: !image.visible
      radius: Math.max(Style.radius.control, Style.space(6))
      color: Util.alpha(icon.tint, 0.18)
      border.width: Style.border.control
      border.color: Util.alpha(icon.tint, 0.45)
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: String(icon.app.name || "?").replace(/[^A-Za-z0-9]/g, "").charAt(0).toUpperCase()
        color: icon.tint
        font.family: Style.font.family
        font.pixelSize: Style.font.heading
        font.bold: true
      }
    }
  }

  // A small bordered label: "AUR".
  component Tag: BorderSurface {
    property alias text: tagText.text
    implicitWidth: tagText.implicitWidth + Style.spacing.md * 2
    implicitHeight: tagText.implicitHeight + Style.spacing.xxs * 2
    radius: Style.radius.control
    color: "transparent"
    borderSpec: Border.flat(Style.normalBorderColor, Style.border.control)
    Text {
      id: tagText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // One key and what it does, for the footer.
  component KeyHint: Row {
    id: hint
    property string keys: ""
    // Keys that have no name to write (the arrow keys), as glyphs: drawn in
    // the icon font, so they look the same in every text font.
    property var icons: []
    property string label: ""
    spacing: Style.spacing.md
    BorderSurface {
      anchors.verticalCenter: parent.verticalCenter
      width: (hint.icons.length > 0 ? keyIcons.implicitWidth : keyText.implicitWidth) + Style.spacing.md * 2
      // The text font's line, with or without text, so every key is one height.
      height: keyText.implicitHeight + Style.spacing.xxs * 2
      radius: Style.radius.control
      color: "transparent"
      borderSpec: Border.flat(Style.normalBorderColor, Style.border.control)
      Text {
        id: keyText
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: hint.keys
        color: Commons.Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
      Row {
        id: keyIcons
        anchors.centerIn: parent
        // Each fills its em, so two would touch.
        spacing: Style.spacing.xxs
        Repeater {
          model: hint.icons
          Text {
            required property string modelData
            textFormat: Text.PlainText
            text: modelData
            color: Commons.Color.foreground
            font.family: Icons.family
            font.pixelSize: Style.font.iconSmall
          }
        }
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: parent.label
      color: Commons.Color.textSecondary
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  // A read that can be asked for again while running; it runs once more
  // after, so the newest state always lands.
  component Query: Process {
    id: query
    property bool again: false
    signal result(string text)

    function request() {
      if (running) again = true
      else if (command.length > 0) running = true
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: query.result(text)
    }
    onExited: if (again) {
      again = false
      running = true
    }
  }
}
