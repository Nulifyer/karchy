# Components

What a karchy install contains. Tags: [O] Omarchy does it, [C] CachyOS does it, [New] neither does. Packages come from Arch unless a repo is named. Anything not listed here is not in the base install.

## System

| Area | Choice | Source |
|---|---|---|
| Repos | `[cachyos]` (generic), then Arch live mirrors, then `[omarchy]` (D-45) | [C] + [O] |
| Kernel | `linux-cachyos`, with `linux-cachyos-lts` as the fallback; NVIDIA machines add both `-nvidia-open` modules and CachyOS's `nvidia-utils` (D-45) | [C] |
| Disk | LUKS2, btrfs `zstd:1,noatime`, subvolumes `@ @home @root @srv @cache @log @tmp @swap`, 4 GiB ESP at `/boot` | [O+C] |
| Initramfs | systemd + `sd-encrypt` | [C] |
| Boot | Limine + limine-snapper-sync; text console, no Plymouth | [O+C] |
| Snapshots | snapper on `@`: before and after package changes, keep 5, no timeline | [O] |
| Swap | zswap (zstd) + swap file on `@swap` sized to RAM; no zram | [New] |
| /tmp | tmpfs, cap = RAM size, aged out after 10 days | [New] |
| Login | greetd auto-login → uwsm → Hyprland | [New] |
| Keyring | Open: oo7, or gnome-keyring + `pam_systemd_loadkey` | [New] |
| sudo / polkit | Shell polkit overlay; per-terminal sudo cache (10 min); fingerprint with lid gate on the laptop | [O] |
| Firewall | ufw deny incoming (+ rules for Podman as needed) | [O] |
| Network | NetworkManager + wpa_supplicant + systemd-resolved; no Omarchy connectivity URL | [O] |
| Bluetooth | bluez + shell panel | [O] |
| Printing + scanning | Optional feature (Settings › Printers & scanners), D-38 | [O] + [New] |
| Audio | PipeWire + WirePlumber | [O+C] |
| Laptop power | power-profiles-daemon (Arch) with amd-pstate; suspend on idle; suspend-then-hibernate after 2 h | [New] |
| Mirrors | rate-mirrors weekly with safety checks (D-29) | [C] tool, [New] safety |
| Dedup | bees on btrfs: an installer choice, off by default; 256 MB table; AC power only on laptops (D-39) | [New] |
| Secure Boot | sbctl + Microsoft keys, signed Limine, config hash enrollment (installer step) | [C] |
| Firmware | fwupd (menu entry) | [O] |
| AUR helper | paru (from `[cachyos]`) | [C] |
| Fonts | JetBrains Mono Nerd; Noto (+ CJK, emoji) | [O] |

## Desktop

| Area | Choice | Source |
|---|---|---|
| Compositor | Hyprland, Lua config with Omarchy's default/user layering and `o.*` helpers | [O] |
| Look | gaps 5/10, 2 px theme-accent border, square corners, no blur or shadow | [O] |
| Animations | Omarchy fast set, instant workspace switch | [O] |
| Layouts | Dwindle + per-workspace floating mode with `omarchy-hyprland-titlebars` | [O] |
| Workspaces | Per-monitor blocks of 10 | [O] |
| Special workspace | Drop-down terminal (no AI agent auto-start) | [O] |
| Opacity | Omarchy default (terminals 0.985/0.96) | [O] |
| Window rules | Omarchy tag system, pruned to installed apps | [O] |
| Idle | Shell screensaver + lock + screen off | [O] |
| Gestures | 3-finger swipe left/right = workspace | [O] |

## Shell (Omarchy Quickshell)

Kept:
- **Core:** host, IPC, plugin registry and CLI, bar engine, `omarchy` router, Commons and Ui, `shell.json`.
- **Services:** notifications (with the hover ✕), OSD, polkit, lock, idle, clipboard history, reminders, theme/background picker, speed tests, and the battery service (only on machines with a battery).
- **Menu:** the engine, used as the launcher (app search). The tree is in `menu.md`.
- **Bar modules:** workspaces, clock, tray, audio, microphone, network, Bluetooth, display brightness, power, media, and the indicators for kept features.
- **Proposed, needs user approval:** the active-window title module, and a pacman/paru update badge [New] to replace Omarchy's update badge.

Dropped: dock and app grid, emoji picker, intro animations and owe, night light, weather, world clock, AI usage, Tailscale, Dropbox, remote session, dev gallery.

## Theming

