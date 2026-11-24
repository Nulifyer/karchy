-- Alt+Tab (D-159; docs/keybindings.md). Loaded by karchy/hypr/bindings.lua.

require("default.hypr.helpers")

-- Alt+Tab goes to the window used before this one, as on Windows, not to the
-- next one in a fixed ring: one press goes back and forth between two
-- windows however many are open. While the modifier stays down each further
-- press goes one window further back (with Shift, forward again), in the
-- order the windows had when the first press came. Letting go ends the walk:
-- the window arrived at is the newest and the one the walk left is next, so
-- one more press goes back to it.
--
-- Hyprland keeps the order (focus_history_id) and changes it with every step
-- taken here, so the order is read once, when the walk starts, and the window
-- the walk left is put back in second place when it ends.
local walk = nil

-- Alt, Super and Control, left and right (xkb keycodes). Shift only turns
-- the walk around.
local HELD = { [64] = true, [108] = true, [133] = true, [134] = true, [37] = true, [105] = true }

local function end_walk()
  if walk and walk.watch then
    walk.watch:remove()
  end
  walk = nil
end

local function start_walk()
  local active = hl.get_active_window()
  local workspace = (active and active.workspace) or hl.get_active_workspace()
  local windows = {}

  if workspace then
    for _, window in ipairs(hl.get_workspace_windows(workspace)) do
      if window.mapped and not window.hidden then
        table.insert(windows, { address = window.address, used = window.focus_history_id or 0 })
      end
    end
  end

  table.sort(windows, function(a, b) return a.used < b.used end)

  walk = { order = {}, at = 0, steps = 0 }
  for index, window in ipairs(windows) do
    walk.order[index] = window.address
    if active and window.address == active.address then
      walk.at = index
      walk.from = window.address
    end
  end

  -- Watched only while a walk is on, so typing runs nothing here.
  walk.watch = hl.on("input.keyboard.key", function(keycode, _, state)
    if state ~= 0 or not HELD[keycode] or not walk then
      return
    end

    local from, to, steps = walk.from, walk.target, walk.steps
    end_walk()

    -- The windows passed on the way were focused too. Focusing the one the
    -- walk left and then the one it arrived at puts those two first again.
    if steps > 1 and from and to and from ~= to and hl.get_window("address:" .. from) then
      hl.dispatch(hl.dsp.focus({ window = "address:" .. from }))
      hl.dispatch(hl.dsp.focus({ window = "address:" .. to }))
    end
  end)
end

function o.switch_window(step)
  local function switch()
    if not walk then
      start_walk()
    end

    local count = #walk.order
    -- A window that closed during the walk, or one that cannot take the
    -- keyboard (its dialog has it), is passed over.
    for _ = 1, count do
      if walk.at == 0 then
        walk.at = step > 0 and 1 or count
      else
        walk.at = (walk.at - 1 + step) % count + 1
      end

      local address = walk.order[walk.at]
      local target = "address:" .. address
      local window = hl.get_window(target)
      if window and window.mapped then
        walk.target = address
        hl.dispatch(hl.dsp.focus({ window = target }))
        local now = hl.get_active_window()
        if now and now.address == address then
          walk.steps = walk.steps + 1
          return
        end
      end
    end
  end

  o.bind_expressions[switch] = step > 0 and "o.switch_window(1)" or "o.switch_window(-1)"
  return switch
end

-- Focus that moves any other way (a click, a window opening) ends the walk:
-- the next press starts from the windows as they then are.
hl.on("window.active", function(window)
  if walk and not (window and window.address == walk.target) then
    end_walk()
  end
end)
