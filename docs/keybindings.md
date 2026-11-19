# Keybindings

This is the complete default set. Anything not listed is unbound. New bindings need the user's approval (D-17). Tags: [O] same as Omarchy, [New] differs from Omarchy.

## Windows

| Key | Action | Tag |
|---|---|---|
| Alt+F4 | Close window | [New] (Omarchy: Super+W) |
| Super+Up | Maximize | [New] |
| Super+Down | Restore a maximized window, otherwise minimize it (as in Windows) | [New] |
| Super+Left / Super+Right | Focus window left/right | [O] |
| Super+Shift+Arrows | Swap window | [O] |
| Super+T | Toggle floating for one window | [O] |
| Super+F | Fullscreen | [O] |
| Super+M | Minimize all windows on the workspace (as in Windows) | [New] |
| Super+Shift+M | Restore minimized windows to where they were (as in Windows) | [New] |
| Super+Minus / Super+Equal | Resize width | [O] |
| Super+Shift+Minus / Super+Shift+Equal | Resize height | [O] |
| Super+LMB drag / Super+RMB drag | Move / resize | [O] |
| Alt+Tab / Alt+Shift+Tab | Next / previous window | [O] |

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

## Shell and system

| Key | Action | Tag |
|---|---|---|
| Super+Space | Menu / app search | [O] |
| Super+L | Lock | [New] (Omarchy: Super+Ctrl+L; Omarchy's Super+L layout toggle moves to the menu) |
| Super+Escape | Power menu | [O] |
| Super+K | Keybinding viewer | [O] |
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

Window groups, panel keys, the tiling/floating workspace toggle (menu only), style toggles, browser and editor launch keys, input-method switching, zoom, the time/battery notices, dictation, the scratchpad, and the extra resize steps.
