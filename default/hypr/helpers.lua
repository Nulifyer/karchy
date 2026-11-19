-- Shared helpers for Hyprland Lua configuration.

local paths = require("default.hypr.paths")

o = o or {}

local function shell_quote(value)
  return "'" .. tostring(value):gsub("'", "'\\''") .. "'"
end

o.shell_quote = shell_quote

local function file_exists(path)
  local file = io.open(path, "r")
  if file then
    file:close()
    return true
  end

  return false
end

-- Hyprland reaps its own children, so os.execute() can't retrieve an exit status
-- from inside the compositor. Read a marker off stdout instead.
function o.shell_succeeds(command)
  -- Subshell, so the redirection covers every command rather than binding to
  -- the last one and letting an earlier one write its own OK into the pipe.
  local pipe = io.popen("( " .. command .. " ) >/dev/null 2>&1 && echo OK")
  if not pipe then
    return false
  end

  local output = pipe:read("*a") or ""
  pipe:close()

  return output:find("OK", 1, true) ~= nil
end

function o.cmd_present(command)
  if command:find("/", 1, true) then
    return file_exists(command)
  end

  local path = os.getenv("PATH") or "/usr/local/bin:/usr/bin"
  for directory in (path .. ":"):gmatch("([^:]*):") do
    if file_exists((directory ~= "" and directory or ".") .. "/" .. command) then
      return true
    end
  end

  return false
end

function o.cmd_missing(command)
  return not o.cmd_present(command)
end

-- The global shortcuts the shell registers, read from the same list it reads.
local shell_shortcuts = nil

local function shell_shortcut_registered(name)
  if not shell_shortcuts then
    shell_shortcuts = {}
    local file = io.open(paths.karchy_path .. "/default/karchy/shortcuts", "r")
    if file then
      for line in file:lines() do
        local kind, target = line:match("^(%a+)%s+(%S+)%s*$")
        if kind then
          shell_shortcuts[kind .. "." .. target] = true
        end
      end
      file:close()
    end
  end

  return shell_shortcuts[name] == true
end

-- Reach the shell through its global shortcut when it registers one, so the
-- keypress spawns nothing. Anything else runs the command as before.
local function shell_dispatcher(kind, target, command)
  local name = kind .. "." .. target
  if shell_shortcut_registered(name) then
    return hl.dsp.global("karchy:" .. name)
  end

  return command
end

local function command_from(value, description)
  if type(value) ~= "table" then
    return value
  end

  if value.karchy then
    return "karchy-launch-" .. value.karchy
  elseif value.menu then
    return shell_dispatcher("menu", value.menu, "karchy-menu toggle " .. shell_quote(value.menu))
  elseif value.panel then
    return shell_dispatcher("panel", value.panel, "karchy-shell shell toggle " .. shell_quote(value.panel))
  elseif value.audio then
    return shell_dispatcher("audio", value.audio, "karchy-audio-output-volume " .. shell_quote(value.audio))
  elseif value.brightness then
    local step = value.brightness == "raise" and "+5%" or "5%-"
    return shell_dispatcher("brightness", value.brightness, "karchy-brightness-display " .. step)
  elseif value.ipc then
    local target, method = value.ipc:match("^([^.]+)%.(.+)$")
    return shell_dispatcher("ipc", value.ipc, "karchy-shell " .. shell_quote(target) .. " " .. shell_quote(method))
  elseif value.focus and value.launch then
    return o.launch_sole(value.focus, value.launch)
  elseif value.launch then
    return o.launch(value.launch)
  elseif value.webapp then
    if value.focus then
      return o.launch_webapp_sole(description, value.webapp)
    else
      return o.launch_webapp(value.webapp)
    end
  elseif value.tui then
    if value.focus then
      return "karchy-launch-or-focus-tui " .. shell_quote(value.tui)
    else
      return "karchy-launch-tui " .. shell_quote(value.tui)
    end
  end

  return value
end

