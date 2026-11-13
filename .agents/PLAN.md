# Project plan

## Goal

karchy is the user's own Arch-based Linux setup. Each component is picked on purpose and the default install stays minimal. It keeps the Omarchy ideas the user likes: the Quickshell desktop shell, its plugin system, the theme system, and the simple installer. It leaves out Omarchy's large keybinding set, extra software, mise, and its update and package machinery. Software is installed with pacman, and with paru only when a package is not in the repos.

Source: the user's inception rounds on 2026-11-13, based on the Omarchy audit at `/home/nulifyer/Projects/Omarchy/audit/` (omarchy `quattro` @ `60cb9bf30`; latest release v4.5.0).

Guiding rule from the user: minimal software (small, fast, few dependencies), but basic things must just work out of the box, such as Bluetooth, printing, USB drives, audio, Wi-Fi and sleep.

## Success conditions

- [ ] Milestone 1: the VM boots to a working desktop (checklist in `TESTING.md`).
- [ ] Every component in `docs/components.md` works in the VM (phase 2).
- [ ] The user's two plugins work on karchy with their fixes (phase 3).
- [ ] Running on the Framework 13 AMD laptop (phase 4) and on the RTX 5080 desktop (phase 5).
- [ ] A karchy ISO installs the same result (phase 6).

## Scope

### In

- An installer run from the stock Arch live ISO: a short Omarchy-style form, then an unattended install (archinstall underneath).
- A setup script that installs packages and configures system and user files.
- The Omarchy code being kept, vendored at a release tag with a sync script: the shell, plugin system, bar, menu engine, theme engine, templates, themes, Hyprland Lua helpers, and the `omarchy-*` commands these need.
- New pieces:
  - greetd auto-login, with the keyring unlock decided in the VM
  - a GTK color template
  - a fish prompt template
  - the "nulifyer" theme
  - a VS Code theme that doesn't rewrite settings
  - the NAS "keep this mount" flow and Windows-like internal disk mounts
  - a web-app icon fix
  - `karchy update`
  - the btop task-manager binding
- The dotfiles repo (Nulifyer/dotfiles) reshaped into the user layer.
- Hardware detection in the installer and the three install tiers (D-28), the karchy Settings window (D-27), safe mirror ranking (D-29), bees (D-30), Secure Boot (D-31), laptop suspend-then-hibernate (D-32), and LocalSend on trusted networks (D-33).
- Fixes to the user's plugins, in their own repos.

### Out

- mise and every mise-managed tool or runtime.
- Omarchy's optional-installer catalog (about 80 installers), the Agent/Learn menus, AI integrations and the agent usage panel, and dictation.
- The dock and app grid, emoji picker, intro animations and video wallpaper (owe), night light, weather, world clock and the Tailscale panel.
- Omarchy's pacman config, Omarchy's Arch snapshot mirror, the update guard, migrations content, channels, `omarchy update`, `reinstall-configs`, factory reset, the ISO provisioning flow, the Omarchy kernel and Omarchy's NVIDIA script.
- Plymouth and SDDM.
- Preinstalled dev runtimes, containers, AI CLIs, Steam and Flatpak. The user installs these with pacman or paru after setup.
- Laptop and vendor hardware quirks beyond what the Framework 13 AMD needs.

## Product boundaries

- Hardware targets: a QEMU/KVM VM on this host (first), an older Framework 13 AMD laptop, and the RTX 5080 desktop. All x86_64.
- Package sources, in order: Arch live mirrors, then `[omarchy]`, then `[cachyos]` (generic, for the kernel). Arch's packages win when a package exists in several repos.
- The look and behavior follow Omarchy unless `DECISIONS.md` says otherwise. The keybindings are exactly the list in `docs/keybindings.md`, and the menu is exactly `docs/menu.md`.
- The interactive shell is fish, kept native and fast. Omarchy's commands stay bash scripts.

## Architecture boundaries

- Delivery is a git checkout of karchy on each machine, for example `~/.local/share/karchy`. Running `karchy update` does `paru -Syu`, a fast-forward `git pull`, any karchy migrations, and a reload. A pacman package may come later with the ISO.
- There are two repos: karchy for the system and defaults, and the dotfiles repo for the user layer. Files in `~/.config` are small include stubs or symlinks, created once. The update never overwrites them.
- Vendored Omarchy code is synced from release tags. A manifest lists the vendored paths, and the sync script shows the upstream diffs for just those paths. Vendored files keep their upstream names so that syncing stays mechanical.
- The system must not break CachyOS-style boot assumptions. The initramfs is systemd-based with `sd-encrypt`, and Omarchy's mkinitcpio, pacman, limine and update-guard drop-ins are never installed.
- Security:
  - The terminal sudo password is cached per terminal for about 10 minutes.
  - GUI elevation goes through the shell's polkit prompt.
  - NOPASSWD rules exist only for features that are kept.
  - ufw denies incoming traffic.

## Phases

1. **VM bring-up:**
   - repo skeleton
   - the vendored Omarchy code from v4.5.0 and the sync script
   - the installer form and the archinstall config
   - the setup script

   Exit: the milestone 1 checklist in `TESTING.md` passes.
2. **Full VM check:** every item in `docs/components.md`, `docs/keybindings.md` and `docs/menu.md` works. This phase also closes three open decisions in `DECISIONS.md`: the keyring, micro vs nano, and how to restore minimized windows.
3. **Plugin fixes:** done in their own repos, alongside phases 1–2.
   - Both plugins: use `Commons.Color` instead of bare `Color`.
   - VPN plugin: watch `/run/nulifyer-vpn/status` instead of polling.
   - Project picker: add a "New Project" entry that creates the folder and opens it in VS Code.
4. **Framework 13 AMD install:** fingerprint, power-profiles-daemon, suspend on idle, docking and Wi-Fi.
5. **Desktop install:** RTX 5080 (`linux-cachyos-nvidia-open`), two monitors and the 3.6 TB data disk. This is a fresh install, with data restored afterwards.
6. **karchy ISO:** the same installer, baked into an ISO.
7. **Home backup to the NAS** (D-35): pick the tool, timer, target and a restore test. Offered as an Optional feature.

The karchy Settings window (D-27) and the Secure Boot installer step (D-31) are built and verified in phase 2.

## Open planning questions

- See `DECISIONS.md` › Open decisions.

## Project notes

- Reference material:
  - audit reports: `/home/nulifyer/Projects/Omarchy/audit/` (`README.md`, `01`–`05`)
  - upstream clone: `/home/nulifyer/Projects/Omarchy/reference/omarchy`
  - live `[omarchy]` repo package list: `https://pkgs.omarchy.org/stable/x86_64/omarchy.db`
- Tags used in the docs: [O] means Omarchy does this, [C] means CachyOS does this, and [New] means neither does.
