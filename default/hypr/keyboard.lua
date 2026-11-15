-- The keyboard layout picked at install time. The installer and first-boot
-- setup persist it to /etc/vconsole.conf, so Hyprland reads it from there
-- instead of rewriting every user's config.

local keyboard = {}

local function read_values(path)
  local values = {}
  local file = io.open(path, "r")
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

function keyboard.selected()
  local paths = require("default.hypr.paths")
  local values = read_values(paths.config_home .. "/karchy/keyboard-layouts")
  if values.XKBLAYOUT then return values end
  return keyboard.installed()
end

function keyboard.vconsole()
  return read_values("/etc/vconsole.conf")
end

-- Choices whose console keymap is plain US but whose desktop layout is not:
-- Korean keeps US letters, and Lao is non-Latin, so US still leads. Korean
-- installs take kr104, which adds Right Alt and Right Ctrl as 한/영 and 한자;
-- plain kr is what earlier installs saved.
local desktop_overrides = { kr = true, ["kr:kr104"] = true, la = true }

function keyboard.installed()
  local values = keyboard.vconsole()
  local override = read_values("/etc/karchy/input-method").XKB_LAYOUT
  if desktop_overrides[override]
    and (values.XKBLAYOUT or "us") == "us"
    and (values.XKBVARIANT or "") == "" then
    values.XKBLAYOUT, values.XKBVARIANT = override:match("^([^:]*):?(.*)$")
  end
  return values
end

-- Japanese (JIS) keyboards put +, ^, and the Henkan/Muhenkan keys where US
-- keyboards don't, so a few defaults only apply when that layout leads.
function keyboard.jis()
  local layout = keyboard.selected().XKBLAYOUT or "us"
  return layout:match("^[^,]*") == "jp"
end

-- Layouts that can't type Latin letters. Keep in sync with the list in
-- etc/mkinitcpio.conf.d/karchy_hooks.conf.
local non_latin_layouts =
  " af am ara bd bg by et ge gr il in iq ir kg kh kz la lk mk mm mn mv np rs ru sy th tj ua "
-- us variants that can't type Latin letters either: Russian phonetic and Cherokee.
local non_latin_us_variants = " chr rus "

-- The desktop's XKB layout, variant and options. compose is the compose-key
-- option: karchy's default is "karchy:shift_caps_compose" (Caps Lock is Caps
-- Lock, Shift + Caps Lock is compose; stock XKB has no such option, so karchy
-- defines it in /etc/xkb). Settings › Input passes another, or "" for none,
-- and keeps the layout-switching option this adds for non-Latin layouts.
function keyboard.xkb(compose)
  local vconsole = keyboard.selected()

  local kb_layout = vconsole.XKBLAYOUT or "us"
  local kb_variant = vconsole.XKBVARIANT or ""
  local kb_options = compose or ""

  -- Hyprland resolves keybindings against the first entry in kb_layout, not the
  -- layout that's currently active, so Karchy's Latin-keysym bindings (SUPER + W
  -- and friends) only fire when a Latin layout leads. Installing with a non-Latin
  -- one would otherwise leave the desktop unusable.
  if non_latin_layouts:find(" " .. kb_layout:match("^[^,]*") .. " ", 1, true) then
    -- Variants pair with layouts by position. A list that already names us (as in
    -- "ru,us") moves that entry and its variant to the front rather than gaining a
    -- second us, which would make the toggle cycle through a duplicate.
    local layouts, variants = {}, {}
    for layout in (kb_layout .. ","):gmatch("([^,]*),") do
      layouts[#layouts + 1] = layout
    end
    for variant in (kb_variant .. ","):gmatch("([^,]*),") do
      variants[#variants + 1] = variant
    end

    local us_variant = ""
    for i, layout in ipairs(layouts) do
      if layout == "us" and not non_latin_us_variants:find(" " .. (variants[i] or "") .. " ", 1, true) then
        us_variant = variants[i] or ""
        table.remove(layouts, i)
        if variants[i] then table.remove(variants, i) end
        break
      end
    end

    table.insert(layouts, 1, "us")
    table.insert(variants, 1, us_variant)
    kb_layout = table.concat(layouts, ",")
    kb_variant = table.concat(variants, ",")
    -- Reach the original layout with Left Alt + Right Alt.
    kb_options = kb_options .. (kb_options == "" and "" or ",") .. "grp:alts_toggle"
  end

  -- Saved selections already include their Latin-leading layout. Keep the
  -- installer's layout-switching shortcut when a non-Latin layout remains.
  if not kb_options:find("grp:alts_toggle", 1, true) then
    for layout in kb_layout:gmatch("[^,]+") do
      if non_latin_layouts:find(" " .. layout .. " ", 1, true) then
        kb_options = kb_options .. (kb_options == "" and "" or ",") .. "grp:alts_toggle"
        break
      end
    end
  end

  return { layout = kb_layout, variant = kb_variant, options = kb_options }
end

return keyboard
