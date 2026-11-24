# The clipboard history changed where it keeps things (D-167): what is not
# pinned lives in memory ($XDG_RUNTIME_DIR/karchy/clipboard) and is gone at
# logout, as on Windows; pinned entries are in ~/.local/state/karchy/clipboard.
# The earlier history wrote every copy to the home folder and kept it. Nothing
# reads those files any more, so they are removed rather than left behind.
state="${XDG_STATE_HOME:-$HOME/.local/state}/karchy"

rm -f -- "$state/clipboard-history.json"
rm -rf -- "$state/clipboard-images" "$state/clipboard-open"
# Copies the old capture was cut off in the middle of.
find "$state" -maxdepth 1 -type f -name 'clipboard.??????' -delete 2>/dev/null || true
