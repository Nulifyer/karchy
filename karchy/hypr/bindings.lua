-- karchy's keybindings: exactly docs/keybindings.md (D-17). Media, volume,
-- brightness and the universal clipboard come from Omarchy's
-- default/hypr/bindings/{media,clipboard}.lua, loaded by karchy/hypr/init.lua.
-- Add personal bindings in ~/.config/hypr/bindings.lua, not here.

-- Windows
o.bind("ALT + F4", "Close window", hl.dsp.window.close())
o.bind("SUPER + UP", "Maximize window", hl.dsp.window.fullscreen({ mode = "maximized", action = "set" }))
o.bind("SUPER + DOWN", "Restore window, or minimize it", "karchy-hyprland-window-minimize --down")
o.bind("SUPER + LEFT", "Focus on left window", hl.dsp.focus({ direction = "l" }))
o.bind("SUPER + RIGHT", "Focus on right window", hl.dsp.focus({ direction = "r" }))
o.bind("SUPER + SHIFT + LEFT", "Swap window to the left", hl.dsp.window.swap({ direction = "l" }))
o.bind("SUPER + SHIFT + RIGHT", "Swap window to the right", hl.dsp.window.swap({ direction = "r" }))
o.bind("SUPER + SHIFT + UP", "Swap window up", hl.dsp.window.swap({ direction = "u" }))
o.bind("SUPER + SHIFT + DOWN", "Swap window down", hl.dsp.window.swap({ direction = "d" }))
-- A tiled window floats at a comfortable size in the middle of the screen,
-- as windows on a floating workspace open.
local function toggle_floating()
  local window = hl.get_active_window()
  if not window then
    return
  end
  local tiled = not window.floating
  hl.dispatch(hl.dsp.window.float({ action = "toggle" }))
  if tiled then
    require("default.hypr.workspace-modes").place(window)
  end
end
o.bind_expressions[toggle_floating] = 'hl.dsp.window.float({ action = "toggle" })'
o.bind("SUPER + T", "Toggle window floating/tiling", toggle_floating)
o.bind("SUPER + M", "Minimize all windows", "karchy-hyprland-window-minimize --all")
o.bind("SUPER + SHIFT + M", "Restore minimized windows", "karchy-hyprland-window-restore --all")
o.bind("SUPER + F", "Full screen", hl.dsp.window.fullscreen({ mode = "fullscreen" }))
o.bind("SUPER + code:20", "Make window narrower", hl.dsp.window.resize({ x = -100, y = 0, relative = true }))
o.bind("SUPER + code:21", "Make window wider", hl.dsp.window.resize({ x = 100, y = 0, relative = true }))
o.bind("SUPER + SHIFT + code:20", "Make window shorter", hl.dsp.window.resize({ x = 0, y = -100, relative = true }))
o.bind("SUPER + SHIFT + code:21", "Make window taller", hl.dsp.window.resize({ x = 0, y = 100, relative = true }))
o.bind("SUPER + mouse:272", "Move window", hl.dsp.window.drag(), { mouse = true })
o.bind("SUPER + mouse:273", "Resize window", hl.dsp.window.resize(), { mouse = true })
-- Each Alt+Tab chord carries two binds, as in Omarchy: focus, then raise.
o.bind("ALT + TAB", "Focus on next window", hl.dsp.window.cycle_next())
o.bind("ALT + TAB", "Reveal active window on top", hl.dsp.window.bring_to_top())
o.bind("ALT + SHIFT + TAB", "Focus on previous window", hl.dsp.window.cycle_next({ next = false }))
o.bind("ALT + SHIFT + TAB", "Reveal active window on top", hl.dsp.window.alter_zorder({ mode = "bottom" }))

-- Workspaces and monitors (per-monitor blocks of 10, D-13 in the audit)
for workspace = 1, 10 do
  local key = "code:" .. tostring(workspace + 9)
  o.bind("SUPER + " .. key, "Switch to workspace " .. workspace, o.workspaces.focus(workspace))
  o.bind("SUPER + SHIFT + " .. key, "Move window to workspace " .. workspace, o.workspaces.move_window(workspace))
end
o.bind("SUPER + TAB", "Next workspace", hl.dsp.focus({ workspace = "m+1" }))
o.bind("SUPER + SHIFT + TAB", "Previous workspace", hl.dsp.focus({ workspace = "m-1" }))
o.bind("SUPER + mouse_down", "Scroll active workspace forward", hl.dsp.focus({ workspace = "m+1" }))
o.bind("SUPER + mouse_up", "Scroll active workspace backward", hl.dsp.focus({ workspace = "m-1" }))
o.bind("SUPER + grave", "Toggle drop-down terminal", hl.dsp.workspace.toggle_special("qconsole"))
o.bind("SUPER + SHIFT + CTRL + LEFT", "Move window to left monitor", o.workspaces.move_window_to_monitor("l"))
o.bind("SUPER + SHIFT + CTRL + RIGHT", "Move window to right monitor", o.workspaces.move_window_to_monitor("r"))
o.bind("SUPER + SHIFT + CTRL + UP", "Move window to up monitor", o.workspaces.move_window_to_monitor("u"))
o.bind("SUPER + SHIFT + CTRL + DOWN", "Move window to down monitor", o.workspaces.move_window_to_monitor("d"))
o.bind("CTRL + ALT + TAB", "Focus on next monitor", hl.dsp.focus({ monitor = "+1" }))

-- Shell and system
o.bind("SUPER + SPACE", "Menu", { menu = "root" })
o.bind("SUPER + L", "Lock", "karchy-system-lock")
o.bind("SUPER + ESCAPE", "Power menu", { menu = "system" })
o.bind("XF86PowerOff", "Power menu", { menu = "system" }, { locked = true })
-- The kernel turns the radios off or on for this key; karchy-airplane shows
-- the result, and toggles only on a kernel that doesn't (D-68).
o.bind("XF86RFKill", "Airplane mode", "karchy-airplane key", { locked = true })
o.bind("SUPER + K", "Keybindings", "karchy-menu-keybindings")
o.bind("SUPER + CTRL + R", "Set reminder", "karchy-reminder -i")
o.bind("SUPER + comma", "Dismiss last notification", { ipc = "notifications.dismissOne" })
o.bind("SUPER + SHIFT + comma", "Dismiss all notifications", { ipc = "notifications.dismissAll" })
o.bind("SUPER + SHIFT + ALT + comma", "Open notification history", { ipc = "notifications.showHistory" })
o.bind("CTRL + SHIFT + ESCAPE", "Task manager", "karchy-launch-or-focus io.missioncenter.MissionCenter missioncenter")

-- Apps
o.bind("SUPER + RETURN", "Terminal", o.launch_terminal())
o.bind("SUPER + E", "File manager", "karchy-launch-files")

-- Capture (Omasnap, D-34)
o.bind("PRINT", "Screenshot", "karchy-capture-screenshot")
o.bind("SUPER + SHIFT + S", "Screenshot region", "karchy-capture-screenshot region")
o.bind("ALT + PRINT", "Screen recording", "karchy-capture-screenrecording --stop-recording || karchy-capture-screenrecording")

-- Laptop lid
o.bind("switch:on:Lid Switch", nil, "karchy-system-lid-close", { locked = true })
o.bind("switch:off:Lid Switch", nil, "karchy-hyprland-monitor-clamshell", { locked = true })

-- Touchpad: three-finger swipe switches workspace
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
