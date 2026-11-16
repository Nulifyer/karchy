# Chris Titus Tech's Linux setup: research for karchy

Researched 2026-11-14. Primary sources: his GitHub repos (shallow-cloned and read), the source of his website (`ChrisTitusTech/website`, which holds every christitus.com post and `data/livestreams.json`), and the auto-generated YouTube captions of five streams and videos. Caption quotes are from automatic speech recognition, so wording is approximate.

## 1. His current Linux setup

### He is moving from Arch to Fedora

- **January 2026, "How I Switched to Linux"** (https://christitus.com/how-i-use-linux/): Arch Linux with the CachyOS kernel, DWM ("116KB binary"), Thunar, 628 days of uptime, 80% of his gaming on Linux through Proton, and "Windows Work: Optimized VM". He still uses X.org and says most users should use Wayland.
- **April 2026, "Top Linux Distros"** (https://christitus.com/top-linux-distros/): "I personally use cachy repos on Arch".
- **June 2026, "Switch From Arch to Fedora"** (https://christitus.com/switch-from-arch-to-fedora/): written after the June 2026 AUR malware incident. Fedora has better default security (SELinux, firewalld, signed repos, a predictable release cycle). Arch is still fine if you read the news, review AUR diffs and keep snapshots.
- **dwm-titus is now a Fedora-only distribution** (https://github.com/ChrisTitusTech/dwm-titus, release 0.8, Fedora 45 ISOs, docs at https://dwm.christitus.com). Main features:
  - X11 dwm plus a Quickshell panel, launcher, Control Center and Settings
  - Live-reloading TOML hotkeys, themes and window rules
  - A searchable window overview (Super+Tab) and a keybind viewer (Super+/)
  - A display wizard, Picom settings, 15 theme presets, gnome-keyring
  - An on-demand System Health dashboard
  - Install profiles `core`, `recommended` and `full`
- I could not confirm whether his own workstation now runs Fedora or still runs Arch.

### Linutil

Linutil (https://github.com/ChrisTitusTech/linutil, run with `curl -fsSL https://christitus.com/linux | sh`) is a Rust TUI over shell scripts in `core/tabs/`, with five tabs:

- **System Setup**
  - Arch: CachyOS repo and kernel, Chaotic-AUR, DWM-Titus, JaKooLit Hyprland, Omarchy, the linux-neptune kernel, NVIDIA drivers, pacman.conf tweaks (Color, ILoveCandy, ParallelDownloads, multilib, MAKEFLAGS), paru or yay, Snapper (hourly snapshots, snap-pac, GRUB entries), maintenance (`paccache.timer`, orphan removal, 30-day journal vacuum), Virtualization, and a minimal server setup.
  - Fedora: RPM Fusion, codecs, DNF tweaks, btrfs-assistant, release upgrade.
  - Any distro: DE and WM install and uninstall, fstrim, gaming dependencies, GPU drivers, global theme, PipeWire, snap removal, cleanup, update (also through topgrade), Terminus TTY font at size 32, zram.
- **Applications:** browsers (including Brave Origin), communication apps, design tools, dev tools, office suites, PDF readers, Docker, Podman, Flatpak, Waydroid, terminals, mybash, zsh, fastfetch, the DankMaterial and Noctalia shells, a GRUB theme.
- **Gaming:** Steam, Lutris, Heroic, RetroArch, many emulators, ProtonPlus, ProtonUp-Qt, plus his own game mods (Arc Raiders, D2R, Fallout 76, Starfield, EverQuest MIDI). The Arch gaming dependencies are multilib, lib32 audio and Vulkan libraries, `vulkan-radeon`, `gamescope`, `mangohud`, `gamemode` and `wine`.
- **Security:** UFW and firewalld baselines, an on-demand Lynis audit, an rkhunter scan.
- **Utilities:** monitor control, printers, a user account manager, auto-login, Bluetooth and Wi-Fi TUIs, a bootable USB creator, numlock at boot, Ollama and Ramalama, a service manager, SSH and Samba, Timeshift.

### Other repos

| Repo | What it is |
|---|---|
| https://github.com/ChrisTitusTech/hyprland-titus | 2023 Hyprland dots (waybar, rofi, Nordic). Stale |
| https://github.com/ChrisTitusTech/omarchy-titus | 2025 overrides of DHH's Omarchy: gaps and borders at 0, blur off, `compose:caps`, repeat rate 40/600, touchpad scroll 0.4, Super+letter app and web-app binds |
| https://github.com/ChrisTitusTech/quickshell | Small 2025 Hyprland bar |
| https://github.com/ChrisTitusTech/mybash | bash, Starship, fzf, zoxide, fastfetch, `trash` instead of `rm` |
| https://github.com/ChrisTitusTech/neovim | kickstart.nvim-based; also has a Thunar `uca.xml` with actions "Copy image to clipboard" and "Open terminal here" |
| ArchTitus, Debian-titus, nixos-titus, secure-linux | ArchTitus is an automated Arch install. secure-linux is UFW, fail2ban and host.conf |
| https://github.com/ChrisTitusTech/Path | His own Rust file manager for X11 (Fedora COPR) |
| https://github.com/ChrisTitusTech/image-tools | Thunar resize, upscale and WebP actions |

## 2. The "Windows on a workspace" setup

**Mechanism: dual-GPU VFIO passthrough with Looking Glass, opened full-screen by a hotkey on the current workspace.** It is not single-GPU passthrough. He rejects that because you lose the Linux desktop while the VM runs ("pointless… just dual boot"). It is not a SPICE or virt-manager window, and not WinApps (that came later as an add-on, see below).

### Sources

- "The Ultimate System" post (2024-03-20): https://christitus.com/the-ultimate-system/
- Its walkthrough video: https://www.youtube.com/watch?v=zq6yvQifyDw. This is the likely video you remember: "when I'm on a different workspace and I just launch Windows… I just made a hot key so anytime I press Windows W it launches into windows".
- The three setup streams:
  - Arch install: https://www.youtube.com/watch?v=Y7LTdEwR9M8
  - QEMU and Windows: https://www.youtube.com/watch?v=K2gliga5Vwc
  - Looking Glass: https://www.youtube.com/watch?v=01R8Ft1BdxE
- Rebuild on new hardware (2025-10-09), "Repair Bootloader and VFIO Passthrough Enable with Looking Glass": https://www.youtube.com/watch?v=mvbN8-pTMk8
- "Modifying DWM-Titus" (2024): https://www.youtube.com/watch?v=hzMJ2a1G8rc. It shows Windows installing programs on workspace 5 while he works on others.
- Still shipped as a default today: `dwm-titus/config/hotkeys.toml` has
  `{ mod="SUPER", key="w", desc="Looking Glass (VM)", func="spawn", cmd="looking-glass-client -F" }`
- Older background: https://christitus.com/windows-inside-linux/ and https://christitus.com/vm-setup-in-linux/

### How it works

- **Host GPU and guest GPU:** the host uses an AMD card (RX 7800 XT). The guest gets an NVIDIA card through VFIO (RTX 2060 in 2024, GTX 1660 in the 2025 rebuild). He binds it with HikariKnight's quickpassthrough (https://github.com/HikariKnight/quickpassthrough, v2.1.5, still maintained). That tool blacklists the card's drivers, adds vfio-pci IDs and edits kernel options and the initramfs.
- **Display:** an HDMI dummy plug in the guest GPU makes Windows render a 4K desktop. The Looking Glass host app (installed in Windows as an auto-start service) copies frames into shared memory.
  - 2024 method: IVSHMEM at `/dev/shm/looking-glass`, 32 MB for 1080p (more for 4K or HDR).
  - 2025 method: the KVMFR kernel module (`/dev/kvmfr0`), a udev rule for permissions, and `/dev/kvmfr0` added to `cgroup_device_acl` in `/etc/libvirt/qemu.conf`. The missing cgroup entry was the bug he hit on stream.
  - `looking-glass-client -F` shows the frames full-screen at near-native latency.
  - A QXL virtual display is kept as a fallback: Windows is set to "show only on" the NVIDIA display, so Looking Glass keeps working through driver updates or if the GPU fails.
- **Input:** goes through SPICE inside Looking Glass. He adds a virtio keyboard and mouse (the PS/2 ones must stay) and removes the tablet device. Scroll Lock toggles exclusive capture, for games. Scroll Lock+O opens the overlay (FSR upscaling and other options). Settings go in `~/.config/looking-glass/client.ini`.
- **Audio:** goes through SPICE too. Looking Glass B7 handles speaker and microphone ("it supports audio and mic now"), using an Intel HDA device in the VM.
- **Storage:** a whole NVMe passed through as a PCI device. His existing bare-metal Windows install was moved into the VM.
- **USB:** a dedicated PCIe USB card passed through for real USB devices, such as a YubiKey needed in Windows.
- **Network:** bridged to the LAN rather than NAT, so VNC and RDP reach the guest.
- **Friction removal:**
  - The VM starts at boot. His post writes `sudo virsh enable win11`, which is not a valid virsh command; the right one is `virsh autostart win11`.
  - Windows logs in automatically and Looking Glass host starts on its own.
  - Super+W opens the client on whatever tag he is on, so "a workspace is Windows" just means the client is full-screen on that workspace. Switching workspaces leaves Windows running.
- **Hardware he lists:**
  - two GPUs
  - a high-end motherboard with clean IOMMU groups (cheap boards and laptops often fail)
  - only full-performance cores, no efficiency cores (a Xeon w5-3435X, 16 cores; he says a Ryzen 5600X also worked)
  - at least 64 GB of RAM (16 GB for the VM)
  - two NVMe drives
  - many PCIe slots
- **Wayland notes:** his attempt on KDE Plasma 6 Wayland (2024) had capture-card flicker, and his AUR client ran under XWayland. He went back to X11 dwm. This was his setup, not a Looking Glass limit: the client has a native Wayland backend. I did not test it on Hyprland.

### Later add-on: WinApps

Stream "I Ran Windows Apps Inside Linux (Without A VM Window)", 2026-04-30: https://www.youtube.com/watch?v=0C_R_e2LbB0

- He pointed WinApps (FreeRDP RemoteApp) at the same passthrough VM, so single Windows apps (WinUtil, VS Code) open as normal windows in dwm.
- He needed a static IP, RDP enabled, a password plus auto-login, and `LIBVIRT_DEFAULT_URI=qemu:///system`.
- He rejected WinBoat as laggy.
- He claims WinApps works only on X11. Its README depends on `freerdp3-x11`, so on Wayland it would run under XWayland. I did not verify that.

### Published scripts

- No passthrough scripts are published anywhere. Linutil's Virtualization entry only installs `qemu-desktop`, `qemu-emulators-full`, `swtpm`, `libvirt`, `dnsmasq`, `iptables-nft` and `virt-manager`, sets polkit auth, adds the user to the libvirt and kvm groups, adds the NSS `libvirt` modules and autostarts the default network.
- None of his VM XML is published.

### WinUtil for the guest

WinUtil (https://github.com/ChrisTitusTech/winutil, `irm https://christitus.com/win | iex`) applies debloat presets inside the guest. Its "Win11 Creator" builds a trimmed ISO from an official one: it removes bloat apps, bypasses TPM, Secure Boot and CPU checks, sets up a local account through `autounattend.xml`, disables BitLocker, and can inject drivers. That makes it a good source for the guest's installer.

### Fit for your current machine

I checked this machine read-only:

- one RTX 5080, in IOMMU group 23 with only its own audio function, so it is clean
- a Ryzen 7 3700X with no integrated GPU
- 31 GiB of RAM
- 3 USB controllers

His model needs a second GPU for the host, for example a cheap AMD card for Linux with the 5080 passed through, or the other way round. RAM is below his 64 GB recommendation.

Without a second GPU, two options work today:

- a SPICE or virtio VM full-screen on a pinned workspace, with no 3D in the Windows guest
- WinApps over RDP

### For karchy, if adopted

Make it an Optional feature, not part of the base. It would need:

- `qemu-desktop`, `libvirt`, `virt-manager`, `edk2-ovmf`, `swtpm` and `dnsmasq` from the Arch repos
- `looking-glass` and `looking-glass-module-dkms` from the AUR (version B7; neither is in the configured repos)
- a window rule that sends `looking-glass-client` to a fixed workspace full-screen, plus a Super+W bind
- `virsh autostart`

## 3. Other ideas to compare with karchy

The verdicts are judged against "minimal software, but basic things just work". Items karchy already has are left out: keybind viewer, numlock, pacman tweaks, ufw, snapshots, paccache, fstrim, Thunar actions, web apps, the CachyOS kernel.

| Idea (source) | Borrow? |
|---|---|
| On-demand System Health page: current-boot journal and kernel errors, failed units with restart buttons, disk, inode and SMART data, missing dependencies, no idle polling (dwm-titus SPEC §5.9) | **Yes, a small version** in Settings › About. Debugging is a basic need, and on demand it costs nothing at idle |
| Gaming as an Optional feature: multilib, Steam, the lib32 Vulkan driver for the detected GPU, gamemode, optionally mangohud and gamescope (linutil `gaming-setup.sh`) | **Yes.** A missing lib32 Vulkan driver is the classic way Steam "doesn't just work". Today karchy leaves Steam to the user |
| `protonrestart`, which kills stuck wine, Proton, Steam and CEF processes (dwm-titus `scripts/protonrestart`, Super+Ctrl+R) | Maybe, only with the gaming feature. Tiny and useful, but niche |
| Windows VM with Looking Glass on a hotkeyed workspace (section 2) | Optional feature, gated on detecting two GPUs. High value for the user, but it needs AUR packages and is fragile |
| Searchable window overview across workspaces (Super+Tab in dwm-titus) | Maybe later. Useful with 10 workspaces per monitor, but it is new shell code |
| Terminus TTY font at size 32 (linutil `terminus-tty.sh`) | **Yes, for HiDPI.** karchy uses a text console and a LUKS prompt with no Plymouth. One package and a `vconsole.conf` line (the sd-vconsole hook puts it in the initramfs) |
| VRR (his Xorg VRR post; Hyprland's `misc:vrr`) | **Yes, as a setting.** Default to full-screen-only VRR; one config line |
| `ufw limit 22/tcp` and fail2ban (secure-linux, linux-security-mistakes post) | `limit 22/tcp` yes, when karchy's sshd option is turned on. fail2ban no: it is for servers |
| Review AUR diffs and prefer repos (Fedora switch post) | **Yes, as policy.** Keep paru's diff review on and keep karchy's own packages in repos |
| Systemd user services for daily jobs, and autostarting the VM (Ultimate System post) | No change: a pattern, not a feature |
| Tuned NFS mount options: `hard,nofail,noatime,x-systemd.automount,_netdev,nfsvers=4.1` (fix-nfs post) | Only if "Keep this mount" adds NFS. karchy's SMB automount already follows the same idea |
| Bridge networking for VMs | Only inside the VM feature (NetworkManager bridge) |
| Topgrade, Timeshift, zram, Chaotic-AUR, Lynis and rkhunter, Waydroid, Input Leap or Deskflow, Ollama | No. karchy already covers these (`karchy update`, snapper, zswap) or they are niche |
| mybash, Starship, zoxide, fzf, `trash` for `rm` | No. karchy uses a native fish config |
| IPv4 precedence in `gai.conf` | No. It is a workaround for broken networks, not a default |

## Not confirmed

- Which video you saw. The likely one is "The Ultimate System" (zq6yvQifyDw); the WinApps stream is also possible.
- Whether he still runs the passthrough VM daily on his current OS.
- Any CPU pinning, hugepages or anti-cheat VM hiding. He declined to share details on stream.
- That the Looking Glass client and WinApps behave well on Hyprland. Not tested.
- Whether YouTube video descriptions match the stream listings in `livestreams.json`. I did not check that separately.
