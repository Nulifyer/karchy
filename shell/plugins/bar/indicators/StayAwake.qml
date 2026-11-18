import QtQuick
import qs.Commons
import qs.Ui

// Shows while Stay Awake is on: the screen stays on and the computer doesn't
// lock or sleep by itself, which should not go unnoticed. The switch is in
// the power panel (the display panel on a computer without a battery);
// clicking this turns it off.
BarIndicator {
  id: root

  readonly property var idle: bar && bar.shell ? bar.shell.firstPartyServiceFor("karchy.idle") : null

  active: idle ? idle.stayAwake === true : false
  // Nothing to offer while off: the way in is the panel's switch.
  revealWhenInactive: false
  activeText: Icons.glyph("power.stay-awake")
  inactiveText: Icons.glyph("power.stay-awake")
  activeTooltipText: I18n.t("bar.stayAwakeOn")

  onPressed: function() {
    if (root.idle) root.idle.setIdleEnabled(true)
  }
}
