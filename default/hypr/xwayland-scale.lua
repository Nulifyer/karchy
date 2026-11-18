-- X11 apps (XWayland) on a scaled monitor.
--
-- With xwayland.force_zero_scaling (envs.lua) Hyprland hands X11 apps the
-- monitor's real pixels: sharp, but drawn at 1x on a monitor scaled 1.5 or 2
-- unless the app scales itself. X11 apps learn the scale from the X server's
-- Xft.dpi resource, which takes fractions: 96 is 1x, 144 is 1.5x. Steam, Qt,
-- Chromium and Electron under X11, Wine and GTK's text read it when they
-- start. This keeps it at 96 x the monitor scale.
--
-- X11 has one scale for all monitors, so it follows the lowest scale of the
-- monitors in use: nothing is drawn too large for any of them. An app keeps
-- the scale it started with; start it again after changing the scale.
--
-- GDK_SCALE is the other way an X11 app is told (GTK's widgets, Java, Steam).
-- It takes whole numbers only, and an app that reads both multiplies them:
-- Steam at GDK_SCALE=2 with Xft.dpi 144 draws at 3x. So where GDK_SCALE is
-- set (hl.env("GDK_SCALE", "2")), Xft.dpi is divided by it, never to less
-- than 96, and apps that read both come out right. Hyprland keeps an
-- environment variable until you sign out, so a GDK_SCALE taken out of the
-- config counts until then.
--
-- Limits: an app that reads neither (xterm's default font, old toolkits)
-- stays at 1x; GTK apps under X11 scale their text but not their icons; and
-- the pointer over an X11 window is the size the app draws it, which is
-- XCURSOR_SIZE in real pixels.

local applied = nil

local function lowest_scale()
  local lowest = nil
  for _, monitor in ipairs(hl.get_monitors()) do
    local scale = tonumber(monitor.scale)
    if scale and scale > 0 and (not lowest or scale < lowest) then
      lowest = scale
    end
  end
  return lowest
end

local function apply()
  local scale = lowest_scale()
  if not scale then
    return
  end

  local gdk = tonumber(os.getenv("GDK_SCALE") or "") or 1
  if gdk < 1 then
    gdk = 1
  end

  local dpi = math.max(96, math.floor(96 * scale / gdk + 0.5))
  if dpi == applied then
    return
  end
  applied = dpi

  -- xrdb, where installed, changes this one resource and keeps the others;
  -- xprop (always installed) writes the property that holds them.
  hl.exec_cmd("sh -c 'if command -v xrdb >/dev/null 2>&1; then echo \"Xft.dpi: " .. dpi .. "\" | xrdb -merge; "
    .. "else xprop -root -f RESOURCE_MANAGER 8s -set RESOURCE_MANAGER \"$(printf \"Xft.dpi:\\t" .. dpi .. "\")\"; fi'")
end

hl.on("hyprland.start", function()
  -- A new X server has no resources, whatever the last session set.
  applied = nil
  apply()
end)

hl.on("config.reloaded", apply)
hl.on("monitor.added", apply)

-- The monitor is still listed while Hyprland reports its removal.
hl.on("monitor.removed", function()
  hl.timer(apply, { type = "oneshot", timeout = 1 })
end)
