-- Games. A fullscreen game holds idle off and keeps the keyboard, and other
-- windows open above it.
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

local workspace_modes = require("default.hypr.workspace-modes")

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

-- Other windows beside a fullscreen game, the way a borderless game behaves
-- on Windows (user 2026-11-22):
--   - a window that opens on the game's workspace floats above the game, with
--     the keyboard. The game keeps its fullscreen and its size; Hyprland's own
--     answer (misc.on_focus_under_fullscreen = 1) hands the fullscreen to the
--     new window and squeezes the game into a tile.
--   - click the game and it is in front again: the windows above it go behind
--     it, still open. Focus one of them (the keyboard, the bar) and it comes
--     back above.
--   - while this lasts the workspace focuses on click, not on hover, or
--     leaving a window with the pointer would hide it.
--   - when the game leaves fullscreen or closes, the windows this floated
--     tile again, as does one carried to another workspace.
-- Apps with float rules of their own and modal dialogs float anyway and are
-- left alone, as on a floating workspace (workspace-modes.lua).
local OVER_RULE = "karchy-over-game-"
-- On a window through the rule, so it goes when the rule is turned off.
local OVER_TAG = "karchy-over-game"
-- On a window this floated, until it tiles again.
local FLOATED_TAG = "karchy-game-floated"

local over = {} -- workspace id -> true while its rule is on
local update_input = workspace_modes.click_to_focus(function(workspace)
  return over[tostring(workspace.id)] == true
end)

local function games_by_workspace()
  local found = {}
  for _, window in ipairs(hl.get_windows()) do
    local id = window.workspace and tonumber(window.workspace.id)
    if id and id >= 1 and o.fullscreen_game(window) then
      found[tostring(id)] = window
    end
  end
  return found
end

-- Windows this floated that no longer sit beside a fullscreen game tile again.
-- One a floating workspace also floated stays as that mode has it.
local function settle(games)
  for _, window in ipairs(hl.get_windows({ tag = FLOATED_TAG })) do
    local id = window.workspace and tostring(window.workspace.id)
    if not (id and games[id]) then
      hl.dispatch(hl.dsp.window.tag({ tag = "-" .. FLOATED_TAG, window = window }))
      if window.floating and (window.fullscreen or 0) == 0 and not o.window_tagged(window, workspace_modes.FLOATED_TAG) then
        hl.dispatch(hl.dsp.window.float({ action = "off", window = window }))
      end
    end
  end
end

local function sync()
  local games = games_by_workspace()

  for id in pairs(games) do
    if not over[id] then
      over[id] = true
      hl.window_rule({
        name = OVER_RULE .. id,
        enabled = true,
        match = workspace_modes.not_floating_on_their_own({ workspace = id, modal = false }),
        float = true,
        size = workspace_modes.OPEN_WIDTH .. " " .. workspace_modes.OPEN_HEIGHT,
        center = true,
        tag = "+" .. OVER_TAG,
      })
    end
  end

  for id in pairs(over) do
    if not games[id] then
      over[id] = nil
      hl.window_rule({ name = OVER_RULE .. id, enabled = false })
    end
  end

  settle(games)
  update_input()
end

-- The change an event tells of is still being made when it fires.
local function sync_soon()
  hl.timer(sync, { type = "oneshot", timeout = 1 })
end

hl.on("window.fullscreen", sync_soon)
hl.on("window.close", sync_soon)
hl.on("window.move_to_workspace", sync_soon)

-- The rule's tag leaves with the rule, so what it floated is marked for good
-- as it opens.
hl.on("window.open", function(window)
  if o.window_tagged(window, OVER_TAG) and not o.fullscreen_game(window) then
    hl.dispatch(hl.dsp.window.tag({ tag = "+" .. FLOATED_TAG, window = window }))
  end
end)

hl.on("window.active", function(window)
  if not (window and window.mapped) then
    return
  end

  local id = window.workspace and window.workspace.id
  if not (id and over[tostring(id)]) then
    return
  end

  if o.fullscreen_game(window) then
    -- The game is in front again. Its own windows (a launcher's dialog) stay.
    for _, other in ipairs(hl.get_workspace_windows(tostring(id))) do
      if other.address ~= window.address and other.floating and other.allowed_over_fullscreen and other.pid ~= window.pid then
        hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom", window = other }))
      end
    end
  elseif window.floating and not window.allowed_over_fullscreen then
    hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", window = window }))
  end
end)

-- A config reload starts this file again with the windows already open.
sync()
