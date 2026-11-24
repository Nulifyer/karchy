-- Halves on a floating workspace (D-165; docs/components.md, "Window
-- modes"). Loaded by karchy/hypr/bindings.lua.
--
-- Super+Left and Super+Right put the window on the left or right half of its
-- monitor, as on Windows. On a tiling workspace the same keys move the focus,
-- as they always have, so each key carries two actions and each acts on its
-- own kind of workspace.
--
--   - A window that is not on a half goes to the half the arrow points at.
--   - A window on the left half, Super+Right: back to the place and size it
--     had before (and the other way round). One more press snaps it right.
--   - A window on the left half, Super+Left: to the right half of the monitor
--     on the left, if there is one, and so on across the monitors.
--   - Super+Down gives a window on a half its earlier place and size back
--     before it minimizes anything (o.window_down, below). Super+Up maximizes
--     it, and Super+Down then brings it back to its half.
--   - A maximized window goes straight to the half the arrow points at.
--
-- A half is the tile a tiling workspace would give one of two windows: the
-- same gaps to the screen edge, the bar and the other half.
--
-- Whether a window is on a half is read from where it is, never remembered,
-- so a window dragged or resized by hand is simply no longer on one. What is
-- remembered is the place and size from before the snap, in a tag on the
-- window: it goes with the window, and survives a config reload. Hyprland
-- tells the config nothing about a drag, so a window dragged off its half
-- keeps the half's size until Super+Down gives the earlier size back.
--
-- The bar docks while a window on its monitor is maximized and floats again
-- afterwards, which moves the top of the usable area by the bar's margin. A
-- window on a half follows: it is fitted again a moment after a window
-- enters or leaves maximized (the end of this file).

require("default.hypr.helpers")
local workspace_modes = require("default.hypr.workspace-modes")

local BEFORE = "karchy-before-snap-"
local OPPOSITE = { l = "r", r = "l" }
-- A window may round the size it is given (a terminal, to whole cells).
local CLOSE = 2
-- How far the top of a half moves when the bar docks or floats: its margin
-- to the screen edge, with room to spare. The other three edges stay.
local BAR_SHIFT = 8
-- The bar is the shell's surface and answers a maximize a moment later, and
-- Hyprland has no event for the area it reserves. Milliseconds.
local BAR_SETTLES = 150

local function sides(key)
  local value = hl.get_config(key)
  if type(value) ~= "table" then
    value = tonumber(value) or 0
    return { left = value, right = value, top = value, bottom = value }
  end
  return value
end

-- The left or right half of a monitor, as the box of the window itself:
-- inside its border and below its titlebar.
local function half(monitor, side)
  local area = workspace_modes.work_area(monitor)
  if not area then
    return nil
  end

  local outer, inner = sides("general.gaps_out"), sides("general.gaps_in")
  local border = tonumber(hl.get_config("general.border_size")) or 0
  local titlebar = workspace_modes.titlebar_height()
  local middle = area.x + area.w // 2

  local from = side == "l" and area.x + outer.left or middle + inner.left
  local to = side == "l" and middle - inner.right or area.x + area.w - outer.right

  return {
    x = from + border,
    y = area.y + outer.top + titlebar + border,
    w = to - from - 2 * border,
    h = area.h - outer.top - outer.bottom - titlebar - 2 * border,
  }
end

local function close_to(a, b, slack)
  return math.abs(a - b) <= (slack or CLOSE)
end

-- The size of a half, whichever way the bar stood when it was given.
local function same_size(window, box)
  return close_to(window.size.x, box.w) and close_to(window.size.y, box.h, BAR_SHIFT)
end

local function exactly(window, box)
  return close_to(window.at.x, box.x) and close_to(window.at.y, box.y)
    and close_to(window.size.x, box.w) and close_to(window.size.y, box.h)
end

-- "l" or "r" when the window is on that half of its monitor: its left, right
-- and bottom edges are the half's, and its top is where the bar leaves it or
-- left it. The half's box comes back too.
local function side_of(window)
  for _, side in ipairs({ "l", "r" }) do
    local box = half(window.monitor, side)
    if box
      and close_to(window.at.x, box.x)
      and close_to(window.size.x, box.w)
      and close_to(window.at.y + window.size.y, box.y + box.h)
      and close_to(window.at.y, box.y, BAR_SHIFT)
    then
      return side, box
    end
  end
  return nil
end

-- The tag carries x, y, width and height, a negative number written n12.
local function before_tag(window)
  for _, name in ipairs(window.tags or {}) do
    if name:sub(1, #BEFORE) == BEFORE then
      return name
    end
  end
  return nil
end

local function before(window)
  local name = before_tag(window)
  if not name then
    return nil
  end

  local numbers = {}
  for sign, digits in name:sub(#BEFORE + 1):gmatch("(n?)(%d+)") do
    table.insert(numbers, (sign == "n" and -1 or 1) * tonumber(digits))
  end
  if #numbers ~= 4 then
    return nil
  end
  return { x = numbers[1], y = numbers[2], w = numbers[3], h = numbers[4] }
end

local function forget(window)
  local name = before_tag(window)
  if name then
    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. name, window = window }))
  end
end

local function remember(window, box)
  forget(window)

  local words = {}
  for _, number in ipairs({ box.x, box.y, box.w, box.h }) do
    number = math.floor(number)
    table.insert(words, (number < 0 and "n" or "") .. math.abs(number))
  end
  hl.dispatch(hl.dsp.window.tag({ tag = "+" .. BEFORE .. table.concat(words, "_"), window = window }))
