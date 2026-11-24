-- The 8:9 portrait presets scale from monitor height so they occupy the same
-- share of anything from a 1080p monitor to a scaled 6K display.
o.window("^WebcamOverlay-small$", {
  size = { "(monitor_h*4/25)", "(monitor_h*9/50)" },
  move = { "(monitor_w-monitor_h*4/25-40)", "(monitor_h-monitor_h*9/50-40)" },
})
o.window("^WebcamOverlay-medium$", {
  size = { "(monitor_h*2/9)", "(monitor_h/4)" },
  move = { "(monitor_w-monitor_h*2/9-40)", "(monitor_h-monitor_h/4-40)" },
})
o.window("^WebcamOverlay-large$", {
  size = { "(monitor_h*3/10)", "(monitor_h*27/80)" },
  move = { "(monitor_w-monitor_h*3/10-40)", "(monitor_h-monitor_h*27/80-40)" },
})

-- mpv draws the camera under an app id of its own, so these rules reach the
-- overlay and no other mpv window, and it opens at its corner.
o.window({ class = "^WebcamOverlay-(small|medium|large)$", title = "^WebcamOverlay$" }, {
  float = true,
  pin = true,
  no_initial_focus = true,
  no_dim = true,
})
