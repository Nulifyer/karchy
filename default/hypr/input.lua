-- https://wiki.hypr.land/Configuring/Basics/Variables/#input

local keyboard = require("default.hypr.keyboard")

-- Caps Lock is Caps Lock, and Shift + Caps Lock is the compose key (see
-- keyboard.xkb). Settings › Input can choose another compose key.
local xkb = keyboard.xkb("karchy:shift_caps_compose")

hl.config({
  input = {
    kb_layout = xkb.layout,
    kb_variant = xkb.variant,
    kb_model = "",
    kb_options = xkb.options,
    kb_rules = "",
    follow_mouse = 1,
    sensitivity = 0,

    repeat_rate = 40,
    repeat_delay = 250,
    numlock_by_default = true,

    touchpad = {
      natural_scroll = false,
      clickfinger_behavior = true,
      scroll_factor = 0.4,
    },
  },

  misc = {
    key_press_enables_dpms = true,
    mouse_move_enables_dpms = true,
  },
})

-- Scroll nicely in the terminal. TUIs launched under their own app-id
-- (org.karchy.agent in the console, org.karchy.btop, TUI.float, ...) no longer
-- carry the terminal's class, but their initial title is still the terminal's
-- name, so they are matched by that to scroll at the same rate.
local function terminal_scroll(class, title, factor)
  o.window(class, { scroll_touchpad = factor })
  o.window({ class = "(org\\.karchy\\..*|TUI\\..*)", initial_title = title }, { scroll_touchpad = factor })
end

terminal_scroll("(Alacritty|kitty)", "(Alacritty|kitty)", 1.5)
-- foot only applies its scrollback multiplier to wheel clicks, not precise touchpad scrolling.
terminal_scroll("foot", "foot", 2.0)
terminal_scroll("com.mitchellh.ghostty", "Ghostty", 0.2)
