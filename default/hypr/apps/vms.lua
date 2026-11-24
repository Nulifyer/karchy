-- The Virtual machines and Containers windows are shell windows (Quickshell's
-- class), matched by title as karchy Settings is. App windows that give
-- themselves a size (D-175, system.lua): tiles on a tiling workspace,
-- floating at their own size on a floating one.
o.own_size_window({ class = "^org.quickshell$", title = "^Virtual machines$", size = { 960, 680 } })
o.own_size_window({ class = "^org.quickshell$", title = "^Containers$", size = { 1000, 680 } })
