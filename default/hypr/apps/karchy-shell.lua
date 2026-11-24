-- Window and layer rules for the Karchy Quickshell surfaces. The
-- shell-wide bar / menu / popouts are layer-shell.

-- Keep the bar instant: no layer-shell fade/slide animation.
hl.layer_rule({ match = { namespace = "karchy-bar" }, no_anim = true, animation = "none" })

-- Launcher, image selector, emojis, clipboard overlays, the OSD, reminders, the
-- Wi-Fi QR code, the Alt+Tab switcher and keyboard-driven panels should pop
-- without compositor layer animations. Overlays open as soon as their scale is ready, without a
-- compositor fade or slide. Panels keep their own QML opacity transition
-- for normal open/close, and skip it for panel handoff.
hl.layer_rule({ match = { namespace = "^(karchy-menu|karchy-image-selector|karchy-emojis|karchy-clipboard|karchy-keyboard-panel|karchy-osd|karchy-reminders|karchy-network-qr|karchy-dock|karchy-dock-apps|karchy-window-switcher)$" }, no_anim = true, animation = "none" })

-- A boot intro hands the desktop between OWE's video layer and the shell's
-- background layer. The media fades itself, so a compositor fade on either
-- layer only dips the screen toward the empty desktop during the handoff.
hl.layer_rule({ match = { namespace = "^(karchy-background|owe-background)$" }, no_anim = true, animation = "none" })

-- Dev gallery is the main shell workbench; open it maximized like
-- SUPER+ALT+F so component previews have the whole workspace.
o.window({ class = "^karchy-shell$", title = "^Karchy shell – dev gallery$" }, { maximize = true })
