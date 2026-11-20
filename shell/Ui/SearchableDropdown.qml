import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons

// Searchable single-select dropdown. Same trigger shape as Dropdown, but
// the popup leads with an embedded TextField that filters the option
// list in real time. Use for pickers with enough options that scanning
// is friction.
//
// Filtering is case-insensitive substring against each option's label.
// Options can be string[] or [{ value, label, description? }] — the same
// shape Dropdown accepts. The filter clears whenever the popup closes.
//
// For rows that show more than a label (a font in its own face, FontPicker):
// `rowDelegate` draws a row's content from `option`, `current` (the row under
// the cursor) and `chosen` (the option that is the value); `popupWidth` makes
// the popup wider than the trigger, kept inside the window; `popupRows` is
// how many rows show before the list scrolls. An option's `group` puts a
// heading over the first row of each run of options that share it.
//
// Keyboard: Tab to focus the trigger, Enter/Space opens (search focused
// immediately). The list opens at the present choice, with the cursor on
// it. Down arrow from the search goes to it, or to the first match once
// something is typed; Up from the first row returns to the search. Enter
// selects, Esc closes (and clears the filter).
//
// Where the window has too little room under the trigger the popup opens
// over it, mirrored: the search stays next to the trigger, the first match
// sits right above the search and the rest follow upward, so Up enters the
// list and Down comes back. Where neither side fits the whole popup it
// takes the larger side and the list scrolls. Dropdown places its popup
// the same way.
Item {
  id: root

  property string label: ""
  property string value: ""
  property var options: []
  property string placeholderText: Commons.I18n.t("common.search")
  property string emptyText: Commons.I18n.t("common.noMatches")
  property string triggerLabel: ""

  property color foreground: Commons.Color.popups.text
  property color background: Commons.Color.popups.background
  property color popupBorder: Commons.Color.popups.border
  property color accent: Commons.Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Commons.Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property int popupMinHeight: Style.spacing.searchablePopupMinHeight
  property bool showLabel: true
  property Component rowDelegate: null
  // 0: as wide as the trigger.
  property real popupWidth: 0
  property int popupRows: 6

  // Panel-cursor flag. When true, the trigger renders the shared
  // hover-cursor state. Active Qt focus defaults to the same visuals.
  // Emits `hovered(bool)` on pointer enter/leave so the panel can keep
  // its cursor state in sync with the mouse.
  property bool hasCursor: false

  // popupOpen + open()/close()/toggle() let a parent panel know when the
  // dropdown owns keys (search field + result list are active) and
  // suspend its own keyCatcher so typing into the filter doesn't drive
  // the panel cursor.
  readonly property bool popupOpen: popup.opened
  // Puts the keyboard on the trigger, as Tab would (a page opened at it).
  function takeFocus() { trigger.forceActiveFocus(Qt.TabFocusReason) }
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)
  signal hovered(bool isHovered)

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }
  function optionDescription(o) {
    return (o && typeof o === "object" && o.description) ? String(o.description) : ""
  }
  function optionGroup(o) {
    return (o && typeof o === "object" && o.group) ? String(o.group) : ""
  }
  function currentLabel() {
    for (var i = 0; i < options.length; i++) {
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    }
    return value
  }

  property var filtered: options
  function recomputeFiltered() {
    var q = searchField.text.toLowerCase()
    if (!q) { filtered = options; return }
    var out = []
    for (var i = 0; i < options.length; i++) {
      var lbl = optionLabel(options[i]).toLowerCase()
      var desc = optionDescription(options[i]).toLowerCase()
      if (lbl.indexOf(q) !== -1 || desc.indexOf(q) !== -1) out.push(options[i])
    }
    filtered = out
  }

  onOptionsChanged: recomputeFiltered()

  implicitWidth: Style.spacing.searchableDropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Commons.Color.secondaryText(root.foreground, root.background)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.radius.control

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor
      readonly property var _borderSpec: Border.controlSpec(trigger._focused || trigger._hot ? "hover-cursor" : "normal", root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec

      activeFocusOnTab: true

      FocusRing { shown: trigger._focused || root.hasCursor }

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down) {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        text: root.currentLabel() || root.triggerLabel || root.placeholderText
        color: (root.currentLabel() || root.triggerLabel) ? root.foreground : Commons.Color.secondaryText(root.foreground, root.background)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: Icons.glyph("ui.chevron.down")
        color: Commons.Color.secondaryText(root.foreground, root.background)
        font.family: Icons.family
        font.pixelSize: Style.font.iconSmall
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        // CloseOnPressOutsideParent treats a press on the trigger as inside,
        // so the popup is still open here and a second click collapses it
        // instead of reopening.
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      QQC.Popup {
        id: popup

        // A popup is drawn inside its window and cut off at the window's
        // edge, so where it opens is decided each time it opens, from the
        // room the window then has on each side of the trigger.
        property bool above: false
        // The most height the chosen side has room for; 0 before the first open.
        property real room: 0
        // How far left of the trigger a wider popup starts, to stay in the window.
        property real shift: 0
        readonly property real gap: Style.spacing.xxs
        // The tallest the popup gets with every option listed, which is what
        // has to fit: the list grows back when the filter is cleared.
        readonly property real fullHeight:
          Math.max(root.popupMinHeight,
                   Math.min(root.options.length * root.popupRowHeight + Math.max(0, root.options.length - 1) * Style.spacing.labelGap,
                            root.popupRowHeight * root.popupRows + (root.popupRows - 1) * Style.spacing.labelGap) + Style.space(50))
        // The search and one row.
        readonly property real leastHeight: searchHeader.height + 1 + root.popupRowHeight + topPadding + bottomPadding

        function place() {
          var win = trigger.Window.window
          if (!win) {
            popup.above = false
            popup.room = 0
            popup.shift = 0
            return
          }
          // The window's top and bottom edges, seen from the trigger.
          var windowTop = trigger.mapFromItem(null, 0, 0).y
          var windowBottom = trigger.mapFromItem(null, 0, win.height).y
          var edge = Style.spacing.sm
          var below = windowBottom - trigger.height - popup.gap - edge
          var over = -windowTop - popup.gap - edge
          popup.above = popup.fullHeight > below && over > below
          popup.room = Math.max(popup.leastHeight, popup.above ? over : below)
          // A popup wider than the trigger starts at the trigger's left edge
          // and moves left only as far as the window's right edge asks.
          var windowLeft = trigger.mapFromItem(null, 0, 0).x
          var windowRight = trigger.mapFromItem(null, win.width, 0).x
          popup.shift = Math.max(windowLeft + edge, Math.min(0, windowRight - edge - popup.width))
        }

        x: shift
        y: above ? -height - gap : trigger.height + gap
        width: Math.max(trigger.width, root.popupWidth)
        closePolicy: QQC.Popup.CloseOnPressOutsideParent | QQC.Popup.CloseOnEscape
        readonly property real wantedHeight:
          Math.max(root.popupMinHeight,
                   Math.min(resultList.contentHeight + Style.space(50),
                            root.popupRowHeight * root.popupRows + (root.popupRows - 1) * Style.spacing.labelGap + Style.space(50)))
        implicitHeight: room > 0 ? Math.min(wantedHeight, room) : wantedHeight
        onAboutToShow: place()
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        background: BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.radius.surface
        }

        onOpened: {
          searchField.text = ""
          root.recomputeFiltered()
          resultList.showChosen()
          Qt.callLater(function() { searchField.forceActiveFocus() })
        }
        onClosed: searchField.text = ""

        // The search is on the trigger's side: at the top of a popup that
        // opens under the trigger, at the bottom of one that opens over it.
        contentItem: Item {
          Item {
            id: searchHeader
            y: popup.above ? parent.height - height : 0
            width: parent.width
            height: root.popupRowHeight + Style.spacing.controlPaddingX

            TextField {
              id: searchField
              anchors.fill: parent
              anchors.margins: Style.spacing.md
              placeholderText: root.placeholderText
              foreground: root.foreground
              accent: root.accent
              font.family: root.fontFamily
              font.pixelSize: Style.font.body

              onTextChanged: {
                root.recomputeFiltered()
                if (resultList.count > 0) resultList.currentIndex = 0
              }

              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (event.key === (popup.above ? Qt.Key_Up : Qt.Key_Down)) {
                  // Toward the list, which is over the search in a popup
                  // that opened upward: the first match, or with nothing
                  // typed the row the list opened at.
                  if (resultList.count > 0) {
                    if (searchField.text !== "" || resultList.currentIndex < 0) resultList.currentIndex = 0
                    resultList.forceActiveFocus()
                  }
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  // Enter takes the first match. With nothing typed the row
                  // under the cursor is the present choice: nothing changes.
                  if (resultList.count > 0) {
                    if (searchField.text !== "" || resultList.currentIndex < 0) resultList.currentIndex = 0
                    if (root.optionValue(root.filtered[resultList.currentIndex]) === root.value) popup.close()
                    else resultList.selectCurrent()
                  }
                  event.accepted = true
                }
              }
            }
          }

          Rectangle {
            y: popup.above ? searchHeader.y - height : searchHeader.height
            width: parent.width
            height: 1
            color: Util.alpha(root.foreground, 0.10)
          }

          Item {
            y: popup.above ? 0 : searchHeader.height + 1
            width: parent.width
            height: parent.height - searchHeader.height - 1

            Text {
              textFormat: Text.PlainText
              anchors.centerIn: parent
              visible: resultList.count === 0
              text: root.emptyText
              color: Commons.Color.secondaryText(root.foreground, root.background)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ListView {
              id: resultList
              anchors.fill: parent
              spacing: Style.spacing.labelGap
              clip: true
              boundsBehavior: Flickable.StopAtBounds
              model: root.filtered
              currentIndex: -1
              keyNavigationEnabled: false
              // The first match is always the one next to the search.
              verticalLayoutDirection: popup.above ? ListView.BottomToTop : ListView.TopToBottom

              // A list opens at the present choice, in view with the
              // cursor on it: a long list (the timezones) opened at its
              // first row, far from the one in use. Without a choice among
              // the options, the first row.
              function showChosen() {
                var at = -1
                for (var i = 0; i < root.filtered.length && at < 0; i++)
                  if (root.optionValue(root.filtered[i]) === root.value) at = i
                currentIndex = at >= 0 ? at : (count > 0 ? 0 : -1)
                if (at >= 0) positionViewAtIndex(at, ListView.Center)
                else positionViewAtBeginning()
              }

              function selectCurrent() {
                if (currentIndex < 0 || currentIndex >= root.filtered.length) return
                var v = root.optionValue(root.filtered[currentIndex])
                root.value = v
                root.changed(v)
                popup.close()
              }

              Keys.priority: Keys.BeforeItem
              Keys.onPressed: function(event) {
                // Away from the search is the next match, toward it the
                // previous one: Down and Up, or the reverse in a popup that
                // opened upward.
                var down = event.key === Qt.Key_Down || event.text === "j"
                var up = event.key === Qt.Key_Up || event.text === "k"
                var next = popup.above ? up : down
                var previous = popup.above ? down : up
                if (event.key === Qt.Key_Escape) {
                  popup.close(); event.accepted = true
                } else if (next) {
                  if (resultList.currentIndex >= resultList.count - 1) {
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex + 1
                  event.accepted = true
                } else if (previous) {
                  if (resultList.currentIndex <= 0) {
                    searchField.forceActiveFocus()
                    event.accepted = true; return
                  }
                  resultList.currentIndex = resultList.currentIndex - 1
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  resultList.selectCurrent(); event.accepted = true
                }
              }

              delegate: Item {
                id: optionItem
                required property var modelData
                required property int index
                readonly property bool current: index === resultList.currentIndex
                // The first row of a group carries the group's heading.
                readonly property string group: root.optionGroup(modelData)
                readonly property bool startsGroup: group !== ""
                  && (index === 0 || root.optionGroup(root.filtered[index - 1]) !== group)
                width: resultList.width
                height: (startsGroup ? groupHeading.height : 0) + optionRow.height

                Text {
                  id: groupHeading
                  textFormat: Text.PlainText
                  visible: optionItem.startsGroup
                  // In a list that grows upward the heading still reads above its rows.
                  y: 0
                  x: Style.spacing.controlPaddingX
                  height: implicitHeight + Style.spacing.lg + Style.spacing.sm
                  verticalAlignment: Text.AlignBottom
                  bottomPadding: Style.spacing.sm
                  text: optionItem.group.toUpperCase()
                  color: Commons.Color.secondaryText(root.foreground, root.background)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: Style.font.labelSpacing
                }

                Rectangle {
                  id: optionRow
                  y: optionItem.startsGroup ? groupHeading.height : 0
                  width: parent.width
                  height: Math.max(root.popupRowHeight,
                                   (customRow.item ? customRow.item.implicitHeight : rowContent.implicitHeight) + Style.spacing.rowPaddingX)
                  radius: Style.radius.control
                  color: optionItem.current
                    ? Style.hoverFillFor(root.foreground, root.accent)
                    : "transparent"

                  FocusRing { shown: optionItem.current; keyboardOnly: false }

                  Loader {
                    id: customRow
                    active: root.rowDelegate !== null
                    sourceComponent: root.rowDelegate
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.controlPaddingX
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    readonly property var option: optionItem.modelData
                    readonly property bool current: optionItem.current
                    readonly property bool chosen: root.optionValue(optionItem.modelData) === root.value
                  }

                  Column {
                    id: rowContent
                    visible: root.rowDelegate === null
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: Style.spacing.controlPaddingX
                    anchors.rightMargin: Style.spacing.controlPaddingX
                    spacing: Style.spacing.xxs

                    Text {
                      textFormat: Text.PlainText
                      text: root.optionLabel(optionItem.modelData)
                      color: optionItem.current ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                      elide: Text.ElideRight
                      width: parent.width
                    }
                    Text {
                      textFormat: Text.PlainText
                      visible: text !== ""
                      text: root.optionDescription(optionItem.modelData)
                      color: Commons.Color.secondaryText(root.foreground, root.background)
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: parent.width
                    }
                  }

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPositionChanged: resultList.currentIndex = optionItem.index
                    onClicked: resultList.selectCurrent()
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
