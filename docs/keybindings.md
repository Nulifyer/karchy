# Keybindings

This is the complete default set. Anything not listed is unbound. New default bindings need the user's approval (D-17). People change their own in Settings › Keybindings or in `~/.config/hypr/bindings.lua`: see [Layers and the editor](#layers-and-the-editor) at the end. Tags: [O] same as Omarchy, [New] differs from Omarchy.

## Windows

| Key | Action | Tag |
|---|---|---|
| Alt+F4 | Close window | [New] (Omarchy: Super+W) |
| Super+Up | Maximize | [New] |
| Super+Down | Restore a maximized window; give a window on a half its earlier place and size back; otherwise minimize it (as in Windows) | [New] |
| Super+Left / Super+Right | On a tiling workspace: focus window left/right. On a floating workspace: put the window on the left/right half of its monitor (as in Windows, D-165). The arrow the other way brings it back; the same arrow again sends it on to the next monitor that way. Each key carries the two actions, "Focus on left window" and "Snap window to the left half" | [O] + [New] |
| Super+Shift+Arrows | Swap window | [O] |
| Super+T | Toggle floating for one window | [O] |
| Super+F | Fullscreen | [O] |
| Super+M | Minimize all windows on the workspace (as in Windows) | [New] |
| Super+Shift+M | Restore minimized windows to where they were (as in Windows) | [New] |
| Super+Minus / Super+Equal | Resize width | [O] |
| Super+Shift+Minus / Super+Shift+Equal | Resize height | [O] |
| Super+LMB drag / Super+RMB drag | Move / resize | [O] |
| Alt+Tab / Alt+Shift+Tab | The window used before this one. While Alt stays down, each Tab goes one window further back and Shift+Tab forward again, on the current workspace (as in Windows, without its picture of the windows) | [New] (Omarchy: next / previous in a fixed order) |

## Workspaces and monitors