end

-- Hyprland resizes a floating window around its middle, so the place is set
-- after the size: the box's, or the corner the window has now.
local function put(window, box, keep_place)
  local x, y = box.x, box.y
  if keep_place then
    x, y = window.at.x, window.at.y
  end

  hl.dispatch(hl.dsp.window.resize({ x = box.w, y = box.h, relative = false, window = window }))
  hl.dispatch(hl.dsp.window.move({ x = x, y = y, relative = false, window = window }))
end

-- An app window on a floating workspace. A dialog keeps the size its app
-- gave it, a pinned window its place, a fullscreen one the screen.
local function snappable(window)
  if not (window and window.mapped and window.floating) or window.pinned then
    return false
  end
  if (window.fullscreen or 0) > 1 or o.window_tagged(window, o.DIALOG_TAG) then
    return false
  end

  local workspace = window.workspace
  return workspace ~= nil and workspace_modes.floating_workspace(workspace.id)
end

-- Gives a window the place and size it had before it was snapped. One that
-- was dragged off its half and still has the half's size gets the size back
-- where it is now. Returns whether there was anything to give back; a window
-- resized by hand since has its own size, and only loses the tag.
local function restore(window)
  local box = before(window)
  if not box then
    return false
  end

  local on_half = side_of(window) ~= nil
  local half_sized = on_half
  if not on_half then
    local left = half(window.monitor, "l")
    half_sized = left ~= nil and same_size(window, left)
  end

  forget(window)
  if not half_sized then
    return false
  end

  put(window, box, not on_half)
  return true
end

local function snap(direction)
  local window = hl.get_active_window()
  if not snappable(window) then
    return
  end

  local selector = "address:" .. window.address
  -- A maximized window goes straight to the half the arrow points at, as on
  -- Windows, whatever it was before it was maximized; what it comes back to
  -- later is the size it had before it was snapped or maximized.
  local side = nil
  if (window.fullscreen or 0) == 1 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset", window = selector }))
    window = hl.get_window(selector)
    if not window then
      return
    end
  else
    side = side_of(window)
  end

  if side == OPPOSITE[direction] then
    restore(window)
    return
  end

  if side == direction then
    -- On to the next monitor that way, onto the half it enters by.
    local from, target = window.monitor, hl.get_monitor(direction)
    if not (from and target) or target.name == from.name then
      return
    end

    hl.dispatch(hl.dsp.window.move({ monitor = target.name, window = selector }))
    window = hl.get_window(selector)
    local workspace = window and window.workspace
    if not workspace or not workspace_modes.floating_workspace(workspace.id) then
      -- A tiling workspace tiles it; there is no half to keep.
      if window then
        forget(window)
      end
      return
    end

    local box, earlier = half(target, OPPOSITE[direction]), before(window)
    if earlier then
      earlier.x, earlier.y = earlier.x - from.x + target.x, earlier.y - from.y + target.y
      remember(window, earlier)
    end
    if box then
      put(window, box)
    end
    return
  end

  local box = half(window.monitor, direction)
  if not box then
    return
  end

  -- A window dragged off a half and snapped again keeps what it had before
  -- the first snap; one given a size by hand since is remembered as it is.
  local left = half(window.monitor, "l")
  if not before(window) or not (left and same_size(window, left)) then
    remember(window, { x = window.at.x, y = window.at.y, w = window.size.x, h = window.size.y })
  end
  put(window, box)
end

function o.snap_window(direction)
  local function action()
    snap(direction)
  end

  o.bind_expressions[action] = string.format("o.snap_window(%q)", direction)
  return action
end

-- An action that belongs to tiling workspaces, for a key that does something
-- else on a floating one.
function o.on_tiling_workspace(dispatcher, expression)
  local function action()
    local window = hl.get_active_window()
    local workspace = (window and window.workspace) or hl.get_active_workspace()
    if workspace and workspace_modes.floating_workspace(workspace.id) then
      return
    end
    hl.dispatch(dispatcher)
  end

  o.bind_expressions[action] = expression
  return action
end

-- Super+Down, as on Windows: a maximized window comes back to its size, a
-- window on a half to the place and size it had before, and anything else
-- is minimized. `karchy-hyprland-window-minimize --down` runs this too.
function o.window_down()
  local window = hl.get_active_window()
  if not (window and window.mapped) then
    return
  end

  if (window.fullscreen or 0) ~= 0 then
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "unset" }))
  elseif not (snappable(window) and restore(window)) then
    hl.exec_cmd("karchy-hyprland-window-minimize " .. window.address)
  end
end

o.bind_commands[o.window_down] = "karchy-hyprland-window-minimize --down"

-- The bar has docked or floats again once a window entered or left
-- maximized: the windows on a half of that workspace take the half as it now
-- is. One short timer per such change; nothing runs in between.
hl.on("window.fullscreen", function(window)
  local workspace = window and window.workspace
  if not (workspace and workspace_modes.floating_workspace(workspace.id)) then
    return
  end

  local id = tostring(workspace.id)
  hl.timer(function()
    for _, other in ipairs(hl.get_workspace_windows(id)) do
      if (other.fullscreen or 0) == 0 and before_tag(other) and snappable(other) then
        local side, box = side_of(other)
        if side and not exactly(other, box) then
          put(other, box)
        end
      end
    end
  end, { timeout = BAR_SETTLES, type = "oneshot" })
end)
