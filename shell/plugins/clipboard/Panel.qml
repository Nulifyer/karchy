import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "ClipboardHistory.js" as ClipboardHistory

// The clipboard in the bar (D-167): by default in the tray's drawer, the part
// of the bar that opens on hover. Its panel answers "what did I copy?": the
// pinned entries and the newest of the rest. A click (or Enter) pastes an
// entry where the cursor was, as the picker does; Pin and Delete are on each
// row and Clear all under them. Search, previews and everything older are in
// the picker (Clipboard.qml), which the button in the header and a right
// click on the bar icon open. Both read the same service (Service.qml).
Panel {
  id: root
  moduleName: "karchy.clipboard"

  readonly property var service: bar && bar.shell ? bar.shell.services["karchy.clipboard"] || null : null
  readonly property var history: service ? service.history : []
  // How many rows each of the two lists shows at most.
  readonly property int maxRows: 5
  readonly property var lists: ClipboardHistory.panelRows(history, maxRows, I18n.t, I18n.tn, I18n.formatNumber)
  readonly property var rows: lists.pinned.concat(lists.recent)
  readonly property int pinnedCount: history.length - (service ? service.unpinnedCount : 0)
  readonly property bool canClear: !!service && service.unpinnedCount > 0
  readonly property bool recording: !service || service.recording

  // The keyboard's stops, in order: the rows (by entry id), then Clear all
  // (when there is something to clear), the history switch, and the picker
  // button in the header. The cursor is the stop's name, so it stays on its
  // control when the list changes under it.
  readonly property var stops: {
    var list = []
    for (var i = 0; i < rows.length; i++) list.push(rows[i].id)
    if (canClear) list.push("clear")
    list.push("switch", "picker")
    return list
  }
  property string cursor: ""
  property int cursorAt: -1
  // Which of the cursor row's controls the keyboard is on (h/l): -1 the row
  // itself, 0 Pin, 1 Delete.
  property int actionIndex: -1

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function cursorRow() {
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].id === cursor) return rows[i]
    }
    return null
  }

  function setCursor(stop) {
    cursor = stop
    actionIndex = -1
  }

  function moveCursor(dy) {
    var at = stops.indexOf(cursor)
    setCursor(stops[at < 0 ? 0 : (at + dy + stops.length) % stops.length])
  }

  function moveAction(dx) {
    if (!cursorRow()) return
    actionIndex = Math.max(-1, Math.min(1, actionIndex + dx))
  }

  // The panel closes first, so the keyboard is back in the window the entry
  // goes to.
  function paste(row) {
    if (!row || !service) return
    root.close()
    service.paste(row.id, false)
  }

  function togglePin(row) {
    if (row && service) service.togglePin(row.id)
  }

  function remove(row) {
    if (row && service) service.remove(row.id)
  }

  function clearAll() {
    if (service) service.clear()
  }

  function toggleRecording() {
    if (service) service.setRecording(!recording)
  }

  function openPicker() {
    root.close()
    if (bar && bar.shell) bar.shell.summon("karchy.clipboard", "{}")
  }

  function activateCursor() {
    if (cursor === "picker") { openPicker(); return }
    if (cursor === "clear") { clearAll(); return }
    if (cursor === "switch") { toggleRecording(); return }
    var row = cursorRow()
    if (!row) return
    if (actionIndex === 0) togglePin(row)
    else if (actionIndex === 1) remove(row)
    else paste(row)
  }

  onOpenedChanged: setCursor("")
  onCursorChanged: if (cursor !== "") cursorAt = stops.indexOf(cursor)
  // The cursor's entry is gone (deleted, cleared): the stop that took its
  // place gets the cursor, so Delete can be pressed again for the next one.
  onStopsChanged: {
    if (cursor === "") return
    var at = stops.indexOf(cursor)
    if (at < 0) cursor = stops[Math.max(0, Math.min(cursorAt, stops.length - 1))]
    else cursorAt = at
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Icons.glyph("clipboard")
    tooltipText: root.opened ? "" : I18n.t("clipboard.title")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openPicker()
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
      onActivateRequested: if (root.cursor !== "") root.activateCursor()
      onCloseRequested: root.close()
      onDeleteRequested: root.remove(root.cursorRow())
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "p") root.togglePin(root.cursorRow())
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        PanelHero {
          iconText: Icons.glyph("clipboard")
          title: I18n.t("clipboard.title")
          meta: !root.recording && root.history.length === 0 ? I18n.t("clipboard.historyOff")
            : root.history.length === 0 ? I18n.t("clipboard.empty")
            : I18n.tn("clipboard.kept", root.history.length).arg(I18n.formatNumber(root.history.length))
              + (root.pinnedCount > 0 ? " · " + I18n.tn("clipboard.pinnedCount", root.pinnedCount).arg(I18n.formatNumber(root.pinnedCount)) : "")
          fontFamily: root.bar.fontFamily
          trailingControl: Component {
            PanelActionButton {
              iconText: Icons.glyph("ui.history")
              tooltipText: I18n.t("clipboard.openHistory")
              foreground: root.panelText
              fontFamily: root.bar.fontFamily
              hasCursor: root.cursor === "picker"
              onClicked: root.openPicker()
              onHovered: function(h) { if (h) root.setCursor("picker") }
            }
          }
        }

        PanelSeparator { foreground: root.panelText }

        Repeater {
          model: [
            { title: I18n.t("clipboard.pinned"), rows: root.lists.pinned },
            { title: I18n.t("clipboard.recent"), rows: root.lists.recent }
          ]

          delegate: Column {
            id: section
            required property var modelData
            visible: modelData.rows.length > 0
            width: column.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              text: section.modelData.title
              foreground: root.panelText
              surface: root.panelSurface
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: section.modelData.rows
              delegate: ClipboardRow {
                required property var modelData
                width: section.width
                entry: modelData
                hasCursor: root.cursor === modelData.id
                // The pointer on a row hovers the row; only the keyboard
                // cursor marks which of its controls Enter would use.
                actionCursor: hasCursor && InputMode.keyboard ? root.actionIndex : -1
                foreground: root.panelText
                surface: root.panelSurface
                fontFamily: root.bar.fontFamily
                onPointerEntered: root.setCursor(modelData.id)
                onActionHovered: function(i) { root.cursor = modelData.id; root.actionIndex = i }
                onClicked: root.paste(modelData)
                onPinToggled: root.togglePin(modelData)
                onDeleteRequested: root.remove(modelData)
              }
            }
          }
        }

        Text {
          visible: root.lists.more > 0
          width: parent.width
          textFormat: Text.PlainText
          text: I18n.tn("clipboard.more", root.lists.more).arg(I18n.formatNumber(root.lists.more))
          color: Commons.Color.secondaryText(root.panelText, root.panelSurface)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }

        EmptyState {
          visible: root.history.length === 0
          width: parent.width
          iconName: "clipboard"
          title: root.recording ? I18n.t("clipboard.empty") : I18n.t("clipboard.historyOff")
          body: root.recording ? I18n.t("clipboard.emptyBody") : I18n.t("clipboard.historyOffBody")
          foreground: root.panelText
          surface: root.panelSurface
          fontFamily: root.bar.fontFamily
        }

        Button {
          visible: root.canClear
          leftAlign: true
          text: I18n.t("clipboard.clearAll")
          iconText: Icons.glyph("ui.delete")
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
          hasCursor: root.cursor === "clear"
          onClicked: root.clearAll()
          onHovered: function(h) { if (h) root.setCursor("clear") }
        }

        PanelSeparator { foreground: root.panelText }

        // Off: nothing more is recorded and what is not pinned is forgotten.
        Toggle {
          width: parent.width
          flat: true
          label: I18n.t("clipboard.keepHistory")
          description: I18n.t("clipboard.keepHistoryBody")
          checked: root.recording
          foreground: root.panelText
          fontFamily: root.bar.fontFamily
          hasCursor: root.cursor === "switch"
          onClicked: root.toggleRecording()
          onHovered: function(h) { if (h) root.setCursor("switch") }
        }
      }
    }
  }
}
