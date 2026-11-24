-- Alt+Tab (D-159, D-165; docs/keybindings.md). Loaded by
-- karchy/hypr/bindings.lua.
--
-- Alt+Tab goes to the window used before this one, as on Windows, not to the
-- next one in a fixed ring: one press goes back and forth between two
-- windows however many are open. While the modifier stays down each further
-- press goes one window further back (with Shift, forward again), and
-- letting go switches to the window arrived at. Nothing changes before that:
-- the windows passed on the way keep their place and their order, so the
-- window the walk left is the one used before the new one, and one more
-- press goes back to it. Alt+Escape gives the walk up.
--
-- The windows of a walk are the ones on the workspace, most recently used
-- first, then the ones minimized from it (karchy-hyprland-window-minimize),
-- which is where Windows puts a minimized window. Stopping on a minimized
-- window brings it back.
--
-- The walk lives here and nowhere else. The shell's switcher
-- (shell/plugins/window-switcher) draws it and decides nothing: every change
-- is sent to it as one event, `custom>>karchy-window-switch ...` on
-- Hyprland's event socket, and the keys work the same with no shell running.
--
-- Everything runs on Hyprland's events, and the ones that only matter during
-- a walk are watched only while one is on, so typing runs nothing here.

require("default.hypr.helpers")

local MINIMIZED = "special:minimized"
local MINIMIZED_FROM = "karchy-minimized-from-"
local EVENT = "karchy-window-switch"
-- Hyprland cuts an event off at 1024 bytes; an address takes up to 16.
local EVENT_WINDOWS = 48
-- Hyprland's eFocusReason: focus that only followed the pointer.
local HOVER = 1

-- Alt, Super and Control, left and right (xkb keycodes). Shift only turns
-- the walk around.
local HELD = { 64, 108, 133, 134, 37, 105 }
local RELEASED = 0

-- { order = addresses, minimized = address -> true, at = index, from =
--   address the walk started on, watches = event subscriptions }
local walk = nil

local function tell_shell(message)
  hl.dispatch(hl.dsp.event(EVENT .. " " .. message))
end

-- "show <index of the target> <address> <address>* ...", a minimized window
-- marked with a star. More windows than an event holds: the ones around the
-- target.
local function announce()
  local count = #walk.order
  local first = 1
  if count > EVENT_WINDOWS then
    first = math.max(1, math.min(walk.at - EVENT_WINDOWS // 2, count - EVENT_WINDOWS + 1))
  end

  local words = { "show", tostring(walk.at - first + 1) }
  for index = first, math.min(count, first + EVENT_WINDOWS - 1) do
    local address = walk.order[index]
    table.insert(words, address .. (walk.minimized[address] and "*" or ""))
  end
  tell_shell(table.concat(words, " "))
end

local function end_walk()
  if not walk then
    return
  end

  for _, watch in ipairs(walk.watches) do
    watch:remove()
  end
  walk = nil
  tell_shell("hide")
end

local function by_use(a, b)
  return a.used < b.used
end

local function addresses(windows, order)
  table.sort(windows, by_use)
  for _, window in ipairs(windows) do
    table.insert(order, window.address)
  end
end

-- Letting go of the modifier: go to the window the walk arrived at.
local function finish()
  local target = walk.order[walk.at]
  local from, minimized = walk.from, target and walk.minimized[target]
  end_walk()

  if not target or target == from or not hl.get_window("address:" .. target) then
    return
  end

  if minimized then
    -- Back to the workspace in front, with the keyboard and on top, and no
    -- longer minimized from anywhere: the same as from the bar's indicator.
    hl.exec_cmd("karchy-hyprland-window-restore " .. target)
  else
    hl.dispatch(hl.dsp.focus({ window = "address:" .. target }))
  end
end

local function forget(address)
  for index, known in ipairs(walk.order) do
    if known == address then
      table.remove(walk.order, index)
      walk.minimized[address] = nil
      if index < walk.at or walk.at > #walk.order then
        walk.at = walk.at - 1
      end
      if walk.at == 0 and #walk.order > 0 then
        walk.at = 1
      end
      return true
    end
  end
  return false
end

local function watch_walk()
  local watches = walk.watches

  table.insert(watches, hl.on("input.keyboard.key", function(keycode, _, state)
    if state ~= RELEASED or not walk then
      return
    end
    for _, held in ipairs(HELD) do
      if keycode == held then
        finish()
        return
      end
    end
  end))

  -- Focus that moves any other way (a click, a window opening, a window that
  -- asks for it) ends the walk where things are: the next press starts from
  -- the windows as they then are. Focus that only followed the pointer does
  -- not; the walk still goes where it was going.
  table.insert(watches, hl.on("window.active", function(window, reason)
    if not walk or (window and window.address == walk.from) then
      return
    end
    if (tonumber(reason) or 0) % 2 == HOVER then
      return
    end
    end_walk()
  end))

  table.insert(watches, hl.on("workspace.active", function()
    end_walk()
  end))

  -- A window that closes during the walk leaves it.
  table.insert(watches, hl.on("window.close", function(window)
    if walk and window and forget(window.address) then
      if #walk.order == 0 then
        end_walk()
      else
        announce()
      end
    end
  end))
end

local function start_walk()
  local active = hl.get_active_window()
  local workspace = (active and active.workspace) or hl.get_active_workspace()
  local open, minimized = {}, {}

  walk = { order = {}, minimized = {}, at = 0, watches = {} }

  if workspace then
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
      if window.mapped and not window.hidden then
        table.insert(open, { address = window.address, used = window.focus_history_id or 0 })
      end
    end

    local id = tonumber(workspace.id)
    if id and id >= 1 then
      for _, window in ipairs(hl.get_windows({ tag = MINIMIZED_FROM .. id })) do
        if window.mapped and window.workspace and window.workspace.name == MINIMIZED then
          table.insert(minimized, { address = window.address, used = window.focus_history_id or 0 })
          walk.minimized[window.address] = true
        end
      end
    end
  end

  addresses(open, walk.order)
  addresses(minimized, walk.order)

  for index, address in ipairs(walk.order) do
    if active and address == active.address then
      walk.at = index
      walk.from = address
    end
  end

  watch_walk()
end

-- Whether a key that ends the walk when let go is down. Without one (the
-- action run from a command, or bound to a key with no modifier) nothing
-- would ever end the walk, so each press is a whole switch.
local function held()
  for _, keycode in ipairs(HELD) do
    if hl.is_key_down(keycode) then
      return true
    end
  end
  return false
end

function o.switch_window(step)
  local function switch()
    if not walk then
      start_walk()
    end

    local count = #walk.order
    if count == 0 then
      end_walk()
      return
    end

    if walk.at == 0 then
      walk.at = step > 0 and 1 or count
    else
      walk.at = (walk.at - 1 + step) % count + 1
    end

    if held() then
      announce()
    else
      finish()
    end
  end

  o.bind_expressions[switch] = step > 0 and "o.switch_window(1)" or "o.switch_window(-1)"
  return switch
end

-- Alt+Escape: stay where you were.
function o.cancel_window_switch()
  o.bind_expressions[end_walk] = "o.cancel_window_switch()"
  return end_walk
end