| Key | Action | Tag |
|---|---|---|
| Super+1..0 | Workspace N on the focused monitor | [O] |
| Super+Shift+1..0 | Move window to workspace N, follow | [O] |
| Super+Tab / Super+Shift+Tab | Next / previous workspace | [O] |
| Super+Scroll | Next / previous workspace | [O] |
| Super+` | Drop-down terminal | [O] |
| Super+Shift+Ctrl+Arrows | Move window to monitor | [O] |
| Ctrl+Alt+Tab | Focus next monitor | [O] |

## Clipboard

| Key | Action | Tag |
|---|---|---|
| Super+C / Super+V / Super+X / Super+A | Universal copy / paste / cut / select all (terminal-aware) | [O] |
| Super+Ctrl+V | Clipboard history | [O] |

The clipboard works as on Windows (D-167). Ctrl+C, Ctrl+X and Ctrl+V are the apps' own keys and karchy binds nothing over them. In a terminal Ctrl+C interrupts the running program, so copy and paste are Ctrl+Shift+C and Ctrl+Shift+V there (also Ctrl+Insert and Shift+Insert), in every terminal karchy configures: foot, Ghostty, Alacritty and kitty. Super+C and Super+V send whichever pair the focused window takes.

Super+Ctrl+V opens the history of what was copied: text, images and file copies. Its keys are the picker's own, not Hyprland bindings:

| Key in the history | Action |
|---|---|
| typing | Search |
| Enter, or a click | Paste the entry where the cursor is |
| Shift+Enter | Copy the entry without pasting |
| Alt+Enter | Open it: a link in the browser, text in the editor, an image in the annotator, a file in its app |
| Ctrl+P | Pin or unpin it; a pinned entry stays through Clear all and a restart |
| Delete | Remove the entry |
| Shift+Delete | Clear all that is not pinned (asks first) |
| Escape | Clear the search, then close |

## Shell and system

| Key | Action | Tag |
|---|---|---|
| Super+Space | Menu / app search | [O] |
| Super+L | Lock | [New] (Omarchy: Super+Ctrl+L; Omarchy's Super+L layout toggle moves to the menu) |
| Super+Escape | Power menu | [O] |
| Super+K | Keybindings: Settings › Keybindings, the list of every binding and its editor (D-134) | [New] (Omarchy: a read-only list) |
| Super+Ctrl+R | Set reminder | [O] |
| Super+Comma | Dismiss latest notification | [O] |
| Super+Shift+Comma | Dismiss all notifications | [O] |
| Super+Shift+Alt+Comma | Notification history | [O] |
| Ctrl+Shift+Esc | Mission Center (task manager: performance, apps, services); btop stays in the menu | [New] |

## Apps

| Key | Action | Tag |
|---|---|---|
| Super+Return | Terminal (foot) | [O] |
| Super+E | File manager (Thunar) | [New] (Omarchy: Super+Shift+F) |
| Ctrl+Alt+P | Project picker (only while the karchy-project-picker package is installed) | [New] |

## Capture

| Key | Action | Tag |
|---|---|---|
| Super+Shift+S | Region screenshot (Omasnap): saved and copied; its notification has Open and Edit (annotate) | [New] |
| Print | Screenshot of a region, window or screen (Omasnap): saved and copied; its notification has Open and Edit (annotate) | [O] |
| Alt+Print | Start/stop screen recording | [O] |

## Hardware keys (also work on the lock screen)

This is Omarchy's full set [O]:
- **Volume:** ±5 (Alt: ±1), mute, Shift+Mute to switch output, mic mute.
- **Media:** play/pause, next, previous.
- **Screen brightness:** ±5% (Alt: ±1%, Shift: max/min).
- **Keyboard backlight:** up, down, cycle.
- **Touchpad:** toggle.
- **Eject.**
- **Airplane mode** (the airplane key, `XF86RFKill`): every radio off or on, with an on-screen message [New]. The kernel switches the radios for this key (`CONFIG_RFKILL_INPUT`), also at the login prompt; the binding runs `karchy-airplane key`, which shows the result and toggles only on a kernel without that handler, so the two never undo each other. Approved by the user (D-68, N-5).

## Touchpad

| Gesture | Action | Tag |
|---|---|---|
| 3-finger swipe left/right | Previous / next workspace | [O] |

## Deliberately unbound

Window groups, panel keys, the tiling/floating workspace toggle (Settings › Appearance only), style toggles, browser and editor launch keys, input-method switching, zoom, the time/battery notices, dictation, the scratchpad, and the extra resize steps.

## Layers and the editor

Every binding belongs to a layer (D-134). They load in this order, and a later layer can take over what an earlier one bound:

| Layer | What | File |
|---|---|---|
| 1 default | karchy's set, the tables above | `karchy/hypr/bindings.lua`; hardware keys and the clipboard in `default/hypr/bindings/` |
| 2 add-on | an add-on package's bindings | `/usr/share/karchy/hypr.d/<name>.lua` |
| 3 Settings | changes made in Settings › Keybindings | `~/.config/karchy/keybindings.json`, generated into `~/.local/state/karchy/hypr/keybindings.lua` |
| 4 yours | your own file, which wins | `~/.config/hypr/bindings.lua` |

`karchy/hypr/init.lua` loads them in that order. `karchy/hypr/keys.lua` watches every bind and unbind, notes the layer from where the calling file lives, and publishes the record when the config has loaded (`$XDG_RUNTIME_DIR/karchy-keybindings.json`). `karchy-settings-keybindings list --json` resolves the record into rows: the action, the keys in effect, the layer that won, and the chain of what it replaced. The Settings page and agents read that one list.

**Settings › Keybindings** (Super+K) works like VS Code's Keyboard Shortcuts:

- Each binding is a row, grouped as the tables above: the action, its keys as key caps, and where it comes from (karchy, the add-on's name, Settings, your bindings.lua). A row that replaced something, or was itself replaced or removed, shows the whole chain under it, lowest layer first, with what lost struck through.
- Search matches the action, its keys now and before, the source and what it runs. "Record keys" searches by pressing a combination. Filters: All, Changed, Yours, Add-ons, Conflicts.
- Enter (or a double click) on a row captures new keys; Enter accepts, Escape clears, then cancels. Keys another action has are shown before saving ("Also bound to: Close window") with Replace, Keep both and Cancel. A adds one more binding for the same action, Delete removes the binding, R brings the default back. "Add…" makes a binding of your own: a name, a command and keys. "Reset all…" forgets every change.
- While keys are captured the window asks Hyprland to hold back its own shortcuts, so Super+T arrives in the page instead of running. That ends with the capture, the window or the shell.
- A binding set in your own `bindings.lua` shows as yours and is read-only here: it wins, and it is changed in that file (the page's header links it). Mouse bindings are shown and not edited.
- A change that would leave no key for the menu, a terminal or this page is refused.

What a change writes follows VS Code: a rule of your own wins over a default; taking a default away is a rule of its own (`{"unbind": keys, "action": name}`); moving a default writes that removal and an addition (`{"bind": keys, "action": name, "replaces": old keys}`); changing a binding you made edits its rule; a reset deletes your rules for that binding and adds nothing. `keybindings.json` holds only your changes, so no changes is no file.

If the generated Lua fails to load, or one rule in it fails, Hyprland keeps everything bound so far (the defaults are bound before it loads) and the page says what happened. A rule whose action is gone (an add-on removed, a default renamed) does nothing and is listed as no longer applying.

### Adding a default

One line in `karchy/hypr/bindings.lua`, under the `o.bind_group("…")` it belongs to:

```lua
o.bind("SUPER + SHIFT + N", "Night light", "karchy-settings-nightlight toggle")
```

`o.bind(keys, name, what it runs)`: the name is the action's identity in the editor and in people's saved changes, so every action gets its own, and renaming one orphans changes made to it. The row appears in Settings › Keybindings by itself, in that group. Add the key to the tables above (D-17).

An add-on brings its bindings in its own file, installed to `/usr/share/karchy/hypr.d/<name>.lua`: the same `o.bind` lines after `o.bind_group("<what the add-on is called>")`. They show with the add-on's name as their source and can be changed in the editor like karchy's own.

