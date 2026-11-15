import QtQuick
import qs.Commons
import qs.Commons as Commons

// Asks before an action runs. Cancel is button 0, the action button 1; both
// are the kit's Button, so they look and behave like every other button.
//
// `destructive` (the default: most callers delete, remove or uninstall)
// draws the action as a destructive Button and opens with Cancel selected,
// so Enter on the request and Enter again here never destroys anything:
// reaching the action takes Tab, an arrow or the pointer. A non-destructive
// confirm draws the action as the primary Button and opens on it. The
// selection resets each time the dialog opens; callers don't set it.
Item {
  id: root

  property bool opened: false
  property bool destructive: true
  property string message: ""
  property string cancelText: Commons.I18n.t("common.cancel")
  property string confirmText: Commons.I18n.t("common.confirm")
  // Where the selection starts: Cancel for a destructive action, else the
  // action. A host can start every confirm on Cancel.
  property int defaultIndex: destructive ? 0 : 1
  // Hosts that don't route their keys through handleKey() set this, and the
  // dialog takes keyboard focus itself while it is open.
  property bool ownsKeys: false
  property int selectedIndex: defaultIndex
  property color background: Commons.Color.popups.background
  property color foreground: Commons.Color.popups.text
  property color scrim: Util.alpha(Commons.Color.background, 0.7)
  // Kept for hosts that pass their own surface colors; the card's border.
  property color selectedBackground: Util.alpha(Commons.Color.foreground, 0.08)
  property color selectedText: Commons.Color.popups.border
  property string fontFamily: Style.font.family
  property int cornerRadius: Style.radius.surface

  signal canceled()
  signal confirmed()

  onOpenedChanged: {
    if (!opened) return
    selectedIndex = defaultIndex
    if (ownsKeys) Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Item {
    id: keyCatcher
    Keys.onPressed: function(event) { if (root.handleKey(event)) event.accepted = true }
  }

  function handleKey(event) {
    if (!root.opened) return false
    InputMode.keyPressed()

    if (event.key === Qt.Key_Escape) {
      root.canceled()
      return true
    } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Right || event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab
        || event.text === "h" || event.text === "l") {
      root.selectedIndex = root.selectedIndex === 0 ? 1 : 0
      return true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
      if (root.selectedIndex === 0) root.canceled()
      else root.confirmed()
      return true
    }

    return false
  }

  visible: opened

  Rectangle {
    anchors.fill: parent
    color: root.scrim

    MouseArea { anchors.fill: parent; onClicked: root.canceled() }

    BorderSurface {
      id: card
      width: Math.min(parent.width - Style.space(32), Style.space(380))
      // Grows with the wrapped message so narrow hosts (like the menu card)
      // don't squeeze the text into the buttons.
      height: card.contentTopInset + card.contentBottomInset + messageText.implicitHeight + Style.spacing.huge + buttons.implicitHeight
      anchors.centerIn: parent
      color: root.background
      borderSpec: Border.flat(root.selectedText, Style.border.surface)
      padding: Style.spacing.huge
      radius: root.cornerRadius

      MouseArea { anchors.fill: parent; onClicked: {} }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.rightMargin: card.contentRightInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset

        Text {
          id: messageText
          textFormat: Text.PlainText
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          text: root.message
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.subtitle
          wrapMode: Text.WordWrap
        }

        Row {
          id: buttons
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          spacing: Style.spacing.controlGap

          Repeater {
            model: [root.cancelText, root.confirmText]

            Button {
              required property int index
              required property string modelData

              text: modelData
              width: Math.max(implicitWidth, Style.space(88))
              fontFamily: root.fontFamily
              foreground: root.foreground
              bordered: true
              variant: index === 0 ? "neutral" : (root.destructive ? "destructive" : "primary")
              // The selected button is where Enter goes.
              hasCursor: root.selectedIndex === index
              onHovered: function(on) { if (on) root.selectedIndex = index }
              onClicked: {
                if (index === 0) root.canceled()
                else root.confirmed()
              }
            }
          }
        }
      }
    }
  }
}
