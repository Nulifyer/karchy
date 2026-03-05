# Karchy

A system menu and toolkit for CachyOS KDE Plasma, inspired by [omarchy](https://github.com/basecamp/omarchy).

Launch everything from a single `Super+Space` menu — apps, package management, web apps, system settings, updates, and more.

## Features

| | Feature | Description |
|---|---|---|
| 🚀 | **App Launcher** | fuzzel-powered app search with KDE integration |
| 📦 | **Package Management** | Install/remove packages from pacman and AUR (paru) with fzf fuzzy search |
| 🌐 | **Web Apps** | Create desktop shortcuts that launch in browser app mode |
| 🔍 | **Project Discovery** | Scan for projects and open them in your preferred editor |
| 🔄 | **System Updates** | Update pacman + AUR packages, with a system tray notifier icon |
| ⬆️ | **Self-Update** | Update karchy itself via `git pull` |
| 🧹 | **Cleanup** | Remove orphaned packages and clean the package cache |
| 🎨 | **10 Color Themes** | Applied to all menus — Catppuccin, Tokyo Night, Nord, Dracula, and more |
| ⚙️ | **Setup Utilities** | Audio, Wi-Fi, Bluetooth, monitors, power profiles, theme |
| 🔒 | **System Controls** | Lock, suspend, hibernate, logout, restart, shutdown |

## Requirements

- CachyOS (or Arch Linux) with KDE Plasma 6
- Wayland
- Git

Dependencies are installed automatically during setup.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/install.sh | bash
```

This will:
- Install dependencies (fuzzel, gum, alacritty, fzf, chafa, paru-git, etc.)
- Clone the repo to `~/.local/share/karchy`
- Add `~/.local/share/karchy/bin` to PATH
- Bind `Super+Space` to the karchy menu
- Set up KWin window rules for popups and web apps
- Enable the update notifier tray icon

Re-running the installer updates the existing installation via `git pull`.

## Update

From the menu: **Update > Update Karchy**

Or from the command line:

```bash
karchy-self-update
```

## Usage

Press `Super+Space` to open the menu, or run directly:

```bash
karchy-menu          # main menu
karchy-menu apps     # jump to app launcher
karchy-menu install  # jump to install menu
karchy-menu update   # jump to update menu
karchy-menu setup    # jump to setup menu
karchy-menu remove   # jump to remove menu
karchy-menu system   # jump to system menu
```

### Menu Structure

```
Karchy
├── Apps             — fuzzel app launcher
├── Projects         — scan & open projects in editor
├── Setup
│   ├── Audio        — pavucontrol
│   ├── Wifi         — KDE network settings
│   ├── Bluetooth    — KDE bluetooth settings
│   ├── Monitors     — KDE display settings
│   ├── Power        — power profile selector
│   └── Theme        — pick a color theme
├── Install
│   ├── Package      — interactive pacman browser
│   ├── AUR          — interactive paru browser
│   ├── Web App      — create browser app shortcuts
│   └── Font         — install Nerd Fonts
├── Remove
│   ├── Package      — interactive package remover
│   ├── Web App      — remove created shortcuts
│   └── Font         — remove installed fonts
├── Update
│   ├── System       — pacman + AUR upgrade
│   ├── Mirror       — rank fastest mirrors
│   ├── Firmware     — fwupd firmware update
│   ├── Timezone     — select timezone
│   ├── Hardware     — restart audio, wifi, bluetooth
│   ├── Cleanup      — remove orphans + clean cache
│   └── Karchy       — self-update via git pull
└── System           — lock, suspend, hibernate, logout, restart, shutdown
```

### Themes

Go to **Setup > Theme** to pick a color theme. Choose `auto` to follow your KDE color scheme, or select a hardcoded theme:

Catppuccin Mocha, Gruvbox Dark, Tokyo Night, Nord, Dracula, Solarized Dark, One Dark, Rose Pine, Everforest Dark, Kanagawa

## License

MIT
