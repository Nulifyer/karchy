-- Which window is in front, where Alt+Tab goes (D-159), the halves of a
-- floating workspace (D-165) and which rules karchy's own windows get
-- (D-175): karchy's real default/hypr/stacking.lua, window-switch.lua,
-- snap.lua, workspace-modes.lua and the window rules of apps/system.lua and
-- apps/vms.lua under a stand-in for Hyprland's `hl` that keeps the windows'
-- stacking order, focus history, place and size the way Hyprland does.
--
--   lua tests/window-stacking.lua        (from the checkout)

local repo = os.getenv("KARCHY_PATH") or "."
package.path = repo .. "/?.lua;" .. package.path

-- ---- the stand-in

local stack = {} -- windows in stacking order, the one in front last
local history = {} -- addresses, the one with the keyboard first
local handlers = {} -- event name -> functions
local rules = {} -- every hl.window_rule call
local workspace = { id = 1 }
local executed = {} -- every hl.exec_cmd
local said = {} -- every custom event: what the shell's switcher is told
local floated = {} -- every float dispatch: "<address> on" or "<address> off"
local alt_down = true -- whether the key that ends an Alt+Tab walk is held
-- Two monitors side by side, the bar's 31 pixels reserved on each.
local monitors = {
  { name = "LEFT", x = 0, y = 0, width = 1280, height = 800, scale = 1, transform = 0, reserved = { top = 31 } },
  { name = "RIGHT", x = 1280, y = 0, width = 1920, height = 1080, scale = 1, transform = 0, reserved = { top = 31 } },
}
local monitor_workspace = { LEFT = workspace, RIGHT = { id = 11 } }
local second_monitor = false
local config = {
  ["general.gaps_out"] = { left = 10, right = 10, top = 10, bottom = 10 },
  ["general.gaps_in"] = { left = 5, right = 5, top = 5, bottom = 5 },
  ["general.border_size"] = 2,
  ["plugin.hyprbars.enabled"] = true,
  ["plugin.hyprbars.bar_height"] = 30,
}

local function fire(name, ...)
  for _, handler in ipairs(handlers[name] or {}) do
    handler(...)
  end
end

local function find(address)
  for index, window in ipairs(stack) do
    if window.address == address then
      return window, index
    end
  end
end

local function focus(window, reason)
  for index, address in ipairs(history) do
    if address == window.address then
      table.remove(history, index)
      break
    end
  end
  table.insert(history, 1, window.address)
  fire("window.active", window, reason)
end

local window_meta = {
  __index = function(window, key)
    if key == "active" then
      return history[1] == window.address
    elseif key == "focus_history_id" then
      for index, address in ipairs(history) do
        if address == window.address then
          return index - 1
        end
      end
      return 99
    end
  end,
}

local function open(address, fields)
  local window = setmetatable({ address = address, mapped = true, workspace = workspace, pid = 1, tags = {}, fullscreen = 0, floating = false }, window_meta)
  for key, value in pairs(fields or {}) do
    window[key] = value
  end
  table.insert(stack, window)
  fire("window.open_early", window)
  focus(window, 65536)
  fire("window.open", window)
  return window
end

local function selected(selector)
  if type(selector) == "table" then
    return selector
  end
  return (find((tostring(selector):gsub("^address:", ""))))
end

