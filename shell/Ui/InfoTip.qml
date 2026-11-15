import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons

// An (i) button beside a control or label, for an optional explanation of it
// ("Auto docks the bar while a window is maximized."). It opens on click,
// Enter or Space, not on hover alone, and closes the same way or on Escape.
// For a page-wide explanation use PageHeader's `explanation` instead. Never
// put errors, warnings, or what an action will do behind it.
//
//   InfoTip { subject: "Bar"; text: "Auto docks the bar while a window is maximized." }
PanelActionButton {
  id: root

  property string text: ""
  // What it explains, for its accessible name ("About Bar").
  property string subject: ""
  property bool open: false

  focusable: true
  iconText: Icons.glyph("ui.explain")
  tooltipText: ""
  foreground: open ? Commons.Color.focus : Commons.Color.textSecondary
  hoverColor: Commons.Color.foreground

  Accessible.name: subject !== "" ? "About " + subject : "More information"
  Accessible.description: text

  onClicked: open = !open
  onActiveFocusChanged: if (!activeFocus) open = false
  Keys.onEscapePressed: function(event) {
    if (!open) { event.accepted = false; return }
    open = false
  }

  PanelToolTip {
    visible: root.open && root.text !== ""
    text: root.text
    delay: 0
    timeout: -1
    // Shown and hidden by `open` alone; the button handles Escape.
    closePolicy: Popup.NoAutoClose
    width: Math.min(implicitWidth, Style.space(320))
  }
}
