-- Games. A fullscreen game holds idle off and keeps the keyboard.
--
-- A game played with a controller alone gives Hyprland no input, and not
-- every game asks for the screen to stay on, so the screen would lock and the
-- machine suspend in the middle of it. Hyprland holds idle off itself while
-- one of these windows is fullscreen on a workspace that is shown, and the
-- shell's idle timers follow Hyprland's inhibitors.
--
-- The `game` tag marks the windows:
--   steam_app_<id>  Steam's Proton games
--   gamescope       whatever runs inside it
--   <name>.exe      Wine outside Steam (Lutris, Heroic, Bottles), which names
--                   a window after its program
--   content "game"  a window that declares its content as a game
--                   (wp-content-type), or is given it by a `content` rule
-- Steam's own windows (class `steam`) are not games. Tag another game with
--   o.window("its-class", { tag = "+game" })

o.window("steam_app_.*", { tag = "+game" })
o.window("gamescope", { tag = "+game" })
o.window(".*\\.(exe|EXE)", { tag = "+game" })
o.window({ content = "game" }, { tag = "+game" })

o.window({ tag = "game" }, { idle_inhibit = "fullscreen" })

-- Whether the window is a game in fullscreen (maximized counts, as it does
-- for Hyprland's idle_inhibit). Such a window is not taken out of focus by a
-- window that asks for it (activation.lua).
function o.fullscreen_game(window)
  return window ~= nil and window.mapped and (window.fullscreen or 0) ~= 0 and o.window_tagged(window, "game")
end
