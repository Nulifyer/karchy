<div align="center">

# karchy

<img src="docs/logo.svg" alt="karchy logo" width="128" height="128">

**A minimal Arch Linux desktop on Hyprland, with one Settings window, signed updates and snapshots you can boot.**

[![Release](https://github.com/nulifyer/karchy/actions/workflows/release.yml/badge.svg)](https://github.com/nulifyer/karchy/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/nulifyer/karchy?include_prereleases&label=release&logo=github&cacheSeconds=300)](https://github.com/nulifyer/karchy/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Arch Linux + Hyprland](https://img.shields.io/badge/Arch%20Linux-Hyprland-1793d1?logo=archlinux&logoColor=white)

</div>

<p align="center">
  <a href="docs/screenshots/desktop.png"><img src="docs/screenshots/desktop.png" alt="The karchy desktop: a terminal with fastfetch and a git project, btop and Thunar, tiled under the bar" width="32%"></a>
  <a href="docs/screenshots/menu.png"><img src="docs/screenshots/menu.png" alt="The menu, searching: settings pages, package actions and apps in one list" width="32%"></a>
  <a href="docs/screenshots/settings.png"><img src="docs/screenshots/settings.png" alt="The Settings window on Keybindings: every binding, its keys and where it comes from" width="32%"></a>
</p>

karchy is a tiling desktop that works out of the box and stays out of the way.
The base install is small and fast. Everything is a pacman package, so the
system is updated, never reinstalled.

## What's in it

- **The desktop.** A bar, a menu that searches apps and settings with
  `Super` + `Space`, a notifications panel, and 24 themes that recolor
  everything at once.
- **Settings.** One window for network, displays, input, keybindings,
  appearance, power, storage, users and more. Your own config files still win.
- **Keybindings.** Every binding is listed with its keys, and you can change,
  add or reset them in Settings.
- **Quick install.** About 550 apps, fonts and optional features, installed
  from one window.
- **Updates.** One command or one button updates the whole system, with a
  snapshot before and after. Packages are signed, and you pick a stable, rc or
  nightly channel.
- **The system.** btrfs with snapshots you can boot from the boot menu. Disk
  encryption and a firewall are on by default, and Secure Boot is supported.
- **The installer.** A short form, a clear summary of what gets erased, and the
  right drivers for laptops and NVIDIA GPUs.
- **Agent skills.** AI coding agents learn how karchy works, so they can help
  you customize or troubleshoot it.

## Get it

Download the ISO from [releases](https://github.com/Nulifyer/karchy/releases),
write it to a USB stick and boot it. The installer starts by itself.
[Installing karchy](docs/installing.md) has the details.

## Docs

- [Installing](docs/installing.md)
- [Recovery](docs/recovery.md)
- [Components](docs/components.md)
- [Menu](docs/menu.md)
- [Keybindings](docs/keybindings.md)
- [Maintenance](docs/maintenance.md)
- [Architecture](docs/architecture.md)

## License

[MIT](LICENSE)
