-- karchy's Hyprland composition (docs/architecture.md). It loads the vendored
-- Omarchy modules karchy keeps, in Omarchy's order, plus karchy's own
-- autostart and bindings. It replaces Omarchy's default/hypr/omarchy.lua,
-- which also loads the agent, dictation and app bindings karchy drops.
--
-- ~/.config/hypr/hyprland.lua requires this after Omarchy's bootstrap, then
-- loads the user's own files, which win over everything here.

require("default.hypr.helpers")
local require_optional = require("default.hypr.require_optional")

require("karchy.hypr.autostart")
require("default.hypr.monitor-workspaces")

-- Bindings: Omarchy's media keys and universal clipboard kept whole, then
-- karchy's own set (docs/keybindings.md).
require("default.hypr.bindings.media")
require("default.hypr.bindings.clipboard")
require("karchy.hypr.bindings")

-- Add-on packages (karchy's addons/) bring their own bindings and rules in
-- root-owned /usr/share/karchy/hypr.d, so they exist only while the package is
-- installed; karchy's pacman hooks reload Hyprland when they change.
do
  local handle = io.popen("find /usr/share/karchy/hypr.d -maxdepth 1 -type f -name '*.lua' 2>/dev/null | sort")
  if handle then
    for file in handle:lines() do dofile(file) end
    handle:close()
  end
end

require("default.hypr.envs")
require("default.hypr.looknfeel")
require("default.hypr.qconsole")
require("default.hypr.input")
require("default.hypr.windows")
require("default.hypr.pop")

require_optional.module("karchy.current.theme.hyprland")

-- Settings window choices (D-27), generated into ~/.local/state/karchy/hypr by
-- the karchy-settings-* commands. They load here, after karchy's defaults and
-- before the user's ~/.config/hypr files, so a hand-written rule always wins.
local paths = require("default.hypr.paths")
for _, name in ipairs({ "displays", "input", "power" }) do
  local file = paths.state_home .. "/karchy/hypr/" .. name .. ".lua"
  local handle = io.open(file, "r")
  if handle then
    handle:close()
    dofile(file)
  end
end