function o.preinstalled_bindings_enabled()
  if _G.karchy_preinstalled_bindings ~= nil then
    return _G.karchy_preinstalled_bindings == true
  end

  return not file_exists((os.getenv("HOME") or "") .. "/.local/state/karchy/preinstalls-removed")
end

-- What a bind runs, in words for the keybinding list (Settings ›
-- Keybindings): the command, "menu=root" for a shell target, or the command
-- or expression a function stands for.
local function describe_dispatcher(value)
  if type(value) == "string" then
    return value
  elseif type(value) == "table" then
    for _, kind in ipairs({ "menu", "panel", "ipc", "audio", "brightness", "karchy", "launch", "webapp", "tui" }) do
      if value[kind] then return kind .. "=" .. tostring(value[kind]) end
    end
    return ""
  end
  return o.bind_commands[value] or o.bind_expressions[value] or ""
end

-- Binds keys to an action. `description` is the action's name: it is what the
-- keybinding list shows, and what a change made in Settings refers to, so two
-- different actions must not share one. karchy/hypr/keys.lua records
-- the call and the layer it came from.
function o.bind(keys, description, dispatcher, options)
  local opts = options or {}

  if description then
    opts.description = description
  end

  o.bind_what = describe_dispatcher(dispatcher)
  dispatcher = command_from(dispatcher, description)

  if type(dispatcher) == "string" then
    dispatcher = hl.dsp.exec_cmd(dispatcher)
  end

  hl.bind(keys, dispatcher, opts)
  o.bind_what = nil
end

-- Names the part of the keybinding list ("Windows", "Media") that the binds
-- after it belong to, up to the next call or the end of the file.
function o.bind_group(name)
  local keybindings = package.loaded["karchy.hypr.keys"]
  if keybindings then keybindings.set_group(name) end
end

function o.rebind(keys, description, dispatcher, options)
  hl.unbind(keys)
  o.bind(keys, description, dispatcher, options)
end

function o.launch(command)
  return "uwsm-app -- " .. command
end

-- The command each function bind stands for: what Settings › Keybindings
-- shows and searches for a bind that Hyprland only reports as Lua.
o.bind_commands = {}

-- The Lua expression each function bind stands for, for binds with no command
-- to name instead.
o.bind_expressions = {}

-- Hand the launcher the focused window's pid, which it would otherwise ask
-- Hyprland for, to open the new terminal in that terminal's directory.
function o.launch_terminal()
  local function launch()
    local window = hl.get_active_window()
    if window and window.pid then
      hl.exec_cmd("karchy-launch-terminal --pid=" .. window.pid)
    else
      hl.exec_cmd("karchy-launch-terminal")
    end
  end

  o.bind_commands[launch] = "karchy-launch-terminal"
  return launch
end

function o.exec_on_start(command)
  hl.on("hyprland.start", function()
    hl.exec_cmd(command)
  end)
end

function o.launch_on_start(command)
  o.exec_on_start(o.launch(command))
end

function o.launch_webapp(url)
  return "karchy-launch-webapp " .. shell_quote(url)
end

function o.launch_webapp_sole(name, url)
  return "karchy-launch-or-focus-webapp " .. shell_quote(name) .. " " .. shell_quote(url)
end

function o.launch_sole(match, command)
  return "karchy-launch-or-focus " .. shell_quote(match) .. " " .. shell_quote(o.launch(command))
end

function o.bind_toggle(keys, description, toggle, options)
  o.bind(keys, description, "karchy-toggle-" .. toggle, options)
end

