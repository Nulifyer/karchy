-- Which window is in front, and where Alt+Tab goes (D-159): karchy's real
-- default/hypr/stacking.lua, window-switch.lua and workspace-modes.lua under a
-- stand-in for Hyprland's `hl` that keeps the windows' stacking order and
-- focus history the way Hyprland does.
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
    end
  end,
  focus = function(args)
    local window = args.window and selected(args.window)
    if window then
      focus(window, 4)
    end
  end,
  fullscreen = function(args)
    local window = args.window and selected(args.window) or (find(history[1]))
    if window then
      window.fullscreen = args.action == "unset" and 0 or (args.mode == "maximized" and 1 or 2)
    end
  end,
}

local function action(kind)
  return function(args) return { kind = kind, args = args or {} } end
end

hl = setmetatable({
  dsp = setmetatable({
    focus = action("focus"),
    window = setmetatable({ alter_zorder = action("zorder"), tag = action("tag"), bring_to_top = action("none"), fullscreen = action("fullscreen") }, {
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
  get_windows = function() return { table.unpack(stack) } end,
  get_workspace_windows = function() return { table.unpack(stack) } end,
  get_active_window = function() return (find(history[1])) end,
  get_active_workspace = function() return workspace end,
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
local workspace_modes = require("default.hypr.workspace-modes")
o.OVER_GAME_TAG = "karchy-over-game"
require("default.hypr.stacking")

local ALT, RELEASED = 64, 0
local next_window, previous_window = o.switch_window(1), o.switch_window(-1)

-- Alt+Tab swaps the two windows used last, however many are open.
local a, b, c, d = open("a"), open("b"), open("c"), open("d")
next_window()
fire("input.keyboard.key", ALT, 0, RELEASED)
eq(history[1], "c", "Alt+Tab goes to the window used before this one")
next_window()
fire("input.keyboard.key", ALT, 0, RELEASED)
eq(history[1], "d", "and back with one more press")

-- With Alt held each press goes one further back, Shift+Tab forward again.
next_window()
next_window()
next_window()
eq(history[1], "a", "three presses with Alt held go three windows back")
previous_window()
eq(history[1], "b", "Shift+Tab goes one forward again")
eq(#handlers["input.keyboard.key"], 1, "the key release is watched during a walk")
fire("input.keyboard.key", ALT, 0, RELEASED)
eq(history[1] .. history[2], "bd", "after the walk the window it left is second")
eq(#handlers["input.keyboard.key"], 0, "and no key is watched once the walk is over")

-- A walk broken off by a click starts again from the windows as they are.
next_window()
focus(a, 48)
next_window()
eq(history[1], "d", "a click ends the walk; the next press goes back from the clicked window")
fire("input.keyboard.key", ALT, 0, RELEASED)

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

print(string.format("window-stacking: %d checks passed", checks))
