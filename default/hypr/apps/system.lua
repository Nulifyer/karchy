-- Floating windows.
o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })

o.window(
  "(org.karchy.btop|org.karchy.terminal|org.karchy.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|org.gnome.Evince|Karchy|About|TUI.float|imv|mpv)",
  {
    tag = "+floating-window",
  }
)

-- The portal only ever shows dialogs — file pickers, screen shares, permission
-- prompts — so every one of its windows belongs in the floating treatment,
-- whatever the app that asked for it titled it.
o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
o.window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

-- The About fastfetch layout needs more columns than the standard float provides.
-- karchy sizes the About window here; karchy-launch-about no longer measures it.
o.window("org.karchy.about", { float = true })
o.window("org.karchy.about", { center = true })
o.window("org.karchy.about", { size = { 920, 480 } })

o.window("omacalc", { float = true })

-- karchy Settings is a shell window (Quickshell's class), so match its title.
-- It sizes itself to fit the screen it opens on.
o.window({ title = "^karchy Settings$" }, { float = true })
o.window({ title = "^karchy Settings$" }, { center = true })

-- Quick install is a shell window too. Tiled beside another window, its rows
-- and key hints are cut short.
o.window({ title = "^Quick install$" }, { float = true })
o.window({ title = "^Quick install$" }, { center = true })

-- The Updates window: every shell window floats at the size it gives itself
-- (Settings, Quick install, Virtual machines and Containers in vms.lua).
o.window({ class = "^org.quickshell$", title = "^Updates$" }, { float = true })
o.window({ class = "^org.quickshell$", title = "^Updates$" }, { center = true })

-- Fullscreen screensaver.
o.window("org.karchy.screensaver", { fullscreen = true })
o.window("org.karchy.screensaver", { float = true })
o.window("org.karchy.screensaver", { animation = "slide" })
-- The launcher picks each screensaver's workspace. A terminal mapped again as it closes lands out of sight instead,
-- where its fullscreen rule cannot take fullscreen from a window.
o.window("org.karchy.screensaver", { workspace = "special:screensaver silent" })

-- Popped window rounding.
o.window({ tag = "pop" }, { rounding = 8 })

-- Prevent idle while open.
o.window({ tag = "noidle" }, { idle_inhibit = "always" })