-- Bind one action to a key's press and another to its release, as for
-- push-to-talk. Hyprland skips a plain release bind once another key or mouse
-- button is released during the hold, or once the modifiers have changed, so
-- typing while holding the key would never run the release. The release half
-- here is transparent and ignores modifiers, and runs only after its own press
-- did, so letting go of the key without the rest of the chord does nothing. It
-- is also non-consuming: a release bind that ignores modifiers would otherwise
-- take the key from apps whenever it is pressed with other modifiers, such as
-- Shift+F9, or without them, such as a plain x for SUPER + X.
function o.bind_hold(keys, press_description, press, release_description, release, options)
  local held = false
  press, release = command_from(press, press_description), command_from(release, release_description)

  local function run(dispatcher)
    if type(dispatcher) == "string" then
      hl.exec_cmd(dispatcher)
    elseif type(dispatcher) == "function" then
      dispatcher()
    else
      hl.dispatch(dispatcher)
    end
  end

  local function on_press()
    held = true
    run(press)
  end

  local function on_release()
    if held then
      held = false
      run(release)
    end
  end

  if type(press) == "string" then
    o.bind_commands[on_press] = press
  end
  if type(release) == "string" then
    o.bind_commands[on_release] = release
  end

  local press_options, release_options = {}, {}
  for key, value in pairs(options or {}) do
    press_options[key], release_options[key] = value, value
  end
  -- Options that change when the press half fires would break the release half.
  for _, key in ipairs({ "repeating", "long_press", "click", "drag" }) do
    release_options[key] = nil
  end
  release_options.release, release_options.transparent = true, true
  release_options.ignore_mods, release_options.non_consuming = true, true

  o.bind(keys, press_description, on_press, press_options)
  o.bind(keys, release_description, on_release, release_options)
end

-- icon: an optional name from default/karchy/icons.json, shown on the toast.
function o.notify(message, icon)
  local glyph = icon and ("-g " .. shell_quote(icon) .. " ") or ""
  return "karchy-notification-send -u low " .. glyph .. shell_quote(message)
end

-- What makes apps float on their own account, so a floating workspace can
-- leave their floating to them: the class and title patterns of rules that
-- float them, the tags rules float, and the patterns of rules that tag them.
o.floating_apps = { class = {}, title = {}, tags = {}, tagged = {} }
-- Helpers reload before workspace modes, so discard the previous config's hook.
o.floating_apps_changed = nil

function o.window(match, rules)
  local floating_changed = false
  rules.match = rules.match or {}

  if type(match) == "string" then
    rules.match.class = match
  else
    for key, value in pairs(match) do
      rules.match[key] = value
    end
  end

  if rules.float == true then
    -- Only a rule floating a tag alone floats everything with that tag; one
    -- that also names a class or title floats just those, recorded below.
    if type(rules.match.tag) == "string" and rules.match.class == nil and rules.match.title == nil then
      o.floating_apps.tags[rules.match.tag] = true
      floating_changed = true
    end
    for _, key in ipairs({ "class", "title" }) do
      if type(rules.match[key]) == "string" then
        table.insert(o.floating_apps[key], rules.match[key])
        floating_changed = true
      end
    end
  end

  if type(rules.tag) == "string" and rules.tag:sub(1, 1) == "+" then
    local tag = rules.tag:sub(2)
    o.floating_apps.tagged[tag] = o.floating_apps.tagged[tag] or {}
    for _, key in ipairs({ "class", "title" }) do
      if type(rules.match[key]) == "string" then
        table.insert(o.floating_apps.tagged[tag], { key = key, pattern = rules.match[key] })
        floating_changed = true
      end
    end
  end

  hl.window_rule(rules)
  if floating_changed and o.floating_apps_changed then
    o.floating_apps_changed()
  end
end

-- Whether a window carries a tag. Hyprland reports a tag set by a rule as
-- "<tag>*" and one set by the tag dispatcher as "<tag>".
function o.window_tagged(window, tag)
  for _, name in ipairs(window and window.tags or {}) do
    if name == tag or name == tag .. "*" then
      return true
    end
  end

  return false
end

-- Opt a window in to Karchy's standard active/inactive transparency. The tag
-- lets Appearance > Windows > Window Opacity turn these windows opaque or glassy.
function o.transparent_window(match, opacity)
  o.window(match, { opacity = opacity or "0.985 0.96", tag = "+transparent-window" })
end