local actions = {
  zorder = function(args)
    local window, index = find(selected(args.window).address)
    table.remove(stack, index)
    if args.mode == "top" then
      table.insert(stack, window)
      window.allowed_over_fullscreen = true
    else
      table.insert(stack, 1, window)
      window.allowed_over_fullscreen = false
    end
  end,
  tag = function(args)
    local window = selected(args.window)
    if args.tag:sub(1, 1) == "+" then
      table.insert(window.tags, args.tag:sub(2))
    else
      for index, name in ipairs(window.tags) do
        if name == args.tag:sub(2) then
          table.remove(window.tags, index)
          break
        end
      end
    end
  end,
  focus = function(args)
    local window = args.window and selected(args.window)
    if window then
      focus(window, 4)
    end
  end,
  event = function(text)
    table.insert(said, text)
  end,
  -- Recorded, not applied: the windows here say themselves whether they float.
  float = function(args)
    table.insert(floated, selected(args.window).address .. " " .. args.action)
  end,
  fullscreen = function(args)
    local window = args.window and selected(args.window) or (find(history[1]))
    if window then
      window.fullscreen = args.action == "unset" and 0 or (args.mode == "maximized" and 1 or 2)
    end
  end,
  -- Hyprland resizes a floating window around its middle.
  resize = function(args)
    local window = selected(args.window)
    window.at = { x = window.at.x + (window.size.x - args.x) // 2, y = window.at.y + (window.size.y - args.y) // 2 }
    window.size = { x = args.x, y = args.y }
  end,
  move = function(args)
    local window = selected(args.window)
    if args.monitor then
      for _, monitor in ipairs(monitors) do
        if monitor.name == args.monitor then
          window.monitor, window.workspace = monitor, monitor_workspace[monitor.name]
        end
      end
    elseif args.relative == false then
      window.at = { x = args.x, y = args.y }
    end
  end,
}

local function action(kind)
  return function(args) return { kind = kind, args = args or {} } end
end

-- A window list as Hyprland filters it: by workspace, by tag.
local function windows_where(keep)
  local found = {}
  for _, window in ipairs(stack) do
    if keep(window) then
      table.insert(found, window)
    end
  end
  return found
end

hl = setmetatable({
  dsp = setmetatable({
    focus = action("focus"),
    event = action("event"),
    window = setmetatable({
      alter_zorder = action("zorder"),
      float = action("float"),
      tag = action("tag"),
      bring_to_top = action("none"),
      fullscreen = action("fullscreen"),
      resize = action("resize"),
      move = action("move"),
    }, {
      __index = function() return action("none") end,
    }),
  }, { __index = function() return action("none") end }),
  dispatch = function(dispatcher)
    if actions[dispatcher.kind] then
      actions[dispatcher.kind](dispatcher.args)
    end
  end,
  on = function(name, handler)
    handlers[name] = handlers[name] or {}
    table.insert(handlers[name], handler)
    return {
      remove = function()
        for index, registered in ipairs(handlers[name]) do
          if registered == handler then
            table.remove(handlers[name], index)
            return
          end
        end
      end,
    }
  end,
  timer = function(fn) fn() end,
  window_rule = function(rule) table.insert(rules, rule) end,
  get_window = selected,
  get_windows = function(filter)
    return windows_where(function(window)
      if not (filter and filter.tag) then
        return true
      end
      for _, name in ipairs(window.tags) do
        if name == filter.tag or name == filter.tag .. "*" then
          return true
        end
      end
      return false
    end)
  end,
  get_workspace_windows = function(selector)
    local id = type(selector) == "table" and selector.id or tonumber(selector)
    return windows_where(function(window) return window.workspace.id == id end)
  end,
  -- Alt, by its keycode.
  is_key_down = function(keycode) return alt_down and keycode == 64 end,
  get_active_window = function() return (find(history[1])) end,
  get_active_workspace = function() return workspace end,
  get_config = function(key) return config[key] end,
  -- The monitor in a direction from the first one.
  get_monitor = function(direction) return second_monitor and direction == "r" and monitors[2] or nil end,
  exec_cmd = function(command) table.insert(executed, command) end,
  plugin = { hyprbars = {} },
}, { __index = function() return function() end end })

-- ---- checks

local checks = 0
local function eq(got, want, what)
  checks = checks + 1
  if got ~= want then
    error(string.format("%s: got %s, want %s", what, tostring(got), tostring(want)), 2)
  end
end

local function order()
  local addresses = {}
  for _, window in ipairs(stack) do
    table.insert(addresses, window.address)
  end
  return table.concat(addresses, " ")
end

local function tagged(window, tag)
  for _, name in ipairs(window.tags) do
    if name == tag then
      return true
    end
  end
  return false
end

local function reset()
  stack, history = {}, {}
end

require("default.hypr.helpers")
require("default.hypr.window-switch")
require("default.hypr.snap")
local workspace_modes = require("default.hypr.workspace-modes")
o.OVER_GAME_TAG = "karchy-over-game"
require("default.hypr.stacking")
require("default.hypr.apps.system")
require("default.hypr.apps.vms")
local static_rules = rules

local ALT, RELEASED = 64, 0
local next_window, previous_window = o.switch_window(1), o.switch_window(-1)
local cancel = o.cancel_window_switch()
local function let_go()
  fire("input.keyboard.key", ALT, 0, RELEASED)
end

-- Alt+Tab swaps the two windows used last, however many are open, and
-- nothing changes before Alt is let go.
local a, b, c, d = open("a"), open("b"), open("c"), open("d")
next_window()
eq(history[1], "d", "pressing Tab alone changes no focus")
eq(said[#said], "karchy-window-switch show 2 d c b a", "the switcher is told the windows, last used first, and the target")
let_go()
eq(history[1] .. history[2], "cd", "letting go goes to the window used before this one")
eq(said[#said], "karchy-window-switch hide", "and the switcher is told the walk is over")
next_window()
let_go()
eq(history[1], "d", "and back with one more press")

-- With Alt held each press goes one further back, Shift+Tab forward again.
next_window()
next_window()
next_window()
eq(said[#said], "karchy-window-switch show 4 d c b a", "three presses with Alt held go three windows back")
previous_window()
eq(said[#said], "karchy-window-switch show 3 d c b a", "Shift+Tab goes one forward again")
eq(#handlers["input.keyboard.key"], 1, "the key release is watched during a walk")
let_go()
eq(history[1] .. history[2], "bd", "after the walk the window it left is second, and the ones passed were never focused")
eq(#handlers["input.keyboard.key"], 0, "and no key is watched once the walk is over")

-- Alt+Escape gives the walk up: nothing moves.
next_window()
next_window()
cancel()
eq(said[#said], "karchy-window-switch hide", "Alt+Escape closes the switcher")
let_go()
eq(history[1] .. history[2], "bd", "and the window stays the one it was")

-- A walk broken off by a click ends where things are; focus that only
-- followed the pointer does not break it.
next_window()
focus(a, 48)
eq(said[#said], "karchy-window-switch hide", "a click ends the walk")
let_go()
eq(history[1], "a", "and letting go changes nothing after it")
next_window()
focus(c, 1)
let_go()
eq(history[1], "b", "focus that followed the pointer leaves the walk going where it went")

-- A window that closes during the walk leaves it.
next_window()
next_window()
eq(said[#said], "karchy-window-switch show 3 b c a d", "two presses: the third window")
table.remove(stack, select(2, find("a")))
fire("window.close", a)
eq(said[#said], "karchy-window-switch show 3 b c d", "a window that closed is gone from the switcher, the target the next one")
let_go()
eq(history[1], "d", "and letting go goes to what the switcher showed")
for index, address in ipairs(history) do
  if address == "a" then
    table.remove(history, index)
  end
end

-- Without a key to let go (the action run from a command) a press is a whole switch.
alt_down = false
next_window()
eq(history[1], "b", "with no modifier held one press switches at once")
eq(#handlers["input.keyboard.key"], 0, "and leaves no walk behind")
alt_down = true

-- Minimized windows come after the open ones, however recently they were
-- used, and stopping on one brings it back (D-165).
local minimized = open("min", { workspace = { id = -98, name = "special:minimized" }, tags = { "karchy-minimized-from-1" } })
local elsewhere = open("far", { workspace = { id = -98, name = "special:minimized" }, tags = { "karchy-minimized-from-2" } })
focus(b, 4)
next_window()
eq(said[#said], "karchy-window-switch show 2 b d c min*", "a window minimized from this workspace is last, marked; one from another is not there")
previous_window()
previous_window()
eq(said[#said], "karchy-window-switch show 4 b d c min*", "Shift+Tab from the first window goes round to it")
executed = {}
let_go()
eq(executed[1], "karchy-hyprland-window-restore min", "stopping on a minimized window restores it")
eq(history[1], "b", "which is the restore command's to focus")
table.remove(stack, select(2, find("min")))
table.remove(stack, select(2, find("far")))
executed = {}

-- A floating window that gets the keyboard is raised, unless the pointer gave it.
reset()
local one, two = open("one", { floating = true, tags = { o.FLOAT_RULE_TAG .. "*" } }), open("two", { floating = true, tags = { o.FLOAT_RULE_TAG .. "*" } })
eq(tagged(one, "karchy-dialog"), false, "a window a float rule floated is not a dialog")
focus(one, 4)
eq(order(), "two one", "focused by command, a floating window comes to the front")
focus(two, 1)
eq(order(), "two one", "focus that followed the pointer raises nothing")
local tile = open("tile")
focus(tile, 256)
eq(order(), "two one tile", "a tiled window is not restacked")

-- A dialog is what floats as it opens without a float rule; it stays in front of its app.
reset()
local app = open("app", { floating = true, pid = 7, tags = { workspace_modes.OPENED_TAG .. "*" } })
local other = open("other", { floating = true, pid = 8, tags = { workspace_modes.OPENED_TAG .. "*" } })
local dialog = open("dialog", { floating = true, pid = 7 })
eq(tagged(dialog, "karchy-dialog"), true, "a window Hyprland floated itself is a dialog")
focus(other, 48)
eq(order(), "app dialog other", "another app's window goes in front of the dialog")
focus(app, 48)
eq(order(), "other app dialog", "a click on its own app leaves the dialog in front")
local chooser = open("chooser", { floating = true, pid = 9, tags = { o.FLOAT_RULE_TAG .. "*", "stay-in-front*" } })
focus(other, 48)
eq(order(), "app dialog other chooser", "a stay-in-front window stays in front of every app window")
focus(dialog, 48)
eq(order(), "app other chooser dialog", "a dialog that is clicked comes to the front itself")

-- A floating workspace floats only what would tile, and puts a focused maximized window in front.
reset()
rules = {}
o.workspace_mode({ default = "floating" })
local open_rule
for _, rule in ipairs(rules) do
  if rule.name == "karchy-floating-open-1" then
    open_rule = rule
  end
end
eq(open_rule ~= nil and open_rule.match.float, false, "the rule that floats what opens there leaves dialogs alone")

local big = open("big", { floating = true, pid = 7, fullscreen = 1, tags = { workspace_modes.OPENED_TAG .. "*" } })
local small = open("small", { floating = true, pid = 8, tags = { workspace_modes.OPENED_TAG .. "*" } })
eq(big.fullscreen, 1, "a maximized window stays maximized when another app window opens (D-165)")
local prompt = open("prompt", { floating = true, pid = 7 })
focus(small, 256)
eq(small.allowed_over_fullscreen, true, "a window given the keyboard comes in front of the maximized one")
focus(big, 48)
eq(small.allowed_over_fullscreen, false, "the maximized window, clicked, has the others behind it")
eq(prompt.allowed_over_fullscreen, true, "and keeps its own dialog in front")

-- karchy's own windows are app windows with a size of their own (D-175). No
-- float rule names them, so on a tiling workspace they tile like any app.
local own_titles = { "^Settings$", "^Quick install$", "^Updates$", "^Virtual machines$", "^Containers$" }
eq(#o.own_size_apps, #own_titles, "the five windows of karchy's own are app windows with a size of their own")
for index, title in ipairs(own_titles) do
  local named = 0
  for _, rule in ipairs(static_rules) do
    if rule.match and rule.match.title == title then
      named = named + 1
    end
  end
  eq(named, 0, "no rule floats or places " .. title .. " on a tiling workspace")
  eq(o.own_size_apps[index].class, "^karchy-shell$", title .. " is matched as a shell window")
end

-- On a floating workspace a rule of their own floats them in the middle at
-- the size they give themselves, and the rule that sizes app windows there
-- leaves them out.
local function rule_named(name)
  local found
  for _, rule in ipairs(rules) do
    if rule.name == name then
      found = rule
    end
  end
  return found
end
local own_rule = rule_named("karchy-floating-own-size-1")
eq(own_rule ~= nil and own_rule.enabled and own_rule.match.title, "^Settings$", "a floating workspace has a rule for Settings")
eq(own_rule.match.class, "^karchy-shell$", "of the shell's class: another app's window named Settings is not it")
eq(own_rule.match.workspace, "r[1-2147483647]", "on every floating workspace")
eq(tostring(own_rule.float) .. " " .. tostring(own_rule.center), "true true", "floating, in the middle")
eq(own_rule.size, "min(900,monitor_w*0.85) min(680,monitor_h*0.85)", "at the size Settings gives itself, 85% of a smaller screen")
eq(rule_named("karchy-floating-own-size-3").size, "min(760,monitor_w*0.85) min(640,monitor_h*0.85)", "each at its own")
eq(own_rule.tag, "+" .. workspace_modes.OPENED_TAG, "claimed by the mode like any app window")
eq(rule_named("karchy-floating-own-size-5").match.title, "^Containers$", "and one for each of the five")
eq(rule_named("karchy-floating-own-size-6"), nil, "and no more")
eq(open_rule.match.class:find("(?:^karchy-shell$)", 1, true) ~= nil, true, "the rule that sizes app windows leaves karchy's own out, by the shell's class")
local _, shell_classes = open_rule.match.class:gsub("karchy%-shell", "")
eq(shell_classes, 1, "named once for the five")
eq(open_rule.match.title == nil or open_rule.match.title:find("Settings", 1, true) == nil, true, "and not by a title another app's window can have")

-- Claimed, it tiles when it is carried to a workspace that tiles.
reset()
floated = {}
local settings = open("settings", { floating = true, pid = 5, tags = { workspace_modes.OPENED_TAG .. "*" } })
eq(tagged(settings, workspace_modes.FLOATED_TAG), true, "the mode claims a window of karchy's own it floated")
eq(tagged(settings, "karchy-dialog"), false, "and it is no dialog")
o.workspace_mode({ workspace = 3, mode = "dwindle" })
eq(rule_named("karchy-floating-own-size-10").match.workspace, "r[4-2147483647]", "a workspace that tiles is left out of its rules")
fire("window.move_to_workspace", settings, { id = 3 })
eq(floated[#floated], "settings off", "carried to a tiling workspace, it tiles")
eq(tagged(settings, workspace_modes.FLOATED_TAG), false, "and is the mode's no longer")
o.workspace_mode({ workspace = 3, mode = "floating" })

-- Halves (D-165). Still on the floating workspace: Super+Left and Super+Right
-- put a window on a half, the tile two windows would share on a tiling one.
reset()
local function box(window)
  return string.format("%d,%d %dx%d", window.at.x, window.at.y, window.size.x, window.size.y)
end
local function app(address, fields)
  local window = { floating = true, monitor = monitors[1], at = { x = 200, y = 100 }, size = { x = 800, y = 500 }, tags = { workspace_modes.OPENED_TAG .. "*" } }
  for key, value in pairs(fields or {}) do
    window[key] = value
  end
  return open(address, window)
end
local snap_left, snap_right = o.snap_window("l"), o.snap_window("r")
local focus_left = o.on_tiling_workspace({ kind = "focus-left" }, "focus left")
local moved = 0
actions["focus-left"] = function() moved = moved + 1 end

local win = app("win")
focus_left()
eq(moved, 0, "on a floating workspace Super+Left does not move the focus")
snap_left()
eq(box(win), "12,73 621x715", "Super+Left puts the window on the left half, under its titlebar")
snap_left()
eq(box(win), "12,73 621x715", "and leaves it there with no monitor on that side")
snap_right()
eq(box(win), "200,100 800x500", "Super+Right brings it back to the place and size it had")
eq(table.concat(win.tags, " "):find("before-snap", 1, true), nil, "and nothing is remembered any more")
snap_right()
eq(box(win), "647,73 621x715", "one more press puts it on the right half")

-- Super+Up maximizes it, Super+Down brings it back to its half, then to its
-- earlier place, then minimizes it.
hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized", action = "set" }))
o.window_down()
eq(win.fullscreen .. " " .. box(win), "0 647,73 621x715", "Super+Down on the maximized window: back on its half")
o.window_down()
eq(box(win), "200,100 800x500", "Super+Down on a half: the earlier place and size")
eq(#executed, 0, "nothing was minimized on the way")
o.window_down()
eq(executed[1], "karchy-hyprland-window-minimize win", "Super+Down on a window that is on no half minimizes it")

-- A maximized window goes straight to the half the arrow points at, also one
-- maximized from the other half, and comes back to the size it had before
-- either.
win.fullscreen = 1
snap_left()
eq(win.fullscreen .. " " .. box(win), "0 12,73 621x715", "a maximized window snaps")
win.fullscreen = 1
snap_right()
eq(win.fullscreen .. " " .. box(win), "0 647,73 621x715", "maximized from the left half, Super+Right goes to the right half")
snap_left()
eq(box(win), "200,100 800x500", "and it comes back to its own size from there")

-- Dragged off its half the window keeps the half's size, and Super+Down gives
-- the earlier size back where the window now is.
snap_left()
win.at = { x = 300, y = 200 }
o.window_down()
eq(box(win), "300,200 800x500", "a window dragged off its half gets its size back where it is")
win.at = { x = 200, y = 100 }
snap_left()
win.at = { x = 300, y = 200 }
snap_right()
snap_left()
eq(box(win), "200,100 800x500", "snapped again after a drag, it still comes back to what it had before the first snap")

-- A window given a size by hand is its own size: nothing to give back.
snap_left()
win.at, win.size = { x = 300, y = 200 }, { x = 700, y = 400 }
executed = {}
o.window_down()
eq(box(win) .. " " .. #executed, "300,200 700x400 1", "a window resized by hand since is minimized, not resized")

-- The bar docks while a window is maximized, which moves the top of the
-- area by its margin. A window snapped then is still on its half, and takes
-- the half as it is once the bar floats again.
win.at, win.size = { x = 200, y = 100 }, { x = 800, y = 500 }
monitors[1].reserved.top = 26
snap_left()
eq(box(win), "12,68 621x720", "snapped under the docked bar")
monitors[1].reserved.top = 31
fire("window.fullscreen", win)
eq(box(win), "12,73 621x715", "the half follows the bar when it floats again")
snap_right()
eq(box(win), "200,100 800x500", "and the window on it still comes back to what it had")
monitors[1].reserved.top = 26
snap_left()
monitors[1].reserved.top = 31
snap_right()
eq(box(win), "200,100 800x500", "a half the bar has moved away from is still the half the window is on")

-- With a monitor on that side the window goes on to it, onto the half it
-- enters by, and what it comes back to moves with it.
second_monitor = true
monitor_workspace.RIGHT = workspace
win.at, win.size = { x = 200, y = 100 }, { x = 800, y = 500 }
snap_right()
snap_right()
eq(win.monitor.name .. " " .. box(win), "RIGHT 1292,73 941x995", "from the right half: the left half of the monitor on the right")
snap_right()
eq(box(win), "1480,100 800x500", "and Super+Right there: the place it had, on the monitor it is on")
second_monitor = false
win.monitor = monitors[1]

-- A dialog keeps the size its app gave it, and a tiling workspace keeps the
-- keys for the focus.
local ask = open("ask", { floating = true, monitor = monitors[1], at = { x = 400, y = 300 }, size = { x = 300, y = 200 } })
snap_left()
eq(box(ask), "400,300 300x200", "a dialog is not snapped")

o.workspace_mode({ workspace = "2", mode = "dwindle" })
workspace = { id = 2 }
local float = open("float", { floating = true, monitor = monitors[1], at = { x = 100, y = 100 }, size = { x = 400, y = 300 }, tags = { o.FLOAT_RULE_TAG .. "*" } })
snap_left()
focus_left()
eq(box(float) .. " " .. moved, "100,100 400x300 1", "on a tiling workspace Super+Left moves the focus and snaps nothing")

-- A window that opens while the screensaver shows (D-179) goes to the
-- workspace its monitor was showing, not the screensaver's, and leaves the
-- keyboard to the screensaver, which stays up; it gets the keyboard once the
-- screensaver is gone. So does a window that asked for it meanwhile.
local saver_rule
for _, rule in ipairs(static_rules) do
  if rule.match and rule.match.workspace == "n[s:special:screensaver]" then
    saver_rule = rule
  end
end
eq(saver_rule ~= nil and saver_rule.workspace, "m+0 silent", "a window opening on the screensaver's workspace goes to the one its monitor shows")
eq(saver_rule.no_initial_focus, true, "without the keyboard")
eq(saver_rule.match.class, "negative:^(org\\.karchy\\.screensaver)$", "and the screensaver itself is left where the launcher put it")
local saver_tagged = false
for _, rule in ipairs(static_rules) do
  if rule.match and rule.match.class == "org.karchy.screensaver" and rule.tag == "+screensaver" then
    saver_tagged = true
  end
end
eq(saver_tagged, true, "the screensaver is tagged for the config to know it")

o.fullscreen_game = o.fullscreen_game or function() return false end
require("default.hypr.activation")
reset()
workspace = { id = 1 }
local screensaver_workspace = { id = -98, name = "special:screensaver-LEFT", special = true, visible = true }

-- Hyprland gives a window the rule opens without focus no keyboard and puts
-- it last in the focus history (seen in VM clip); the stand-in focuses every
-- window it opens, so the keyboard is handed back.
local function open_under_screensaver(address, fields)
  local keyboard = history[1]
  local window = open(address, fields)
  focus((find(keyboard)), 0)
  table.remove(history, 2)
  table.insert(history, address)
  return window
end
local function close(window)
  table.remove(stack, select(2, find(window.address)))
  for index, address in ipairs(history) do
    if address == window.address then
      table.remove(history, index)
    end
  end
  fire("window.close", window)
end

local left = open("left")
fire("window.urgent", left)
eq(history[1], "left", "a window that asks for the keyboard gets it")
local other = open("other")
local saver = open("saver", { floating = true, fullscreen = 2, workspace = screensaver_workspace, tags = { "screensaver*" } })
fire("window.urgent", left)
eq(history[1], "saver", "while the screensaver shows, a window that asks for the keyboard leaves it to the screensaver")
close(saver)
eq(history[1], "left", "and gets it once the screensaver is gone")

saver = open("saver", { floating = true, fullscreen = 2, workspace = screensaver_workspace, tags = { "screensaver*" } })
local late = open_under_screensaver("late")
eq(history[1], "saver", "a window that opens while the screensaver shows leaves it the keyboard")
close(saver)
eq(history[1], "late", "and gets it once the screensaver is gone: the newest one")

saver = open("saver", { floating = true, fullscreen = 2, workspace = screensaver_workspace, tags = { "screensaver*" } })
local saver_right = open("saver-right", { floating = true, fullscreen = 2, workspace = { id = -97, name = "special:screensaver-RIGHT", special = true }, tags = { "screensaver*" } })
-- The launcher hands the keyboard back to the monitor that had it.
focus(saver, 0)
local later = open_under_screensaver("later")
close(saver_right)
eq(history[1], "saver", "while one monitor's screensaver is still up, nothing moves")
close(saver)
eq(history[1], "later", "once both are gone the newest window gets the keyboard")

saver = open("saver", { floating = true, fullscreen = 2, workspace = screensaver_workspace, tags = { "screensaver*" } })
close(saver)
eq(history[1], "later", "a screensaver that ends with nothing new leaves the keyboard to Hyprland")

close(later)
fire("window.urgent", other)
eq(history[1], "other", "with no screensaver a window that asks for the keyboard gets it again")

print(string.format("window-stacking: %d checks passed", checks))
