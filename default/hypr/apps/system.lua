-- Floating windows.
o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })

-- Windows that are dealt with and closed. The image viewer, the video player
-- and the document viewer are not among them, nor are karchy's own windows
-- below: they are kept open and switched to, so they are app windows, which
-- tile on a tiling workspace (D-165, D-175). A floating window there would
-- sit in front of every tiled one.
o.window(
  "(org.karchy.btop|org.karchy.terminal|org.karchy.bash|org.codeberg.dnkl.foot|org.gnome.NautilusPreviewer|Karchy|About|TUI.float)",
  {
    tag = "+floating-window",
  }
)

-- The portal only ever shows dialogs — file pickers, screen shares, permission
-- prompts — so every one of its windows belongs in the floating treatment,
-- whatever the app that asked for it titled it.
o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
-- A portal dialog belongs to a window of another app, which Hyprland is not
-- told, so it stays in front of every other window on its workspace until it
-- is answered (stacking.lua), as a dialog stays in front of its own app.
o.window("xdg-desktop-portal-gtk", { tag = "+stay-in-front" })
o.window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

-- The About fastfetch layout needs more columns than the standard float provides.
-- karchy sizes the About window here; karchy-launch-about no longer measures it.
o.window("org.karchy.about", { float = true })
o.window("org.karchy.about", { center = true })
-- Height: the logo is 12 rows but the facts beside it decide: about 26 rows
-- with the title, the color blocks and the line that waits for a key, at 18 px
-- each plus foot's padding is 516 px. 560 leaves room for the rows a laptop or
-- a second disk adds; at 480 the first row (user@host) scrolled off.
o.window("org.karchy.about", { size = { 920, 560 } })

o.window("omacalc", { float = true })

-- karchy's own windows are shell windows (Quickshell's class), so they are
-- matched by title too. They are kept open and switched to, so they are app
-- windows (D-175): on a tiling workspace they tile, with a layout for the
-- width a tile gives them, and no float rule names them; on a floating one
-- they float at the size they give themselves (workspace-modes.lua).
-- Virtual machines and Containers are in vms.lua.
-- The sizes are the ones each window gives itself (its FloatingWindow).
o.own_size_window({ class = "^org.quickshell$", title = "^karchy Settings$", size = { 900, 680 } })
o.own_size_window({ class = "^org.quickshell$", title = "^Quick install$", size = { 1000, 740 } })
o.own_size_window({ class = "^org.quickshell$", title = "^Updates$", size = { 760, 640 } })

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
