-- Hyprland, configured in Lua: https://wiki.hypr.land/Configuring/Start/
-- karchy created this file once; it is yours and updates never rewrite it.

-- Omarchy's bootstrap sets up module paths ($KARCHY_PATH is /usr/share/karchy,
-- or a dev checkout named in /etc/karchy.conf).
dofile(os.getenv("KARCHY_PATH") .. "/default/hypr/bootstrap.lua")

-- karchy's defaults: the Omarchy modules karchy keeps, plus karchy's bindings.
require("karchy.hypr.init")

-- Your overrides, loaded after the defaults so they win.
require("hypr.monitors")
require("hypr.input")
require("hypr.bindings")
require("hypr.looknfeel")
require("hypr.autostart")

-- Toggle flags (gaps, transparency, layouts) applied by the menu and shell.
require("default.hypr.toggles")
