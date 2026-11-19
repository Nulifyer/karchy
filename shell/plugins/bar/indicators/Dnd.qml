import QtQuick
import qs.Commons
import qs.Ui

// Shows while Do Not Disturb is on, on a bar without the notifications bell:
// the bell says it itself (its glyph changes), and one state gets one sign.
// A click turns Do Not Disturb off, since this bar has no panel with the
// switch.
BarIndicator {
  id: root

  readonly property var notifications: bar && bar.shell ? bar.shell.serviceFor("karchy.notifications") : null
  readonly property bool bellInBar: bar && typeof bar.moduleWidgets === "function"
    ? bar.moduleWidgets("karchy.notifications").length > 0 : false

  active: notifications ? notifications.doNotDisturb === true && !bellInBar : false
  // Nothing to offer while off: the way in is the notifications panel.
  revealWhenInactive: false
  activeText: Icons.glyph("notify.silenced")
  inactiveText: Icons.glyph("notify.silenced")
  activeTooltipText: I18n.t("bar.doNotDisturbOnTurnOff")

  onPressed: function() {
    if (root.notifications) root.notifications.setDoNotDisturb(false)
  }
}
