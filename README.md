# Karchy

A system menu and toolkit for CachyOS KDE Plasma, inspired by [omarchy](https://github.com/basecamp/omarchy).

Launch everything from a single `Super+Space` menu — apps, package management, web apps, system settings, updates, and more.

## Features

- **App Launcher** — fuzzel-powered app search with KDE integration
- **Package Management** — install/remove packages from pacman and AUR (paru) with fzf search
- **Web Apps** — install web apps from Dashboard Icons, launch in browser app mode, remove with one click
- **Development Environments** — one-click setup for Ruby, Node.js, Go, Python, Rust, and more
- **System Updates** — update pacman + AUR packages, with a system tray notifier icon
- **Theming** — auto-reads KDE colors or manually override with 10 built-in themes (Catppuccin, Gruvbox, Tokyo Night, Nord, Dracula, etc.)
- **Setup Utilities** — audio, wifi, bluetooth, monitors, DNS, power profiles, timezone
- **System Controls** — lock, suspend, hibernate, logout, restart, shutdown

## Requirements

- CachyOS (or Arch Linux) with KDE Plasma 6
- Wayland

## Install

```bash
git clone https://github.com/youruser/karchy.git
cd karchy
bash install.sh
```

This will:
- Install dependencies (fuzzel, gum, alacritty, fzf, chafa, paru-git, etc.)
- Copy scripts to `~/.local/share/karchy/bin` and add to PATH
- Bind `Super+Space` to the karchy menu
- Set up KWin window rules for popups and web apps
- Enable the update notifier tray icon

Re-run `bash install.sh` to update. Use `bash install.sh --no-deps` to skip package installation.

## Usage

Press `Super+Space` to open the menu, or run directly:

```bash
karchy-menu          # main menu
karchy-menu apps     # jump to app launcher
karchy-menu install  # jump to install menu
karchy-menu update   # jump to update menu
karchy-menu setup    # jump to setup menu
```

### Themes

Go to **Setup > Theme** to pick a color theme. Choose `auto` to follow your KDE color scheme, or select a hardcoded theme:

Catppuccin Mocha, Gruvbox Dark, Tokyo Night, Nord, Dracula, Solarized Dark, One Dark, Rose Pine, Everforest Dark, Kanagawa
