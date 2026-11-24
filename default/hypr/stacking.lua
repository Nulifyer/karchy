-- Which window is in front (D-159; docs/components.md, "Window modes").
-- Alt+Tab's order is in window-switch.lua.
--
-- Hyprland draws every floating window above the tiled ones, in the order
-- they were last raised, and raises one only when it is clicked. Left at
-- that, the keyboard can be in a window hidden behind others, a maximized
-- window can never get in front of one raised over it, and a dialog can go
-- behind the window it belongs to. So, as focus changes:
--
--   - A floating window given the keyboard comes to the front, however it got
--     it: Alt+Tab, a launcher that finds it open, an app asking for focus,
--     the window in front closing. Focus that only followed the pointer
--     raises nothing.
--   - A maximized or fullscreen window on a floating workspace is in front
--     while it has the keyboard, as on Windows; the others stay open behind
--     it, and one of them given the keyboard comes in front of it again.
--   - A dialog stays in front of its app's windows, and a window tagged
--     `stay-in-front` (the portal's file chooser, which belongs to another
--     app's window) in front of every other window on its workspace.
--
-- Everything here runs on Hyprland's own events; nothing polls.

local workspace_modes = require("default.hypr.workspace-modes")

local DIALOG_TAG = o.DIALOG_TAG
-- For rules: o.window("its-class", { tag = "+stay-in-front" })
local FRONT_TAG = "stay-in-front"
-- Hyprland's eFocusReason: focus that only followed the pointer, and a click.
local HOVER = 1
local CLICK = 16

local function raise(window)
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
end

local function lower(window)
  hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = window }))
end

-- A window a float rule floated says so with the rule's tag, and the windows
-- a floating workspace or a fullscreen game floats are app windows. What is
-- left floating as it opens, Hyprland floated.
hl.on("window.open", function(window)
  if not (window and window.mapped and window.floating) or window.pinned then
    return
  end

  if o.window_tagged(window, o.FLOAT_RULE_TAG) or o.tagged_at_open(window, o.FLOAT_RULE_TAG) then
    return
  end

  if o.tagged_at_open(window, workspace_modes.OPENED_TAG) or o.tagged_at_open(window, o.OVER_GAME_TAG) then
    return
  end

  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. DIALOG_TAG, window = window }))
end)

-- Whether `other` stays in front of `window` when that one is raised.
local function stays_in_front(other, window)
  if o.window_tagged(window, FRONT_TAG) or o.window_tagged(window, DIALOG_TAG) then
    return false
  end

  return o.window_tagged(other, FRONT_TAG) or (o.window_tagged(other, DIALOG_TAG) and other.pid == window.pid)
end

local function restack(window)
  local workspace = window.workspace
  if not workspace then
    return
  end

  local fullscreen = (window.fullscreen or 0) ~= 0
  -- The windows come in stacking order, the one in front last.
  local in_front, behind = {}, {}
  for _, other in ipairs(hl.get_workspace_windows(workspace)) do
    if other.address ~= window.address and other.floating and not other.pinned then
      if stays_in_front(other, window) then
        table.insert(in_front, other)
      elseif fullscreen and other.allowed_over_fullscreen then
        table.insert(behind, other)
      end
    end
  end

  if fullscreen then
    -- A fullscreen game is put in front by games.lua, on any workspace.
    if workspace_modes.floating_workspace(workspace.id) then
      -- Each one lowered goes to the very back, so the one in front goes
      -- first and they keep their order.
      for index = #behind, 1, -1 do
        lower(behind[index])
      end
    end
  else
    raise(window)
  end

  for _, other in ipairs(in_front) do
    raise(other)
  end
end

hl.on("window.active", function(window, reason)
  if not (window and window.mapped and window.floating) or window.pinned then
    return
  end

  reason = tonumber(reason) or 0
  if reason % 2 == HOVER then
    return
  end

  restack(window)

  -- Hyprland raises a clicked window itself, after this has run, which would
  -- put it in front of its dialog again. Once the click is done, restack.
  if reason // CLICK % 2 == 1 then
    local target = "address:" .. window.address
    hl.timer(function()
      local current = hl.get_window(target)
      if current and current.mapped and current.active and current.floating and not current.pinned then
        restack(current)
      end
    end, { timeout = 1, type = "oneshot" })
  end
end)
