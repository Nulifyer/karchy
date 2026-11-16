-- What karchy starts with the session. Omarchy's autostart also runs its
-- first-run provisioning, herdr and post-boot hooks, which karchy drops; the
-- default theme is applied at install time instead (install/setup.sh).
require("default.hypr.startup-cursor")

hl.on("hyprland.start", function()
  if karchy_startup_cursor_pending then
    hl.env("XCURSOR_PATH", karchy_startup_cursor.path)
    hl.env("XCURSOR_THEME", karchy_startup_cursor.xcursor)
  end

  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  hl.exec_cmd("karchy-launch-shell")
  -- GTK's dark mode and icon theme live in gsettings, which needs this
  -- session's bus: the theme applied at install could not set them. Applying
  -- them at each login keeps GTK apps matching the current theme.
  hl.exec_cmd("karchy-theme-set-gnome")
  -- karchy's Thunar right-click actions, merged beside the user's own (D-36).
  hl.exec_cmd("karchy-thunar-actions")
  -- Once, at the first login: Downloads, Projects, Pictures and Videos in the
  -- file manager's sidebar, Desktop pointed at home, and starter templates.
  hl.exec_cmd("karchy-user-folders")
  -- Offer to mount internal data disks that have no mount yet (D-24).
  hl.exec_cmd("karchy-disks-check")
  -- Offer to re-enroll Secure Boot keys a firmware update cleared (D-31).
  hl.exec_cmd("karchy-secureboot check")
  -- Warn when the desktop draws on the processor (no usable GPU driver).
  hl.exec_cmd("karchy-hw-renderer check")
  hl.exec_cmd("karchy-powerprofiles-init")
  hl.exec_cmd(o.launch("karchy-hyprland-monitor-watch"))
  -- USB drives automount with a notification (D-24).
  hl.exec_cmd(o.launch("udiskie --automount --notify --no-tray"))
end)
