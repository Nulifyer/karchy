import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "KeybindingsModel.js" as Model

// Settings › Keybindings (D-134): every binding, where it comes from and what
// overrides what, with the editing of VS Code's Keyboard Shortcuts. The list
// and every change are karchy-settings-keybindings's (`list --json`); the page
// adds the search, the filters and the key capture.
//
// Keyboard: Tab reaches the search, the controls and then the list as one
// stop. In the list Up/Down (or j/k) move, Enter changes the binding, A adds
// another one for the same action, Delete removes it and R resets it. While
// keys are being captured Enter accepts and Escape clears, then cancels.
ColumnLayout {
  id: root
  spacing: Style.spacing.xxl

  // The Settings window, for its confirm dialog (set by its Loader).
  property var settings: null
  property var listing: ({ rows: [], errors: [], stale: [], changes: 0 })
  property bool loaded: false
  property string error: ""

  property string searchText: ""
  property string filter: "all"
  // "Record keys": the combination being searched for, and the rows on it.
  property bool recording: false
  property string recordedKeys: ""
  property var recordedLabels: []
  property var recordedIds: null

  readonly property var rows: Model.visibleRows(listing.rows, searchText, filter, recordedKeys !== "" ? (recordedIds || []) : null)
  readonly property var groups: Model.grouped(rows)
  property string currentId: ""
  readonly property var currentRow: {
    for (var i = 0; i < rows.length; i++) if (rows[i].id === currentId) return rows[i]
    return null
  }

  // What is being captured: "" (nothing), "change" or "another" (for the
  // current row), "custom" (the form's keys), "record" (the search).
  property string capture: ""
  property string capturedKeys: ""
  property var capturedLabels: []
  property var pendingMods: []
  // The actions the captured keys already have, once the command has said.
  property var captureConflicts: []
  property bool confirming: false
  property bool adding: false

  // Row items by id, for scrolling the current one into view.
  property var rowItems: ({})
  // The keys a change just bound: the row that has them becomes the current
  // one when the new list arrives, so what was added is where the cursor is.
  property string selectKeys: ""

  function refresh() { if (!listProc.running && !changeProc.running) listProc.running = true }

  function load(text) {
    try {
      var parsed = JSON.parse(text)
      if (!parsed || !parsed.rows) return
      root.listing = parsed
      root.loaded = true
      if (root.selectKeys !== "") {
        var wanted = root.selectKeys
        root.selectKeys = ""
        for (var i = 0; i < parsed.rows.length; i++) {
          if (parsed.rows[i].keys !== wanted) continue
          // Shown whatever the search and the filter were.
          if (!root.rows.some(function(row) { return row.id === parsed.rows[i].id })) { searchField.text = ""; root.searchText = ""; root.filter = "all"; filterDropdown.value = "all" }
          root.currentId = parsed.rows[i].id
          list.forceActiveFocus()
          revealSoon.restart()
          break
        }
      }
      if (!root.currentRow && root.rows.length > 0) root.currentId = root.rows[0].id
    } catch (e) {}
  }

  function run(args) {
    if (changeProc.running) return
    root.error = ""
    root.selectKeys = args[0] === "add" ? args[1] : ""
    changeProc.command = ["karchy-settings-keybindings"].concat(args).concat(["--json"])
    changeProc.running = true
  }

  function move(delta) {
    if (root.rows.length === 0) return
    var index = 0
    for (var i = 0; i < root.rows.length; i++) if (root.rows[i].id === root.currentId) index = i
    index = Math.max(0, Math.min(root.rows.length - 1, index + delta))
    root.currentId = root.rows[index].id
    root.reveal()
  }

  function reveal() {
    var item = root.rowItems[root.currentId]
    if (item && root.settings) root.settings.revealFocused(item)
  }

  // A click selects the row where it is: the list takes the keyboard without
  // the page scrolling (list.revealItem).
  function selectByPointer(id) {
    root.currentId = id
    list.byPointer = true
    list.forceActiveFocus()
    list.byPointer = false
  }

  // The keys a row is known by to the command: what it has, or had.
  function rowKeys(row) { return row.keys !== "" ? row.keys : row.firstKeys }

  function startCapture(kind) {
    if (kind === "change" || kind === "another") {
      if (!root.currentRow || root.currentRow.readOnly !== "") return
      if (root.adding) root.closeForm()
    }
    root.capture = kind
    root.capturedKeys = ""
    root.capturedLabels = []
    root.pendingMods = []
    root.captureConflicts = []
    root.confirming = false
    catcher.forceActiveFocus()
    // The row's "Press the new key combination" line, once it is laid out.
    if (kind === "change" || kind === "another") revealSoon.restart()
  }

  function endCapture(returnFocus) {
    var was = root.capture
    root.capture = ""
    root.confirming = false
    if (!returnFocus) return
    if (was === "custom") saveButton.forceActiveFocus()
    else if (was === "record") recordButton.forceActiveFocus()
    else list.forceActiveFocus()
  }

  function stopRecording() {
    root.recording = false
    root.recordedKeys = ""
    root.recordedLabels = []
    root.recordedIds = null
    if (root.capture === "record") root.endCapture(true)
  }

  // Enter in the capture: keys another action has ask first; free ones save.
  function acceptCapture() {
    if (root.capturedKeys === "" || conflictProc.running) return
    if (root.capture === "custom") { root.endCapture(true); return }
    var others = root.captureConflicts.filter(function(other) { return !root.currentRow || other.id !== root.currentRow.id })
    if (others.length > 0) {
      // The row's own Replace, Keep both and Cancel take over.
      root.confirming = true
      return
    }
    root.commit("")
  }

  function commit(mode) {
    var row = root.currentRow
    var extra = mode !== "" ? [mode] : []
    if (root.capture === "another") root.run(["add", root.capturedKeys, "--action", row.action].concat(extra))
    else root.run(["set", row.action, root.capturedKeys, "--from", root.rowKeys(row)].concat(extra))
    root.endCapture(true)
  }

  function removeCurrent() {
    var row = root.currentRow
    // Something to take away: keys in effect, or a rule of the person's own
    // that their bindings.lua unbinds.
    if (!row || row.readOnly !== "" || (row.keys === "" && row.defaultKeys !== "")) return
    root.run(["remove", row.action, root.rowKeys(row)])
  }

  function resetCurrent() {
    var row = root.currentRow
    if (!row || row.readOnly !== "" || row.defaultKeys === "" || row.state === "default") return
    root.run(["reset", row.action, row.defaultKeys])
  }

  function saveCustom() {
    if (descriptionField.text.trim() === "" || commandField.text.trim() === "" || root.capturedKeys === "") return
    // Keys another action has: say so once, then "Add anyway" keeps both.
    if (root.captureConflicts.length > 0 && !root.confirming) {
      root.confirming = true
      return
    }
    root.run(["add", root.capturedKeys, "--command", commandField.text.trim(), "--description", descriptionField.text.trim()]
      .concat(root.confirming ? ["--keep-both"] : []))
  }

  function closeForm() {
    root.adding = false
    root.confirming = false
    root.capturedKeys = ""
    root.capturedLabels = []
    descriptionField.text = ""
    commandField.text = ""
    // After an add, the new row has the keyboard (load()).
    if (!list.activeFocus) addButton.forceActiveFocus()
  }

  // Once the new rows are laid out.
  Timer { id: revealSoon; interval: 150; onTriggered: root.reveal() }

  Component.onCompleted: refresh()
  onRowsChanged: if (!currentRow && rows.length > 0) currentId = rows[0].id

  Process {
    id: listProc
    command: ["karchy-settings-keybindings", "list", "--json"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.load(text) }
  }

  // A change prints the new list on success and one line on stderr when it
  // is refused.
  Process {
    id: changeProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: if (text.trim() !== "") root.load(text) }
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: root.error = text.trim() }
    onExited: function(code) {
      if (code !== 0) root.selectKeys = ""
      if (code === 0 && root.adding) root.closeForm()
      root.confirming = false
    }
  }

  // What the captured keys are bound to now, and their key caps.
  Process {
    id: conflictProc
    property string forKeys: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var answer = JSON.parse(text)
          if (root.capture === "record" || (root.recording && root.capture === "")) {
            if (conflictProc.forKeys !== root.recordedKeys) return
            root.recordedLabels = answer.labels
            root.recordedIds = answer.rows.map(function(row) { return row.id })
          } else {
            if (conflictProc.forKeys !== root.capturedKeys) return
            root.capturedLabels = answer.labels
            root.captureConflicts = answer.rows
          }
        } catch (e) {}
      }
    }
  }

  function lookUp(keys) {
    conflictProc.running = false
    conflictProc.forKeys = keys
    conflictProc.command = ["karchy-settings-keybindings", "conflicts", keys]
    conflictProc.running = true
  }

  // The key capture: an item that holds the keyboard while keys are wanted.
  // The inhibitor asks Hyprland to hand over its own shortcuts (Super+T
  // arrives here instead of running); it ends with the focus, the window or
  // the shell, so nothing can stay captured.
  Item {
    id: catcher
    width: 0
    height: 0
    // No room of its own in the page's column: without this the gap after it
    // put this page's title lower than every other page's.
    Layout.bottomMargin: -root.spacing
    focus: false
    // It sits at the top of the page; what is being changed is elsewhere
    // (Settings.revealFocused).
    function revealItem() { return null }
    onActiveFocusChanged: if (!activeFocus && root.capture !== "" && !root.confirming) {
      if (root.capture === "record") root.recording = root.recordedKeys !== ""
      root.endCapture(false)
    }
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      event.accepted = true
      if (event.isAutoRepeat) return
      if (Model.isPlain(event.key, event.modifiers, "escape")) {
        if (root.capture === "record") root.stopRecording()
        else if (root.capturedKeys !== "") { root.capturedKeys = ""; root.capturedLabels = []; root.captureConflicts = [] }
        else root.endCapture(true)
        return
      }
      if (root.capture !== "record" && Model.isPlain(event.key, event.modifiers, "enter")) {
        root.acceptCapture()
        return
      }
      var pressed = Model.captureKeys(event.key, event.modifiers, event.nativeScanCode)
      root.pendingMods = pressed.mods
      if (!pressed.complete) return
      if (root.capture === "record") {
        root.recordedKeys = pressed.keys
        root.recordedLabels = Model.roughLabels(pressed.keys)
        root.recordedIds = null
      } else {
        root.capturedKeys = pressed.keys
        root.capturedLabels = Model.roughLabels(pressed.keys)
        root.captureConflicts = []
      }
      root.lookUp(pressed.keys)
    }
    Keys.onReleased: function(event) { event.accepted = true; root.pendingMods = [] }
  }

  ShortcutInhibitor {
    window: root.QsWindow.window
    enabled: catcher.activeFocus && root.capture !== ""
  }

  // Key caps: [Super] [Shift] [T].
  component KeyCaps: Row {
    property var labels: []
    property bool faded: false
    property bool struck: false
    spacing: Style.spacing.xs
    Repeater {
      model: parent.labels
      delegate: Rectangle {
        required property var modelData
        implicitWidth: capText.implicitWidth + Style.spacing.md * 2
        implicitHeight: capText.implicitHeight + Style.spacing.xxs * 2
        radius: Style.radius.control
        color: Util.alpha(Commons.Color.foreground, parent.faded ? 0.03 : 0.07)
        border.width: Math.max(1, Style.space(1))
        border.color: Util.alpha(Commons.Color.foreground, parent.faded ? 0.15 : 0.3)
        Text {
          id: capText
          anchors.centerIn: parent
          textFormat: Text.PlainText
          text: String(modelData)
          color: parent.parent.faded ? Commons.Color.textSecondary : Commons.Color.foreground
          // A key's name, as it is typed in bindings.lua.
          font.family: Style.font.mono
          font.pixelSize: Style.font.bodySmall
          font.strikeout: parent.parent.struck
        }
      }
    }
  }

  component Quiet: Text {
    textFormat: Text.PlainText
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.bodySmall
  }

  PageHeader {
    title: "Keybindings"
    explanation: "Changes apply at once and are kept in keybindings.json. A binding in your own bindings.lua loads last and wins: it shows here and is changed there. In the list: Enter changes a binding, A adds another for the same action, Delete removes it, R brings the default back."
    ConfigFileLink { closes: root.settings; file: ".config/hypr/bindings.lua" }
  }

  InlineMessage {
    kind: "error"
    text: root.error
    dismissible: true
    onDismissed: root.error = ""
  }

  // What Hyprland said about the files it loaded, and rules that no longer
  // match anything.
  InlineMessage {
    kind: "warning"
    text: root.listing.errors && root.listing.errors.length > 0 ? root.listing.errors.join(" ") : ""
  }
  InlineMessage {
    kind: "info"
    text: root.listing.stale && root.listing.stale.length > 0
      ? (root.listing.stale.length === 1 ? "One of your changes no longer applies: " : root.listing.stale.length + " of your changes no longer apply: ")
        + root.listing.stale.map(function(item) { return item.text }).join("; ") + "."
      : ""
    actionText: "Remove"
    onAction: root.run(["reset", "--stale"])
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Style.spacing.md

    TextField {
      id: searchField
      Layout.fillWidth: true
      visible: !root.recording
      placeholderText: "Search actions and keys"
      onTextEdited: root.searchText = text
      Keys.onDownPressed: list.forceActiveFocus()
    }
    // The recorded combination stands where the search was.
    RowLayout {
      visible: root.recording
      Layout.fillWidth: true
      spacing: Style.spacing.md
      Quiet {
        visible: root.recordedKeys === ""
        text: root.pendingMods.length > 0 ? root.pendingMods.join(" + ") + " + …" : "Press the keys to look for"
        font.pixelSize: Style.font.body
      }
      KeyCaps { labels: root.recordedLabels }
      Quiet { visible: root.recordedKeys !== ""; text: root.rows.length === 0 ? "Not bound" : "" }
      Item { Layout.fillWidth: true; implicitHeight: searchField.implicitHeight }
    }

    Button {
      id: recordButton
      focusable: true
      bordered: true
      selected: root.recording
      iconText: Icons.glyph("input.keyboard")
      text: root.recording ? "Stop" : "Record keys"
      accessibleName: root.recording ? "Stop looking for recorded keys" : "Search by pressing a key combination"
      onClicked: {
        if (root.recording) { root.stopRecording(); return }
        root.recording = true
        root.startCapture("record")
      }
    }

    Dropdown {
      id: filterDropdown
      Layout.preferredWidth: Style.space(130)
      showLabel: false
      value: root.filter
      options: Model.FILTERS
      onChanged: function(value) { root.filter = value }
    }

    Button {
      id: addButton
      focusable: true
      bordered: true
      enabled: !root.adding
      text: "Add…"
      accessibleName: "Add a keybinding that runs a command"
      onClicked: {
        root.adding = true
        root.capturedKeys = ""
        root.capturedLabels = []
        root.captureConflicts = []
        descriptionField.forceActiveFocus()
      }
    }
  }

  // A binding of the person's own: a name, a command and keys.
  Section {
    visible: root.adding
    title: "New keybinding"

    GridLayout {
      Layout.fillWidth: true
      columns: 2
      columnSpacing: Style.spacing.xxl
      rowSpacing: Style.spacing.md

      SettingsLabel { text: "Name" }
      TextField { id: descriptionField; Layout.fillWidth: true; placeholderText: "What it does, such as SSH to my server" }
      SettingsLabel { text: "Command" }
      TextField { id: commandField; Layout.fillWidth: true; placeholderText: "footclient ssh my-server" }
      SettingsLabel { text: "Keys" }
      RowLayout {
        spacing: Style.spacing.md
        Button {
          id: keysButton
          focusable: true
          bordered: true
          selected: root.capture === "custom"
          text: root.capture === "custom" ? "Press the keys, then Enter" : root.capturedKeys === "" ? "Record keys…" : "Change…"
          onClicked: root.startCapture("custom")
        }
        KeyCaps { labels: root.adding ? (root.capturedKeys !== "" ? root.capturedLabels : root.capture === "custom" ? root.pendingMods : []) : [] }
        Item { Layout.fillWidth: true; implicitHeight: 1 }
      }
    }

    Text {
      visible: root.adding && root.capturedKeys !== "" && root.captureConflicts.length > 0
      Layout.fillWidth: true
      textFormat: Text.PlainText
      wrapMode: Text.Wrap
      text: "Also bound to: " + root.captureConflicts.map(function(row) { return row.action }).join(", ")
        + (root.confirming ? ". Both will run on these keys." : "")
      color: Commons.Color.status.warning
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    RowLayout {
      spacing: Style.spacing.md
      Button {
        id: saveButton
        focusable: true
        variant: "primary"
        busy: changeProc.running
        enabled: descriptionField.text.trim() !== "" && commandField.text.trim() !== "" && root.capturedKeys !== "" && root.capture === ""
        text: root.adding && root.confirming ? "Add anyway" : "Add keybinding"
        onClicked: root.saveCustom()
      }
      Button { focusable: true; bordered: true; text: "Cancel"; onClicked: root.closeForm() }
    }
  }

  Text {
    visible: root.loaded && root.rows.length === 0
    Layout.fillWidth: true
    textFormat: Text.PlainText
    text: root.recordedKeys !== "" ? "Nothing is bound to these keys."
      : root.searchText.trim() !== "" ? "No keybinding matches \"" + root.searchText.trim() + "\"."
      : root.filter === "changed" ? "Nothing is changed: every binding is as karchy ships it."
      : root.filter === "conflicts" ? "No two actions share keys."
      : root.filter === "yours" ? "Nothing is set in your own bindings.lua."
      : root.filter === "addons" ? "No add-on brings keybindings."
      : ""
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }

  // The list: one Tab stop, the current row moved with the arrows.
  ColumnLayout {
    id: list
    Layout.fillWidth: true
    spacing: Style.spacing.lg
    activeFocusOnTab: root.rows.length > 0
    Accessible.role: Accessible.List
    Accessible.name: "Keybindings"

    // What Settings keeps in view when the keyboard comes here: the current
    // row, or nothing after a click (root.selectByPointer).
    property bool byPointer: false
    function revealItem() { return byPointer ? null : (root.rowItems[root.currentId] || null) }
    Keys.onUpPressed: root.move(-1)
    Keys.onDownPressed: root.move(1)
    // A held key repeats: the Enter that accepted a capture must not start
    // the next one, and one press removes one binding.
    Keys.onReturnPressed: function(event) { if (!event.isAutoRepeat) root.startCapture("change") }
    Keys.onEnterPressed: function(event) { if (!event.isAutoRepeat) root.startCapture("change") }
    Keys.onDeletePressed: function(event) { if (!event.isAutoRepeat) root.removeCurrent() }
    Keys.onPressed: function(event) {
      if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return
      var once = !event.isAutoRepeat
      if (event.text === "j") root.move(1)
      else if (event.text === "k") root.move(-1)
      else if (event.text === "a") { if (once) root.startCapture("another") }
      else if (event.text === "r") { if (once) root.resetCurrent() }
      else if (event.key === Qt.Key_Backspace) { if (once) root.removeCurrent() }
      else if (event.key === Qt.Key_Home) root.move(-10000)
      else if (event.key === Qt.Key_End) root.move(10000)
      else if (event.key === Qt.Key_PageDown) root.move(10)
      else if (event.key === Qt.Key_PageUp) root.move(-10)
      else return
      event.accepted = true
    }

    Repeater {
      model: root.groups

      delegate: Section {
        id: groupSection
        required property var modelData
        title: modelData.name
        contentSpacing: 0

        Repeater {
          model: groupSection.modelData.rows

          delegate: ColumnLayout {
            id: rowItem
            required property var modelData
            readonly property bool current: root.currentId === modelData.id
            readonly property bool editing: current && (root.capture === "change" || root.capture === "another" || (root.confirming && !root.adding))
            readonly property bool editable: modelData.readOnly === ""
            Layout.fillWidth: true
            spacing: 0
            Component.onCompleted: root.rowItems[modelData.id] = rowItem
            Component.onDestruction: if (root.rowItems[modelData.id] === rowItem) delete root.rowItems[modelData.id]

            Accessible.role: Accessible.ListItem
            Accessible.name: modelData.action + ", " + (modelData.labels.length > 0 ? modelData.labels.join(" + ") : "not bound") + ", from " + modelData.source

            Rectangle {
              Layout.fillWidth: true
              implicitHeight: line.implicitHeight + Style.spacing.sm * 2
              radius: Style.radius.control
              color: rowItem.current ? Style.selectedFill : rowMouse.containsMouse ? Style.hoverFill : "transparent"

              FocusRing { shown: rowItem.current && list.activeFocus; keyboardOnly: false }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                onClicked: root.selectByPointer(rowItem.modelData.id)
                onDoubleClicked: { root.currentId = rowItem.modelData.id; root.startCapture("change") }
              }

              RowLayout {
                id: line
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.md
                anchors.rightMargin: Style.spacing.sm
                spacing: Style.spacing.lg

                Text {
                  Layout.fillWidth: true
                  textFormat: Text.PlainText
                  text: rowItem.modelData.action
                  color: rowItem.modelData.keys === "" ? Commons.Color.textSecondary : Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                  elide: Text.ElideRight
                }

                Item {
                  Layout.preferredWidth: Style.space(180)
                  implicitHeight: caps.implicitHeight
                  KeyCaps { id: caps; anchors.verticalCenter: parent.verticalCenter; labels: rowItem.modelData.labels }
                  Quiet { visible: rowItem.modelData.keys === ""; anchors.verticalCenter: parent.verticalCenter; text: "Not bound" }
                }

                // Where the binding in effect comes from.
                Quiet {
                  Layout.preferredWidth: Style.space(128)
                  text: rowItem.modelData.source
                  color: rowItem.modelData.layer === "settings" ? Commons.Color.focus
                    : rowItem.modelData.layer === "user" ? Commons.Color.foreground : Commons.Color.textSecondary
                  elide: Text.ElideRight
                }

                // Shown for the current row; the room is always kept.
                Item {
                  implicitWidth: actions.implicitWidth
                  implicitHeight: actions.implicitHeight
                  RowLayout {
                    id: actions
                    spacing: 0
                    opacity: rowItem.current || rowMouse.containsMouse ? 1 : 0
                    PanelActionButton {
                      enabled: rowItem.editable
                      iconText: Icons.glyph(rowItem.editable ? "ui.edit" : "system.lock")
                      tooltipText: rowItem.editable ? (rowItem.modelData.keys === "" ? "Give it keys (Enter)" : "Change the keys (Enter)") : rowItem.modelData.readOnly
                      onClicked: { root.currentId = rowItem.modelData.id; root.startCapture("change") }
                    }
                    PanelActionButton {
                      readonly property bool resets: rowItem.modelData.defaultKeys !== "" && rowItem.modelData.state !== "default"
                      enabled: rowItem.editable && (resets || rowItem.modelData.keys !== "" || rowItem.modelData.defaultKeys === "")
                      iconText: Icons.glyph(resets ? "ui.undo" : "ui.delete")
                      tooltipText: !rowItem.editable ? "" : resets ? "Back to the default (R)" : "Remove (Delete)"
                      onClicked: {
                        root.currentId = rowItem.modelData.id
                        if (resets) root.resetCurrent()
                        else root.removeCurrent()
                      }
                    }
                  }
                }
              }
            }

            // The layers this binding went through, lowest first; what was
            // replaced or removed is struck through, never hidden.
            Flow {
              visible: Model.chainShown(rowItem.modelData) || rowItem.modelData.conflicts.length > 0 || (rowItem.current && !rowItem.editable)
              Layout.fillWidth: true
              Layout.leftMargin: Style.spacing.md
              Layout.bottomMargin: Style.spacing.sm
              spacing: Style.spacing.md

              Repeater {
                model: Model.chainShown(rowItem.modelData) ? rowItem.modelData.chain : []
                delegate: Row {
                  required property var modelData
                  required property int index
                  spacing: Style.spacing.sm
                  Quiet { anchors.verticalCenter: parent.verticalCenter; text: (index > 0 ? "→  " : "") + modelData.source + ":" }
                  KeyCaps { anchors.verticalCenter: parent.verticalCenter; labels: modelData.labels; faded: modelData.state !== "wins"; struck: modelData.state !== "wins" }
                  Quiet { anchors.verticalCenter: parent.verticalCenter; text: "(" + Model.chainNote(modelData) + ")" }
                }
              }
              Quiet {
                visible: rowItem.modelData.conflicts.length > 0
                text: "Also bound to: " + rowItem.modelData.conflicts.join(", ")
                color: Commons.Color.status.warning
              }
              Quiet {
                visible: rowItem.current && !rowItem.editable
                text: rowItem.modelData.readOnly
              }
            }

            // Capturing new keys for this row.
            ColumnLayout {
              visible: rowItem.editing
              Layout.fillWidth: true
              Layout.leftMargin: Style.spacing.md
              Layout.topMargin: Style.spacing.sm
              Layout.bottomMargin: Style.spacing.lg
              spacing: Style.spacing.md

              RowLayout {
                spacing: Style.spacing.lg
                Text {
                  textFormat: Text.PlainText
                  text: root.confirming ? "New keys:" : root.capture === "another" ? "Press one more key combination, then Enter." : "Press the new key combination, then Enter."
                  color: Commons.Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                KeyCaps { labels: rowItem.editing ? (root.capturedKeys !== "" ? root.capturedLabels : root.pendingMods) : [] }
                Quiet { visible: !root.confirming; text: root.capturedKeys === "" ? "Esc cancels" : "Esc clears" }
                Item { Layout.fillWidth: true; implicitHeight: 1 }
              }
              Text {
                visible: rowItem.editing && root.captureConflicts.some(function(other) { return other.id !== rowItem.modelData.id })
                Layout.fillWidth: true
                textFormat: Text.PlainText
                wrapMode: Text.Wrap
                text: "Also bound to: " + root.captureConflicts.filter(function(other) { return other.id !== rowItem.modelData.id })
                  .map(function(other) { return other.action }).join(", ")
                color: Commons.Color.status.warning
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              // Keys another action has: unbind that, keep both, or leave it.
              RowLayout {
                visible: rowItem.editing && root.confirming
                spacing: Style.spacing.md
                onVisibleChanged: if (visible) replaceButton.forceActiveFocus()
                Button {
                  id: replaceButton
                  focusable: true
                  variant: "primary"
                  text: "Replace"
                  accessibleName: "Use these keys here and unbind the other action"
                  onClicked: root.commit("--replace")
                  Keys.onEscapePressed: root.endCapture(true)
                }
                Button { focusable: true; bordered: true; text: "Keep both"; onClicked: root.commit("--keep-both"); Keys.onEscapePressed: root.endCapture(true) }
                Button { focusable: true; bordered: true; text: "Cancel"; onClicked: root.endCapture(true); Keys.onEscapePressed: root.endCapture(true) }
                Quiet { text: "Replace unbinds the other action. Keep both runs both." }
              }
            }
          }
        }
      }
    }
  }

  Button {
    visible: root.listing.changes > 0
    focusable: true
    bordered: true
    variant: "destructive"
    text: "Reset all…"
    accessibleName: "Remove every keybinding change made in Settings"
    onClicked: if (root.settings) root.settings.ask(
      "Go back to karchy's keybindings? " + (root.listing.changes === 1 ? "The one change" : "All " + root.listing.changes + " changes")
        + " made here are forgotten, your own added bindings included. Your bindings.lua is not touched.",
      "Reset all", function() { root.run(["reset", "--all"]) })
  }
}