| Area | Choice | Source |
|---|---|---|
| Engine | Omarchy theme engine + templates | [O] |
| Themes | All 23 Omarchy themes + **nulifyer** (default) | [O] + [New] |
| GTK | `adw-gtk-theme` + a new `gtk.css.tpl` with theme colors for GTK3/4 | [New] |
| Qt | qtengine colors template | [O] |
| VS Code | Generated theme extension; `settings.json` never edited | [New] |
| fish prompt | Native prompt + theme-color template, fast git status, command duration and exit code | [New] |
| Terminal | foot include line | [O] |

## Apps in the base install

| Role | App | Source |
|---|---|---|
| Terminal | foot (server mode + footclient) | [O] |
| Browser | Brave Origin (`brave-origin-bin`, `[omarchy]`); PDFs open in the browser | [O] |
| File manager | Thunar + gvfs, gvfs-smb, gvfs-mtp, tumbler; right-click actions per D-36 | [New] |
| Default apps | Settings › Default apps, writing `mimeapps.list` (D-37) | [New] |
| Editor | VS Code (`visual-studio-code-bin`, `[omarchy]`) with the user's own settings | [O] |
| Terminal editor | micro or nano, still open | |
| Images | imv | [O] |
| Media | mpv with hardware decoding config | [O] |
| Task manager | btop | [O] |
| About | fastfetch | [O] |
| Screenshots | Omasnap (screenshot + annotation, `[omarchy]`), plus screen recording | [O] |
| Calculator | omacalc (`[omarchy]`) | [O] |
| Disk utility | GNOME Disks | [O] |
| File sharing | LocalSend (`[omarchy]`), port open only on trusted networks | [O] + [New] |
| Settings | karchy Settings window (shell plugin, D-27) | [New] |
| Web apps | Omarchy web-app mechanism, with fixed icons | [O] + [New] |
| Shell | fish, native config from the dotfiles user layer | [New] |
| Plugins | omarchy-vpn-plugin, omarchy-project-picker (Ctrl+Alt+P) | [New] |

## Mounts

- **USB:** udisks2 + udiskie automount with a notification [O].
- **Internal data disks:** fstab at `/mnt/<label>`, with `nofail` and `x-gvfs-show`, owned by the user, NTFS via `ntfs3`. The installer sets up existing ones; a notification offers new ones [New].
- **NAS:** browse via gvfs-smb. The Thunar action "Keep this mount" writes an fstab systemd automount (`nofail,_netdev,x-systemd.idle-timeout`) with root-only credentials; "Remove kept mount" undoes it [New].

## Install tiers (D-28)

**Always:**
- desktop portals (`xdg-desktop-portal-hyprland` + `-gtk`)
- `systemd-oomd`
- `fstrim.timer`, monthly btrfs scrub, `smartd` disk-health warnings
- `paccache` cleanup, `.pacnew` alerts (`pacdiff`)
- the rate-mirrors timer
- a default-apps list: links → Brave Origin, PDF → Brave Origin, images → imv, video and audio → mpv, folders → Thunar
- Thunar archive actions (`thunar-archive-plugin` + xarchiver + `7zip`) and the karchy right-click actions (D-36, D-40)
- `avahi` + `nss-mdns`
- LocalSend, GNOME Disks, omacalc, Omasnap
- `xdg-user-dirs`, `man-db`

**Detected at install:**
- CPU microcode (`amd-ucode` or `intel-ucode`).
- **NVIDIA GPU:** `linux-cachyos-nvidia-open` and `nvidia-utils`, `libva-nvidia-driver`, the NVIDIA suspend/resume/hibernate services.
- **Battery:** the shell battery service (low and critical warnings), suspend-then-hibernate, `tzupdate` automatic timezone, power-profiles-daemon.
- **Framework:** `framework-system` (charge limit, EC tools).
- **Fingerprint reader:** fprintd + PAM (D-14).
- **Firmware in Setup Mode:** the Secure Boot step (D-31).

**Installer choice:** bees dedup, off by default (D-39).

**Optional (Settings › Optional features):**
- Printers & scanners: CUPS + hardened cups-browsed, `sane`, `sane-airscan`, `simple-scan`, plus group setup (D-38).
- Home backup to the NAS (phase 7).

## Installed later by the user (not in base)

dotnet, go, zig, rust, bun, Podman, AI CLIs (from pacman, `[omarchy]` or the AUR), Steam, Flatpak, a password manager (the user's is Proton Pass).
