-- Captive portal sign-in: a small floating window, like macOS's, that
-- karchy-network-captive-portal closes once the internet is reachable. The
-- panel opens http://neverssl.com (Model.js captivePortalUrl), a plain-HTTP
-- page the portal can intercept. A Chromium-based browser names the app window
-- after the browser and the host ("brave-neverssl.com__-Default"), so any
-- browser prefix matches.
local captive_portal = "^.+-neverssl\\.com__.*$"
o.window(captive_portal, { tag = "-chromium-based-browser" })
o.window(captive_portal, { float = true, center = true, size = { 900, 760 } })
