-- Ctrl+Alt+P opens the project picker (docs/keybindings.md). Installed by the
-- karchy-project-picker package into /usr/share/karchy/hypr.d, which
-- karchy/hypr/init.lua loads, so the binding goes with the package.
o.bind("CTRL + ALT + P", "Project picker", "karchy-shell shell toggle karchy.project-picker '{}'")
