-- karchy as a VM guest: the virtual display takes the size of the viewer's
-- window (D-174). Installed by karchy-vm into /usr/share/karchy/hypr.d, which
-- karchy/hypr/init.lua loads before Settings › Displays and the person's own
-- monitors.lua.
--
-- A viewer (virt-manager, remote-viewer, a SPICE or QEMU window) that changes
-- size makes the virtual GPU (virtio-gpu or QXL) announce a new preferred mode,
-- and the kernel sends a DRM hotplug event. Hyprland 0.57 ignores it: Aquamarine
-- reads a connected output's modes only when it connects, so "preferred" stays
-- the size the session started with, even across a reload. Here, a Virtual-N
-- output whose rule asks for the preferred mode gets the connector's live
-- preferred size from sysfs instead. /usr/lib/karchy-vm/display-watch calls
-- karchy_vm_display_follow() when the hotplug event comes; a reload calls it too.
--
-- The rule that decides is the one Hyprland would use (the last hl.monitor for
-- the output's name or description, else the catch-all ""), so a mode set by
-- hand in Settings › Displays or in ~/.config/hypr wins over the viewer, and
-- every other field of that rule (scale, position, transform) is kept.

-- Only in a guest. Its output, not its status: Hyprland reaps its children, so
-- os.execute can't see an exit status here.
do
  local handle = io.popen("systemd-detect-virt --vm 2>/dev/null")
  local virt = handle and handle:read("*l") or ""
  if handle then handle:close() end
  if virt == "" or virt == "none" then return end
end

local rules = {}
local monitor = hl.monitor

-- Every rule the config sets, in order, so the effective one can be found. Like
-- Hyprland, a rule for an output named before adds to that output's rule.
hl.monitor = function(rule)
  if type(rule) == "table" then
    local copy = {}
    for i = #rules, 1, -1 do
      if rules[i].output == rule.output then
        for key, value in pairs(rules[i]) do copy[key] = value end
        break
      end
    end
    for key, value in pairs(rule) do copy[key] = value end
    rules[#rules + 1] = copy
  end
  return monitor(rule)
end

local function effective_rule(output)
  for i = #rules, 1, -1 do
    local name = rules[i].output
    if name == output.name then return rules[i] end
    if type(name) == "string" and name:sub(1, 5) == "desc:" then
      local desc = name:sub(6):match("^%s*(.-)%s*$")
      local short = output.description or ""
      local full = (output.serial or "") ~= "" and short .. " " .. output.serial or short
      if short:sub(1, #desc) == desc or full:sub(1, #desc) == desc then return rules[i] end
    end
  end
  for _, rule in ipairs(rules) do
    if rule.output == "" then return rule end
  end
  return {}
end

-- The connector's preferred mode, which the kernel lists first, and its sysfs
-- name (card1-Virtual-1).
local function preferred_size(name)
  local handle = io.popen("grep -H -m1 . /sys/class/drm/card*-" .. name .. "/modes 2>/dev/null")
  if not handle then return nil end
  local first = handle:read("*l")
  handle:close()
  local connector, width, height = (first or ""):match("^/sys/class/drm/([^/]+)/modes:(%d+)x(%d+)")
  if not width then return nil end
  return tonumber(width), tonumber(height), connector
end

-- Hyprland's automatic scale (CMonitor::getDefaultScale), worked out from the
-- physical size the display reports now, in its EDID's first detailed timing:
-- Hyprland keeps the size the display reported when it connected, so for it a
-- bigger window would mean more pixels per inch and bigger text. Without an
-- EDID (QXL has none), 1: Hyprland divides by a size of zero there and picks 2.
local function auto_scale(name, width, height)
  local handle = io.open(name and ("/sys/class/drm/" .. name .. "/edid") or "", "rb")
  local edid = handle and handle:read("a") or ""
  if handle then handle:close() end
  if #edid >= 72 then
    local mm_w = edid:byte(67) | ((edid:byte(69) & 0xf0) << 4)
    local mm_h = edid:byte(68) | ((edid:byte(69) & 0x0f) << 8)
    if mm_w > 0 and mm_h > 0 then
      local ppi = math.sqrt(width ^ 2 + height ^ 2) / math.sqrt((mm_w / 25.4) ^ 2 + (mm_h / 25.4) ^ 2)
      if ppi > 200 then return 2 elseif ppi > 140 then return 1.5 end
    end
  end
  return 1
end

-- A scale chosen by number must divide the size into whole logical pixels (in
-- Hyprland's 1/120 steps), or Hyprland picks another scale and says so. Keep the
-- scale and trim the size by the few pixels that takes instead.
local function fit(size, scale)
  local step = math.floor(scale * 120 + 0.5)
  if step <= 0 then return size end
  for s = size, math.max(size - step, 1), -1 do
    if (s * 120) % step == 0 then return s end
  end
  return size
end

function karchy_vm_display_follow()
  local changed = false
  for _, output in ipairs(hl.get_monitors() or {}) do
    local name = output.name or ""
    if name:match("^Virtual%-%d+$") then
      local rule = effective_rule(output)
      local mode = rule.mode
      if not rule.disabled and (mode == nil or mode == "" or tostring(mode):sub(1, 4) == "pref") then
        local width, height, connector = preferred_size(name)
        local scale = tonumber(rule.scale)
        if width and not scale then
          scale = auto_scale(connector, width, height)
        end
        scale = math.floor((scale or 1) * 120 + 0.5) / 120
        if width then
          width, height = fit(width, scale), fit(height, scale)
        end
        -- Set even when the size is already right: after a reload, Hyprland
        -- applies the reloaded rules later, and "preferred" would undo it.
        if width then
          local follow = {}
          for key, value in pairs(rule) do follow[key] = value end
          follow.output = name
          follow.mode = width .. "x" .. height
          follow.scale = scale
          monitor(follow)
          if width ~= output.width or height ~= output.height or math.abs(scale - (tonumber(output.scale) or 0)) > 0.001 then
            changed = true
          end
        end
      end
    end
  end
  -- Hyprland applies a changed rule on the monitor's next frame, and an idle
  -- desktop draws none: apply the rules now. Only for a new size, as this sets
  -- the mode of every monitor again.
  if changed then hl.dispatch(hl.dsp.force_renderer_reload()) end
end

-- On a reload, Hyprland sets the monitors from the new rules before
-- config.reloaded, which would show the start size for a moment. A rule for the
-- live size now, which the rules loaded after this file replace or add to,
-- keeps the window's size through the reload; config.reloaded then sets the
-- effective rule's.
for _, output in ipairs(hl.get_monitors() or {}) do
  local name = output.name or ""
  if name:match("^Virtual%-%d+$") then
    local width, height = preferred_size(name)
    local scale = math.floor((tonumber(output.scale) or 1) * 120 + 0.5) / 120
    if width then
      monitor({ output = name, mode = fit(width, scale) .. "x" .. fit(height, scale), position = "auto", scale = scale })
    end
  end
end

hl.on("config.reloaded", function() karchy_vm_display_follow() end)
hl.on("monitor.added", function() karchy_vm_display_follow() end)
hl.on("hyprland.start", function()
  hl.exec_cmd(o.launch("/usr/lib/karchy-vm/display-watch"))
end)
