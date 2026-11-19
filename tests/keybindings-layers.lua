-- Loads karchy's real binding files under a stand-in for Hyprland's `hl`,
-- with a Settings layer and a bindings.lua of the test's own, and publishes
-- the record as Hyprland would. tests/keybindings.py compares it with what
-- the stand-in ended up with bound and with what the command predicts.
-- Run by that test: KARCHY_PATH, HOME, XDG_STATE_HOME and XDG_RUNTIME_DIR
-- point into a temporary folder.
local repo, home = os.getenv("KARCHY_PATH"), os.getenv("HOME")

local live = {} -- what is bound, in order: { keys, description }
local function dispatcher(path)
  return setmetatable({}, {
    __index = function(_, key) return dispatcher(path .. "." .. tostring(key)) end,
    __call = function() return setmetatable({}, { __tostring = function() return "HL.Dispatcher(" .. path .. ")" end }) end,
  })
end
local function nothing() return nil end

hl = setmetatable({
  dsp = dispatcher("hl.dsp"),
  bind = function(keys, _, opts) live[#live + 1] = { keys, opts and opts.description or "" } end,
  unbind = function(keys)
    local keep, norm = {}, package.loaded["karchy.hypr.keys"].normalize(keys)
    for _, bound in ipairs(live) do
      if package.loaded["karchy.hypr.keys"].normalize(bound[1]) ~= norm then keep[#keep + 1] = bound end
    end
    live = keep
  end,
  timer = function(fn) fn() end,
  on = nothing,
  gesture = nothing,
  get_config = nothing,
}, { __index = function() return nothing end })

-- The module path as Hyprland has it: generated state first, then the
-- person's files, then karchy.
dofile(repo .. "/default/hypr/bootstrap.lua")
require("default.hypr.helpers")
local keybindings = require("karchy.hypr.keys")
o.workspaces = { focus = function() return function() end end, move_window = function() return function() end end, move_window_to_monitor = function() return function() end end }
require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("karchy.hypr.bindings")
keybindings.load_settings()
local user = io.open(home .. "/.config/hypr/bindings.lua", "r")
if user then
  user:close()
  dofile(home .. "/.config/hypr/bindings.lua")
end
keybindings.publish()

for _, bound in ipairs(live) do
  print(keybindings.normalize(bound[1]) .. "\t" .. bound[2])
end
