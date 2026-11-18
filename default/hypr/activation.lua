-- A window that asks for focus gets it, on whatever workspace it is.
--
-- An app raises its own window through xdg-activation: `code <folder>` handing
-- the folder to the VS Code window that has it open, a link opening in a
-- browser that already runs, a notification action. misc.focus_on_activate
-- covers that only when the request carries proof of the user's input in the
-- app that made it. Hyprland 0.57.2 gives a request without that proof no
-- more than the urgent mark, and the examples above never carry it: the
-- keypress went to a terminal, a menu or a notification, not to the app that
-- raises itself. So focus follows the urgent mark as well.
--
-- Hyprland cannot tell such a request from an app that only wants attention
-- (Qt's alert(), which Telegram calls for every message). Windows tagged
-- attention-only keep the urgent mark without taking focus; the rule at the
-- end of this file tags Telegram's. A request that is not followed keeps the
-- mark too, and the bar shows it on the window's workspace.

hl.on("window.urgent", function(window)
  if not (window and window.mapped) or o.window_tagged(window, "attention-only") then return end

  -- The mark is set in the middle of Hyprland handling the request, and a
  -- request with proof is focused by Hyprland right after. Wait a loop, then
  -- focus only a window that is still there and still unfocused.
  local target = "address:" .. window.address
  hl.timer(function()
    local current = hl.get_window(target)
    if not (current and current.mapped) or current.active then return end

    -- Focusing a window in a closed scratchpad would open the scratchpad.
    local workspace = current.workspace
    if workspace and workspace.special and not workspace.visible then return end

    -- A menu that holds the keyboard keeps it; the window stays urgent.
    for _, layer in ipairs(hl.get_layers() or {}) do
      if layer.mapped and layer.keyboard_interactivity == 1 then return end
    end

    -- So does a fullscreen game: losing the keyboard in the middle of a match
    -- costs more than an answer that waits. The window stays urgent.
    if o.fullscreen_game(hl.get_active_window()) then return end

    local before = hl.get_active_workspace()
    hl.dispatch(hl.dsp.focus({ window = target }))

    -- Hyprland switches the workspace and then refuses the focus while the
    -- session is locked, and Lua cannot ask whether it is. Go back, so nothing
    -- moved behind the lock screen; the window keeps its urgent mark.
    local focused = hl.get_window(target)
    local after = hl.get_active_workspace()
    if focused and not focused.active and before and after and before.id ~= after.id then
      hl.dispatch(hl.dsp.focus({ workspace = tostring(before.id) }))
    end
  end, { timeout = 1, type = "oneshot" })
end)

-- Telegram asks for activation on every message it receives (upstream
-- ec305459f); it wants attention, not the keyboard.
o.window("org.telegram.desktop", { tag = "+attention-only" })
