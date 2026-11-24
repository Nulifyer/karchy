import QtQuick
import qs.Commons
import qs.Commons as Commons

// A window's sidebar when the window is narrow (a tile beside other windows,
// under Style.spacing.windowNarrow): one dropdown across the top that lists
// what the sidebar listed, in the same order, with the same icons, and shows
// the one that is open. Settings, Quick install, Virtual machines and
// Containers all turn their sidebar into this; none keeps a sidebar of its
// own design at that width.
//
//   SidebarSwitcher {
//     visible: root.narrow
//     Layout.fillWidth: true
//     value: root.section
//     options: root.sections.map(function(s) {
//       return { value: s.id, label: s.label, icon: Icons.glyph(s.iconName) }
//     })
//     onChanged: function(value) { root.section = value }
//   }
//
// An option's `detail` is what the sidebar row showed beside the name: a
// count, a state ("Running"). `note` is a line under the dropdown for what
// the sidebar said under the window's name and still has to be said (which
// engine the containers are from, that the installed apps couldn't be read).
//
// Keyboard: one Tab stop. Enter, Space or Down opens the list; Up/Down or
// j/k move in it, Enter chooses, Escape closes it. `takeFocus()` puts the
// keyboard on it, as a window does where it would have started in its
// sidebar.
Rectangle {
  id: root

  property alias value: dropdown.value
  property alias options: dropdown.options
  property string note: ""
  readonly property alias popupOpen: dropdown.popupOpen
  signal changed(string value)
  // Tab or Shift+Tab on it, for a window that keeps a Tab order of its own
  // (it accepts the event); otherwise the keyboard goes on to the page.
  signal tabbed(var event)

  function takeFocus() { dropdown.takeFocus() }

  implicitHeight: dropdown.implicitHeight + Style.spacing.lg * 2
    + (noteText.visible ? noteText.implicitHeight + Style.spacing.sm : 0)
  // The sidebar's own tint: it is the same list, folded up.
  color: Util.alpha(Commons.Color.foreground, 0.04)

  Dropdown {
    id: dropdown
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: Style.spacing.lg
    anchors.leftMargin: Style.spacing.panelPadding
    anchors.rightMargin: Style.spacing.panelPadding
    showLabel: false
    // More rows than a form's dropdown shows: this list is the window's map.
    maxRows: 12
    onChanged: function(value) { root.changed(value) }
    onTabbed: function(event) { root.tabbed(event) }
  }

  Text {
    id: noteText
    visible: root.note !== ""
    anchors.left: dropdown.left
    anchors.right: dropdown.right
    anchors.top: dropdown.bottom
    anchors.topMargin: Style.spacing.sm
    textFormat: Text.PlainText
    text: root.note
    wrapMode: Text.Wrap
    color: Commons.Color.textSecondary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
}
