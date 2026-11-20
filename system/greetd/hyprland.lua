-- karchy: the Hyprland that carries the login screen (D-130), and nothing
-- else. system/greetd/greeter starts it as the `greeter` user with
-- start-hyprland -- --config <this file>; greeter-session runs the screen in
-- it and ends it.
--
-- It can't use the desktop's config (default/hypr): that builds its paths
-- from a user's home. The keyboard layout below is therefore read here, from
-- the file the installer wrote and the desktop reads too
-- (default/hypr/keyboard.lua), so the password is typed in the layout it was
-- chosen in.

local function read_vconsole()
  local values = {}
  local file = io.open("/etc/vconsole.conf", "r")
  if not file then
    return values
  end
  for line in file:lines() do
    local key, value = line:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
    if key and value then
      value = value:gsub("%s+#.*$", "")
      value = value:gsub('^"(.*)"$', "%1")
      value = value:gsub("^'(.*)'$", "%1")
      values[key] = value
    end
  end
  file:close()
  return values
end

local vconsole = read_vconsole()

-- Scale 1 everywhere: the screen sizes itself by the display's height, as
-- the boot splash before it does (shell/greeter.qml).
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

hl.config({
  input = {
    kb_layout = vconsole.XKBLAYOUT or "us",
    kb_variant = vconsole.XKBVARIANT or "",
    -- The desktop's default compose key (default/hypr/input.lua: Shift +
    -- Caps Lock, from /etc/xkb), so a password chosen there with a composed
    -- character, such as é on a US keyboard, can be typed here. Without the
    -- option that password can't be entered at this screen at all. A compose
    -- key someone picked in Settings › Input is in their home and can't be
    -- read before they log in.
    kb_options = "karchy:shift_caps_compose",
    numlock_by_default = true,
    touchpad = {
      natural_scroll = true,
      clickfinger_behavior = true,
    },
  },

  -- The default theme's background (themes/nulifyer), so nothing flashes
  -- between the boot splash and the screen.
  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    background_color = "rgb(202020)",
    force_default_wallpaper = 0,
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },

  ecosystem = {
    no_update_news = true,
    no_donation_nag = true,
  },

  animations = {
    enabled = false,
  },

  -- Nothing here is an X11 app.
  xwayland = {
    enabled = false,
  },
})

hl.on("hyprland.start", function()
  hl.exec_cmd("/usr/lib/karchy/greeter-session")
end)
