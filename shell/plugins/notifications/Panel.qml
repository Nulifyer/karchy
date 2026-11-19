import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "PanelModel.js" as Model

// Notifications in the bar (D-112): a bell, with a dot while notifications
// wait unseen, and a panel that lists the ones nobody answered. It behaves as
// Android's shade does, in karchy's panel style: ongoing ones first, then the
// rest, then a Silent section (PanelModel.js); several from one app fold into
// a group showing the newest; a notification keeps its buttons; ⋯ sets what
// its app's notifications do. Dismissed and answered ones are a click away
// under History for a day. Do Not Disturb is switched here.
//
// The notifications, their senders and Do Not Disturb belong to the
// notification service (Service.qml), which this reads and calls. Opening the
// panel marks everything seen.
//
// Keyboard: Up/Down (j/k) move through the switch, the notifications and the
// buttons under them; Left/Right (h/l) move through one notification's
// controls; Enter uses the one the cursor is on (on the notification itself
// it opens it, or unfolds its text when there is nothing to open); x or
// Delete dismisses; d switches Do Not Disturb; Tab goes to the next panel;
// Escape closes the menu, then the history, then the panel.
Panel {
  id: root
  moduleName: "karchy.notifications"
  ipcTarget: "karchy.notifications"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("karchy.notifications") : null
  readonly property var entries: service ? service.historyEntries : []
  readonly property int unseenCount: service ? service.unseenCount : 0
  readonly property bool doNotDisturb: service ? service.doNotDisturb === true : false
  readonly property int senderRevision: service ? service.refsRevision : 0

  // "list" (what waits) or "history" (what was dismissed or answered).
  property string view: "list"
  // Group ids opened, entry ids showing all their text, and the entry whose
  // app menu is open (and whether it is asking about turning the app off).
  property var openedGroups: ({})
  property var unfolded: ({})
  property string menuId: ""
  property bool confirmingOff: false
  // The entries that were new when the panel opened: they keep their mark
  // while it is open, though opening has already marked them seen.
  property var newIds: ({})
  // ...and how many of those are still listed.
  readonly property int newCount: {
    var n = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].waiting && newIds[Model.entryId(entries[i])] === true) n++
    return n
  }
  property double now: Date.now()
  readonly property double midnight: { var d = new Date(now); d.setHours(0, 0, 0, 0); return d.getTime() }

  readonly property var ongoing: {
    var out = {}
    if (!service) return out
    for (var i = 0; i < entries.length; i++)
      if (entries[i].waiting && service.isOngoing(entries[i], senderRevision)) out[Model.entryId(entries[i])] = true
    return out
  }
  readonly property var listRows: Model.rows(entries, ongoing, openedGroups)
  readonly property var historyRows: view === "history" ? Model.historyRows(entries) : []
  readonly property var rows: view === "history" ? historyRows : listRows
  readonly property int waitingCount: { var n = 0; for (var i = 0; i < entries.length; i++) if (entries[i].waiting) n++; return n }
  readonly property int clearableCount: waitingCount - Object.keys(ongoing).length

  // "dnd", "back", a row id, "clear", "history", "clearHistory", or "" before
  // the keyboard has moved; and the control within a notification.
  property string cursorId: ""
  property string cursorControl: "main"
  onCursorIdChanged: cursorControl = "main"

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Commons.Color.secondaryText(panelText, panelSurface)

  function toggleDoNotDisturb() {
    if (service) service.setDoNotDisturb(!doNotDisturb)
  }

  function cursorOrder() {
    var order = [view === "history" ? "back" : "dnd"]
    for (var i = 0; i < rows.length; i++) if (rows[i].kind !== "header") order.push(rows[i].id)
    if (view === "history") {
      if (rows.length > 0) order.push("clearHistory")
    } else {
      if (clearableCount > 0) order.push("clear")
      order.push("history")
    }
    return order
  }

  function moveCursor(step) {
    var order = cursorOrder()
    var at = order.indexOf(cursorId)
    cursorId = order[at < 0 ? (step > 0 ? 0 : order.length - 1) : (at + step + order.length) % order.length]
  }

  function rowById(id) {
    var at = Model.indexOfId(rows, id)
    return at >= 0 ? rows[at] : null
  }

  // The controls of the notification the cursor is on, as its row lists them.
  function cursorControls() {
    var at = Model.indexOfId(rows, cursorId)
    var built = panel.loadedContent
    var slot = at >= 0 && built ? built.rowRepeater.itemAt(at) : null
    return slot && slot.item && slot.item.controls ? slot.item.controls : ["main"]
  }

  function moveControl(step) {
    var row = rowById(cursorId)
    if (!row || row.kind !== "entry") return
    var list = cursorControls()
    var at = Math.max(0, list.indexOf(cursorControl))
    cursorControl = list[Math.max(0, Math.min(list.length - 1, at + step))]
  }

  function setUnfolded(id, on) {
    if (!!unfolded[id] === on) return
    var next = Object.assign({}, unfolded)
    if (on) next[id] = true
    else delete next[id]
    unfolded = next
  }

  function setGroupOpen(group, on) {
    var next = Object.assign({}, openedGroups)
    if (on) next[group] = true
    else delete next[group]
    openedGroups = next
  }

  function closeMenu() {
    menuId = ""
    confirmingOff = false
  }

  // The cursor goes to the row that takes this one's place.
  function leaveRow(id) {
    if (cursorId !== id) return
    var at = Model.indexOfId(rows, id)
    cursorId = (at >= 0 ? Model.neighbour(rows, at) : "") || "dnd"
  }

  function dismiss(id) {
    var row = rowById(id)
    if (!row || row.kind !== "entry" || view !== "list" || !service) return
    if (menuId === id) closeMenu()
    leaveRow(id)
    service.dismissEntry(row.entry.key, row.entry.closed_ts)
  }

  // One control of one notification, from the pointer or the keyboard.
  function trigger(id, control) {
    var row = rowById(id)
    if (!row || row.kind !== "entry" || !service) return
    var entry = row.entry
    if (control === "main") {
      if (view === "list" && service.entryOpens(entry, senderRevision)) {
        if (!root.ongoing[id]) leaveRow(id)
        close()
        service.openEntry(entry)
      } else setUnfolded(id, !unfolded[id])
    } else if (control === "unfold") setUnfolded(id, !unfolded[id])
    else if (control === "dismiss") dismiss(id)
    else if (control === "menu") {
      var opening = menuId !== id
      closeMenu()
      if (opening) menuId = id
    } else if (control.indexOf("deed:") === 0) {
      var deed = service.entryDeeds(entry, senderRevision)[Number(control.slice(5))]
      if (!root.ongoing[id]) leaveRow(id)
      service.runEntryDeed(entry, deed)
    } else if (control === "mode:off") {
      confirmingOff = true
      if (cursorId === id) cursorControl = "off:cancel"
    } else if (control.indexOf("mode:") === 0) {
      service.setAppMode(row.app, row.label, control.slice(5))
      closeMenu()
    } else if (control === "off:cancel") {
      confirmingOff = false
      if (cursorId === id) cursorControl = "menu"
    } else if (control === "off:confirm") {
      closeMenu()
      leaveRow(id)
      service.setAppMode(row.app, row.label, "off")
    } else if (control === "settings") {
      close()
      Quickshell.execDetached(["karchy-settings", "notifications", row.app])
    }
  }

  function showHistory(on) {
    closeMenu()
    view = on ? "history" : "list"
    cursorId = on ? "back" : "history"
  }

  function activateCursor() {
    if (cursorId === "dnd") { toggleDoNotDisturb(); return }
    if (cursorId === "clear") { if (service) service.clearWaiting(); cursorId = "dnd"; return }
    if (cursorId === "history") { showHistory(true); return }
    if (cursorId === "back") { showHistory(false); return }
    if (cursorId === "clearHistory") { if (service) service.clearHistory(); cursorId = "back"; return }
    var row = rowById(cursorId)
    if (!row) return
    if (row.kind === "fold") setGroupOpen(row.group, !row.open)
    else trigger(row.id, cursorControl)
  }

  function ageText(entry) {
    var age = Model.age(entry.ts, now, midnight)
    var locale = Qt.locale(I18n.formatLocale)
    if (age.kind === "now") return I18n.t("notifications.now")
    if (age.kind === "minutes") return I18n.t("notifications.minutesAgo").arg(I18n.formatNumber(age.value))
    if (age.kind === "time") return locale.toString(new Date(entry.ts * 1000), "HH:mm")
    if (age.kind === "yesterday") return I18n.t("notifications.yesterday")
    if (age.kind === "day") return locale.toString(new Date(entry.ts * 1000), "ddd")
    return ""
  }

  function markSeen() {
    if (service) service.markHistorySeen()
  }

  function closeOneLayer() {
    if (menuId !== "") closeMenu()
    else if (view === "history") showHistory(false)
    else close()
  }

  onOpenedChanged: {
    if (!opened) return
    now = Date.now()
    view = "list"
    cursorId = ""
    openedGroups = ({})
    unfolded = ({})
    closeMenu()
    // Entries past their day go before the list is drawn.
    var current = service ? service.currentHistory() : []
    var fresh = {}
    for (var i = 0; i < current.length; i++) {
      if (!current[i].waiting || current[i].seen !== false) continue
      fresh[Model.entryId(current[i])] = true
    }
    newIds = fresh
    markSeen()
  }

  // One that arrives while the panel is open is seen as it lands.
  onUnseenCountChanged: if (opened && unseenCount > 0) Qt.callLater(markSeen)

  Timer { interval: 30000; repeat: true; running: root.opened; onTriggered: root.now = Date.now() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Icons.glyph(root.doNotDisturb ? "notify.silenced" : "notify.bell")
    tooltipText: root.doNotDisturb ? I18n.t("bar.doNotDisturbOn")
      : root.unseenCount > 0
        ? I18n.tn("notifications.newCount", root.unseenCount).arg(I18n.formatNumber(root.unseenCount))
        : I18n.t("notifications.title")
    onPressed: function(b) {
      if (b === Qt.RightButton) root.toggleDoNotDisturb()
      else root.toggle()
    }

    // Notifications wait unseen in the panel. A dot is round in every theme,
    // square corners or not: a square read as a second icon beside the bell.
    Rectangle {
      visible: root.unseenCount > 0
      width: Style.space(5)
      height: width
      radius: width / 2
      antialiasing: true
      color: Commons.Color.accent
      // Centred just outside the icon's top-right corner. Centred on the
      // corner itself, its edge met the bell's shoulder by a pixel at 1× and
      // at 1.6×; a pixel further out there is background between them.
      readonly property real reach: Style.bar.iconSize * 0.45 + Style.space(1)
      x: Math.round(parent.width / 2 + reach - width / 2)
      y: Math.round(parent.height / 2 - reach - height / 2)
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

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
      property alias rowRepeater: rowRepeater
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        else if (dx !== 0) root.moveControl(dx)
      }
      onActivateRequested: if (root.cursorId !== "") root.activateCursor()
      onDeleteRequested: root.dismiss(root.cursorId)
      onCloseRequested: root.closeOneLayer()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { if (t === "d" || t === "D") root.toggleDoNotDisturb() }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.spacing.panelGap

        PanelHero {
          iconText: Icons.glyph(root.doNotDisturb ? "notify.silenced" : "notify.bell")
          title: I18n.t("notifications.title")
          // How many are listed, and how many of them came since the panel
          // was last open (the ones the bell's dot was for, marked in the
          // list): "3 waiting · 1 new", "2 new" when all are, "3 waiting".
          meta: {
            if (root.view === "history") return I18n.t("notifications.historyMeta")
            var fresh = root.newCount > 0
              ? I18n.tn("notifications.newShort", root.newCount).arg(I18n.formatNumber(root.newCount)) : ""
            if (root.waitingCount <= root.newCount) return fresh
            var waiting = I18n.tn("notifications.waitingShort", root.waitingCount).arg(I18n.formatNumber(root.waitingCount))
            return fresh !== "" ? waiting + " · " + fresh : waiting
          }
          metaColor: root.view === "history" || root.newCount === 0 ? dim : Commons.Color.accent
          fontFamily: root.fontFamily
        }

        Toggle {
          flat: true
          visible: root.view === "list"
          width: parent.width
          label: I18n.t("notifications.doNotDisturb")
          // What the choice costs, said only while it applies.
          description: root.doNotDisturb ? I18n.t("notifications.doNotDisturbOn") : ""
          checked: root.doNotDisturb
          hasCursor: root.cursorId === "dnd"
          foreground: root.panelText
          fontFamily: root.fontFamily
          onClicked: root.toggleDoNotDisturb()
          onHovered: function(h) { if (h) root.cursorId = "dnd" }
        }

        Button {
          visible: root.view === "history"
          leftAlign: true
          text: I18n.t("notifications.back")
          iconText: Icons.glyph(I18n.rightToLeft ? "ui.chevron.right" : "ui.chevron.left")
          foreground: root.panelText
          fontFamily: root.fontFamily
          hasCursor: root.cursorId === "back"
          onClicked: root.showHistory(false)
          onHovered: function(h) { if (h) root.cursorId = "back" }
        }

        PanelSeparator { foreground: root.panelText }

        EmptyState {
          visible: root.rows.length === 0
          width: parent.width
          iconName: root.view === "history" ? "ui.history" : "notify.bell"
          title: I18n.t(root.view === "history" ? "notifications.historyEmpty" : "notifications.empty")
          body: root.view === "history" ? I18n.t("notifications.historyEmptyHint") : ""
          foreground: root.panelText
          surface: root.panelSurface
          fontFamily: root.fontFamily
        }

        Flickable {
          id: list
          visible: root.rows.length > 0
          width: parent.width
          // As tall as the screen leaves room for, under the switch and over
          // the buttons, so those never scroll away.
          height: Math.min(contentHeight, Math.max(Style.space(200),
            Math.min(Style.space(560), panel.availableCardHeight - Style.space(280))))
          contentWidth: width
          contentHeight: listColumn.implicitHeight
          clip: true
          boundsBehavior: Flickable.StopAtBounds
          interactive: contentHeight > height

          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          // The keyboard's row stays on screen; the pointer's already is.
          function reveal(item) {
            if (!item || !InputMode.keyboard) return
            var top = item.y, bottom = item.y + item.height
            if (top < contentY) contentY = Math.max(0, top)
            else if (bottom > contentY + height) contentY = Math.max(0, Math.min(contentHeight - height, bottom - height))
          }

          Column {
            id: listColumn
            width: list.width
            spacing: Style.spacing.sm

            Repeater {
              id: rowRepeater
              model: root.rows
              delegate: Loader {
                id: slot
                required property var modelData
                required property int index
                readonly property bool hasCursor: root.cursorId === modelData.id
                width: listColumn.width
                sourceComponent: modelData.kind === "header" ? headerRow
                  : modelData.kind === "fold" ? foldRow : entryRow
                onHasCursorChanged: if (hasCursor) list.reveal(slot)
                onHeightChanged: if (hasCursor) list.reveal(slot)

                Component {
                  id: headerRow
                  PanelSectionHeader {
                    text: I18n.t("notifications.section." + slot.modelData.section)
                    topPadding: slot.index > 0 ? Style.spacing.lg : Math.ceil(fontSize * 0.15)
                    foreground: root.panelText
                    surface: root.panelSurface
                    fontFamily: root.fontFamily
                  }
                }

                Component {
                  id: foldRow
                  Button {
                    readonly property string who: slot.modelData.system ? I18n.t("notifications.system") : slot.modelData.label
                    leftAlign: true
                    text: slot.modelData.open ? I18n.t("notifications.showLess")
                      : I18n.tn("notifications.moreFrom", slot.modelData.count).arg(I18n.formatNumber(slot.modelData.count)).arg(who)
                    iconText: Icons.glyph(slot.modelData.open ? "ui.chevron.up" : "ui.chevron.down")
                    foreground: root.panelText
                    fontFamily: root.fontFamily
                    hasCursor: slot.hasCursor
                    onClicked: root.setGroupOpen(slot.modelData.group, !slot.modelData.open)
                    onHovered: function(h) { if (h) root.cursorId = slot.modelData.id }
                  }
                }

                Component {
                  id: entryRow
                  NotificationRow {
                    readonly property string entryId: slot.modelData.id
                    entry: slot.modelData.entry
                    label: slot.modelData.label
                    system: slot.modelData.system
                    readOnly: root.view === "history"
                    deeds: readOnly || !root.service ? [] : root.service.entryDeeds(entry, root.senderRevision)
                    opens: !readOnly && root.opened && !!root.service && root.service.entryOpens(entry, root.senderRevision)
                    isNew: !readOnly && root.newIds[entryId] === true
                    unfolded: root.unfolded[entryId] === true
                    menuOpen: root.menuId === entryId
                    confirmingOff: menuOpen && root.confirmingOff
                    mode: root.service ? root.service.appRules[slot.modelData.app] || "allow" : "allow"
                    ageText: root.ageText(entry)
                    hasCursor: slot.hasCursor
                    // The pointer on a row hovers the row; only the keyboard
                    // cursor marks which of its controls Enter would use.
                    actionCursor: slot.hasCursor && InputMode.keyboard ? root.cursorControl : ""
                    foreground: root.panelText
                    surface: root.panelSurface
                    fontFamily: root.fontFamily
                    onPointerEntered: root.cursorId = entryId
                    onControlHovered: function(control) { root.cursorId = entryId; root.cursorControl = control }
                    onTriggered: function(control) { root.trigger(entryId, control) }
                  }
                }
              }
            }
          }
        }

        PanelSeparator {
          visible: root.rows.length > 0
          foreground: root.panelText
        }

        // What waits is cleared; the ongoing ones stay. History is the quiet
        // way to what was dismissed.
        Item {
          visible: root.view === "list"
          width: parent.width
          height: Math.max(clearButton.implicitHeight, historyButton.implicitHeight)

          Button {
            id: clearButton
            visible: root.clearableCount > 0
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("notifications.clearAll")
            foreground: root.panelText
            fontFamily: root.fontFamily
            bordered: true
            hasCursor: root.cursorId === "clear"
            onClicked: { if (root.service) root.service.clearWaiting() }
            onHovered: function(h) { if (h) root.cursorId = "clear" }
          }

          Button {
            id: historyButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.t("notifications.history")
            iconText: Icons.glyph("ui.history")
            foreground: root.dim
            fontFamily: root.fontFamily
            hasCursor: root.cursorId === "history"
            onClicked: root.showHistory(true)
            onHovered: function(h) { if (h) root.cursorId = "history" }
          }
        }

        Button {
          visible: root.view === "history" && root.rows.length > 0
          text: I18n.t("notifications.clearHistory")
          foreground: root.panelText
          fontFamily: root.fontFamily
          bordered: true
          hasCursor: root.cursorId === "clearHistory"
          onClicked: { if (root.service) root.service.clearHistory() }
          onHovered: function(h) { if (h) root.cursorId = "clearHistory" }
        }
      }
    }
  }
}
