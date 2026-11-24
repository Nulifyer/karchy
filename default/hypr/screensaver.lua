-- Windows that open while the screensaver shows (D-179).
--
-- A window opening is not somebody coming back: to the idle service only
-- input is. So the screensaver stays up, keeps the keyboard and the idle
-- cycle goes on to the lock. The rules in apps/system.lua put such a window on
-- the workspace its monitor was showing, at the size and state it would have
-- had there, without the keyboard (the screensaver ends when it loses it).
-- activation.lua leaves the keyboard with the screensaver when a window asks
-- for it.
--
-- Once the screensaver is gone, the newest of those windows gets the
-- keyboard, and so comes in front (stacking.lua): it is what the person would
-- have seen had they been there, and a window left behind a maximized one on
-- a floating workspace would go unnoticed.
--
-- Runs on Hyprland's window events; nothing polls.

local M = {}

-- For rules: o.window("org.karchy.screensaver", { tag = "+screensaver" })
local TAG = "screensaver"

local savers = {}
local waiting = nil

-- A config reload starts this file afresh while a screensaver may be showing.
for _, window in ipairs(hl.get_windows({ tag = TAG })) do
  if window.mapped then
    savers[window.address] = true
  end
end

function M.showing()
  return next(savers) ~= nil
end

-- The window gets the keyboard once the screensaver is gone.
function M.keyboard_after(window)
  waiting = "address:" .. window.address
end

hl.on("window.open", function(window)
  if not window then
    return
  end

  if o.window_tagged(window, TAG) then
    savers[window.address] = true
  elseif M.showing() then
    M.keyboard_after(window)
  end
end)

hl.on("window.close", function(window)
  if not (window and savers[window.address]) then
    return
  end

  savers[window.address] = nil
  if M.showing() or not waiting then
    return
  end

  local target = waiting
  waiting = nil

  -- Hyprland hands the focus on from the closing window after this has run.
  hl.timer(function()
    local current = hl.get_window(target)
    if current and current.mapped and not current.active then
      hl.dispatch(hl.dsp.focus({ window = target }))
    end
  end, { timeout = 1, type = "oneshot" })
end)

return M
