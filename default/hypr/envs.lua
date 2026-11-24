local paths = require("default.hypr.paths")
local require_optional = require("default.hypr.require_optional")

-- GUM environment variables for styling purposes.
require_optional.module("karchy.current.theme.gum_env")

-- Cursor size.
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")

-- Force all apps to use Wayland.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("OZONE_PLATFORM", "wayland")
hl.env("XDG_SESSION_TYPE", "wayland")

-- GTK 4 apps draw with OpenGL (D-170). GTK 4.16 and newer pick the Vulkan
-- renderer by itself, which on NVIDIA leaves windows blank or crashing, and on
-- AMD made scrolling a long list stutter (Mission Center's Apps and Services
-- pages on a Framework 13 AMD, smooth with this set). To choose another
-- renderer, set GSK_RENDERER with hl.env in your Hyprland config, which loads
-- after this.
hl.env("GSK_RENDERER", "gl")

-- Allow better support for screen sharing (Google Meet, Discord, etc).
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")

-- Use XCompose file.
hl.env("XCOMPOSEFILE", paths.home .. "/.XCompose")

-- hyprctl setenv doesn't reach keybind dispatcher env; use hl.env.
hl.env("KARCHY_PATH", paths.karchy_path)

local bin_dir = paths.karchy_path .. "/bin"
local kept = {}
for entry in (os.getenv("PATH") or "/usr/local/bin:/usr/bin"):gmatch("[^:]+") do
  if entry ~= bin_dir then table.insert(kept, entry) end
end
table.insert(kept, 1, bin_dir)
hl.env("PATH", table.concat(kept, ":"))

-- Hardware-specific environment.
require("default.hypr.nvidia")

require("default.hypr.xwayland-scale")

-- X11 apps draw at the monitor's real pixels (sharp, not stretched) and are
-- told the scale through Xft.dpi: default/hypr/xwayland-scale.lua.
hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },
})
