<div align="center">

# karchy

<img src="docs/logo.svg" alt="karchy logo" width="128" height="128">

**A personal Arch and CachyOS desktop on Hyprland, shared as it is.**

[![Release](https://github.com/nulifyer/karchy/actions/workflows/release.yml/badge.svg)](https://github.com/nulifyer/karchy/actions/workflows/release.yml)
[![Latest release](https://img.shields.io/github/v/release/nulifyer/karchy?include_prereleases&label=release&logo=github&cacheSeconds=300)](https://github.com/nulifyer/karchy/releases)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)
![Arch Linux + Hyprland](https://img.shields.io/badge/Arch%20Linux-Hyprland-1793d1?logo=archlinux&logoColor=white)

</div>

<!-- Three screenshots, side by side. When the three files exist, delete this
     line and the closing line of this comment, and delete the single
     screenshot below.
<p align="center">
  <img src="docs/screenshots/desktop.png" alt="The karchy desktop" width="32%">
  <img src="docs/screenshots/menu.png" alt="The menu" width="32%">
  <img src="docs/screenshots/settings.png" alt="The Settings window" width="32%">
</p>
-->

![karchy desktop with fastfetch, btop and Thunar](docs/screenshot.png)

karchy is one person's Linux distro. Its author built it for their own laptop
and desktop, and publishes it so that others can use it or take parts of it.
It is Arch Linux with CachyOS's kernel and packages, a Hyprland desktop, and a
Quickshell shell that started as [Omarchy](https://github.com/basecamp/omarchy)'s.

The choices are the author's, and the base install is small. If you want a
tiling desktop with a Settings window, snapshots you can boot, and updates that
come as signed packages, it may suit you too.

karchy has release candidates only. They were tested in virtual machines and
not yet on real hardware. Read [The state of things](#the-state-of-things)
before you install karchy on a computer you need.

## What you get

### The desktop

- **The bar.** It floats inset from the screen edge and docks while a window is
  maximized. It holds workspaces, the clock and calendar, notifications, the
  tray, audio, microphone, network, Bluetooth, brightness, power and media.
- **The menu.** `Super` + `Space` opens it. Its eight rows are Apps, Packages,
  Recording, Keybinds, Update, Settings, Reload and Power. Typing searches
  apps, menu rows and every Settings page.
- **Settings.** One window with these sections: Network, Displays, Input,
  Keybindings, Appearance, Fonts, Notifications, Default apps, Power, Storage,
  Date & Time, Security, SSH & Git and About. Where an area has a config file
  of your own, its page links the file, and your file wins over the window.
- **Keybindings.** Settings › Keybindings lists every binding with its keys and
  where it comes from. You can search by pressing keys, change, add, remove and
  reset bindings, and it warns before two actions share the same keys.
- **The notifications panel.** A notification that nobody answered waits behind
  the bell until you open, dismiss or clear it. Each app is set to Allow,
  Silent or Off. Do Not Disturb is a switch in the panel.
- **Quick install.** A window with about 550 apps, fonts and optional features
  in categories. Apps from the signed repositories install in the window, with
  progress for each. AUR apps build in a terminal, where you can read the build
  files first.
- **The Updates window.** It shows what an update would install before the
  update runs, with Arch's news first. It also holds the release channel and
  firmware updates.
- **Themes.** 24 themes. One switch recolors the shell, Hyprland, terminals,
  GTK and Qt apps, VS Code, btop, micro, Brave and the fish prompt.
- **Windows.** Workspaces tile, scroll or float. Floating windows have title
  bars with minimize, maximize and close. The window keys follow Windows:
  `Alt` + `F4`, `Super` + `Up`, `Super` + `Down`, `Super` + `M`.

### The system

- **btrfs with bootable snapshots.** snapper takes a snapshot before and after
  each package change. The boot menu lists every snapshot, and you can boot one
  and make it permanent.
- **Disk encryption by default.** The installer encrypts the disk with LUKS2,
  and one password opens the disk and logs you in. You can choose an install
  without encryption. karchy's login screen then asks for your password at
  every boot.
- **bees deduplication.** bees finds identical data and stores it once. It is
  on by default, uses at most one CPU core and only idle time, and pauses on
  battery. karchy builds it from [its own fork](https://github.com/Nulifyer/bees).
- **Signed packages.** karchy's own packages come from the `[karchy]` pacman
  repository. CI builds and signs them, and pacman refuses a package without a
  valid signature.
- **Release channels.** stable gets releases, rc also gets release candidates,
  and nightly gets every change to `main`. The channel covers karchy's packages
  only. Arch and CachyOS packages are the same on every channel.
- **Two kernels.** `linux-cachyos` is the default and `linux-cachyos-lts` is
  the fallback entry in the boot menu.
- **Secure Boot.** If the firmware is in Setup Mode, the installer creates its
  own keys, enrolls them with Microsoft's and signs the boot loader.
  `karchy secureboot setup` does the same on an installed system.
- **Network defaults.** The firewall denies incoming connections. On a network
  you have not marked as trusted, DNS goes to Quad9 over TLS and the LocalSend
  port stays closed.

### The installer

- It runs from the karchy ISO, where it starts by itself, or from the stock
  Arch ISO.
- A form asks for the keyboard, the disk, encryption, your user and one
  password, the timezone and the release channel. It also asks about other
  internal disks, Secure Boot and bees where they apply.
- A summary shows in red which disks are erased. The installer writes nothing
  to a disk before you confirm "Erase and install".
- A laptop gets the laptop packages. A computer with an NVIDIA GPU gets the
  driver that fits the GPU's generation.
- If a package mirror fails a download, the installer moves that mirror to the
  end of the list and runs the step again.
- An answer file replaces the form for an unattended install.

### Add-ons and optional features

These are not in the base install. Quick install adds and removes them.

- **WireGuard VPN** (`karchy-vpn`). Your own WireGuard VPN with a kill switch.
  In Auto mode it connects on networks you do not trust and stands by on
  trusted ones.
- **Project picker** (`karchy-project-picker`). `Ctrl` + `Alt` + `P` finds your
  projects and opens one in your editor or a terminal.
- **System features.** Printers & scanners, Containers with rootless Podman,
  and Virtual machines with QEMU.

### Agent skills

karchy installs [Agent Skills](https://agentskills.io) that tell an AI coding
agent how this system works. Claude Code, Codex, Gemini CLI and other agents
get them through one shared folder, `~/.agents/skills`.

- `karchy` covers customizing and running the system.
- `karchy-troubleshoot` covers logs, crashes, boot problems and bug reports.
- Containers and Virtual machines each add a skill while they are installed.

The skills tell an agent to make a small change directly and say how to undo
it. For a large change, they tell the agent to plan with you and take a
snapshot first. karchy never replaces a skill of your own.

## Install

You need an x86_64 computer that boots in UEFI mode, a USB stick and a network
connection. The installer erases the whole disk that you choose.

1. Open the [releases page](https://github.com/Nulifyer/karchy/releases) and
   find the newest release candidate. Download `karchy-<version>-x86_64.iso`
   and its `.sha256` file.
2. Check the download:

   ```sh
   sha256sum -c karchy-<version>-x86_64.iso.sha256
   ```

3. Write the ISO to the USB stick. Replace `/dev/sdX` with the stick. This
   command erases everything on the stick.

   ```sh
   sudo dd if=karchy-<version>-x86_64.iso of=/dev/sdX bs=4M oflag=sync
   ```

4. Boot the stick in UEFI mode. The installer starts by itself.
5. Answer the form. At the channel question, pick **rc**.
6. Check the summary, then confirm. Follow the last screen to restart.

[Installing karchy](docs/installing.md) has the rest: installing from the Arch
ISO, Secure Boot, unattended installs and testing in a VM. If the installed
system does not boot, see [When karchy does not boot](docs/recovery.md).

## Updates

Run `karchy update`, or open the Updates window and press Install. One pass
updates karchy's packages from your release channel together with the Arch,
CachyOS and AUR packages, with a snapshot before and after. If an update breaks
the system, boot the snapshot from before it in the boot menu.

A karchy machine is updated, never reinstalled. A change that pacman cannot
make by itself ships as a migration, and the update runs each migration once.

```sh
karchy update                 # update karchy and the whole system
karchy channel                # show the release channel and the installed release
karchy channel set nightly    # change the channel: stable, rc or nightly
```

## The state of things

- **Release candidates only.** The releases so far are `v0.1.0-rc.1` to
  `v0.1.0-rc.7`. There is no stable release, so the installer offers the rc and
  nightly channels.
- **Tested in VMs only.** Fresh installs from the ISO, unlocking the disk,
  snapshot boots, resume from hibernation and updates were checked in virtual
  machines.
- **Not tested on real hardware.** Nobody has checked NVIDIA drivers, Wi-Fi,
  sleep and hibernation, docks, HDR and VRR, fingerprint readers, firmware
  updates or Secure Boot on a physical computer.
- **`main` is ahead of the last release candidate.** This page describes
  `main`, which is the nightly channel. The `v0.1.0-rc.7` ISO has an older
  installer that always encrypts the disk and does not ask about other internal
  disks. The login screen, the eight-row menu, the keybinding editor and the
  Security and Date & Time pages are also newer than rc.7. An rc.7 install
  gets them now on the nightly channel, or with the next release candidate.

What this means if you try it: expect faults on your hardware that no VM
showed. Try it in a VM or on a spare computer first. Keep a backup of anything
on the disk, because the installer takes the whole disk and does not install
beside another system on it.

Not done yet:

- a stable 0.1.0 release
- installs on the two computers karchy is built for, a laptop and an NVIDIA
  desktop
- backup of the home folder to a NAS
- automatic timezone
- a live session on the ISO to try karchy without installing it

## First keys

| Keys | What they do |
| --- | --- |
| `Super` + `Space` | Menu and app search |
| `Super` + `Return` | Terminal |
| `Super` + `E` | Files |
| `Super` + `K` | Settings › Keybindings, every binding and its editor |
| `Super` + `L` | Lock |
| `Super` + `Escape` | Power menu: lock, suspend, log out, reboot, shut down |

## Docs

- [Installing karchy](docs/installing.md): the installer's questions, the Arch
  ISO route, Secure Boot, unattended installs, building the ISO and testing in
  a VM.
- [When karchy does not boot](docs/recovery.md): snapshots, the LTS kernel,
  getting in from the install media and the LUKS header backup.
- [Components](docs/components.md): what an install contains and where each
  part comes from.
- [Menu](docs/menu.md): the menu's rows and what its search finds.
- [Keybindings](docs/keybindings.md): the default keys, the layers and the
  editor.
- [Maintenance](docs/maintenance.md): what updates itself, the package set,
  migrations and what needs a person.
- [Architecture](docs/architecture.md): how the repository, the packages and
  the shell are put together.
- [Packaging](packaging/README.md): how the packages are built, versioned and
  published.

## Credits and licence

karchy is built from [Omarchy](https://github.com/basecamp/omarchy) v4.5.0 and
owes it the shell, the menu engine, the theme system and much of its look. It
runs on [Arch Linux](https://archlinux.org) with the kernel and packages of
[CachyOS](https://cachyos.org). Deduplication comes from
[Nulifyer/bees](https://github.com/Nulifyer/bees), karchy's fork of
[bees](https://github.com/Zygo/bees).

karchy is [MIT licensed](LICENSE), as Omarchy is.
