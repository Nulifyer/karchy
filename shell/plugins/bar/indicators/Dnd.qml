import QtQuick
import qs.Commons
import qs.Ui

// Shows while Do Not Disturb is on, since nothing else on screen says the
// desktop is quiet. The switch is in the clock panel; clicking this turns it
// off.
BarIndicator {
  id: root

  readonly property var notifications: bar && bar.shell ? bar.shell.serviceFor("karchy.notifications") : null

  active: notifications ? notifications.doNotDisturb === true : false
  // Nothing to offer while off: the way in is the clock panel's switch.
  revealWhenInactive: false
  activeText: Icons.glyph("notify.silenced")
  inactiveText: Icons.glyph("notify.silenced")
  activeTooltipText: I18n.t("bar.doNotDisturbOn")

  onPressed: function() {
    if (root.notifications) root.notifications.setDoNotDisturb(false)
  }
}
