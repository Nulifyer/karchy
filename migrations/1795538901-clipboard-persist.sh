# The clipboard keeps a copy after the app that made it closes
# (karchy-clipboard-persist.service). It starts with every session from the
# package; this starts it in the session that ran the update, so it works
# before the next login.
if systemctl --user daemon-reload 2>/dev/null; then
  systemctl --user start karchy-clipboard-persist.service 2>/dev/null || true
fi
