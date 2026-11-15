# Windows on karchy: options, hardware fit, disk sharing, workspace integration

Research date: 2026-11-14. Evidence labels used below:

- **[local]**: checked read-only on this desktop during this session.
- **[primary]**: read from the project's own repo, docs, or release notes.
- **[reported]**: forum posts, news articles, or secondary write-ups. Not reproduced here.
- **[inference]**: my reasoning from the above. Not tested.

## 0. Desktop facts that change the answer [local]

| Item | Finding |
|---|---|
| Motherboard | **ASUS ROG STRIX X570-I GAMING, a mini-ITX board with a single PCIe x16 slot.** A second full-size GPU will not fit. |
| CPU | Ryzen 7 3700X, 8 cores and 16 threads, AMD-V. No iGPU. |
| GPU | RTX 5080 (GB203, `10de:2c02`) plus HDMI audio (`10de:22e9`). Both functions sit alone in **IOMMU group 23**, so the group is clean for passthrough. `reset_method` = `flr bus`. |
| RAM | 31 GiB total. Roughly 16 GiB was in use during the check. |
| System disk | Samsung NVMe, LUKS, btrfs (`@`, `@home`, ... with `compress=zstd:1`). Snapper 0.13.2 is installed. |
| Data disk | `sda1`, ext4, label `BIG`, 3.6 T, mounted at `/mnt/big`, on the chipset SATA controller (IOMMU groups 19 and 20). |
| Virt stack installed | qemu-base 11.1.3, libvirt 12.9.0, edk2-ovmf 202608 (includes `OVMF_CODE.secboot.4m.fd`), swtpm 0.10.2, virtiofsd 1.14.0. Looking Glass and FreeRDP are **not** installed. |
| VM image dir | `/var/lib/libvirt/images` already has the btrfs `C` (nocow) attribute. It is **not** its own subvolume (its inode is not 256), so it lives inside `@`. |
| Secure Boot firmware | The libvirt firmware descriptor `50-edk2-ovmf-x86_64-secure-4m.json` lists `secure-boot` and `requires-smm`. It does **not** list `enrolled-keys`. Arch ships no VARS template with Microsoft keys enrolled (see section 4). |
| Kernel | 7.3.3-cachyos. `ntsync.ko` is present and `/dev/ntsync` exists. No `nova_core` module is built, so the nova_core/vfio race reported on other distros does not apply here. |
| Existing VMs | `windows-privacy-research` (qcow2 under `~/Projects/FilePilot/...`, SPICE, VGA, 4 GiB) and several Linux NT test VMs. |

## 1. Options compared

| Option | What it is | Does the app see real Windows? | GPU acceleration | Kernel anti-cheat / DRM | Works well | Breaks | Setup | Cost |
|---|---|---|---|---|---|---|---|---|
| **Wine / Proton / Bottles / Lutris** | A user-space reimplementation of the Win32/NT API on the Linux kernel. **This is the only mature "Windows on the same kernel".** | No. Apps see Wine's DLLs. Most apps can't tell; some check (`wine_get_version`, registry, driver queries). | Native host GPU. DXVK (D3D8–11) and VKD3D-Proton (D3D12) translate to Vulkan on the RTX 5080. Close to native, and often faster. | User-mode EAC and BattlEye work when the developer enables the Proton module. Kernel drivers (Vanguard, Javelin, Ricochet) cannot load. areweanticheatyet lists 1,167 titles: 17% supported, 24% running, 54% broken, 5% denied (Fortnite, Valorant, Apex, BF2042, R6 Siege). | Most Steam games. Many utilities. Older Office versions with effort. | Microsoft 365 or Click-to-Run (installer, activation, WebView2), Adobe CC (installer and licensing), kernel-driver software, Store and UWP apps. | Low | Lowest: no second OS |
| **Windows VM, full GPU passthrough (VFIO)** | Real Windows in KVM that owns the physical GPU. | Yes. It is real Windows, and NVIDIA's normal driver runs in it. NVIDIA has allowed GeForce passthrough since driver 465 (no more Code 43). | Native, a few percent below bare metal. | Many games work. Vanguard, FACEIT, and Javelin look for VMs, and EA lists "Virtual Machines" as a Javelin target. BF6 also requires Secure Boot plus TPM. Expect some titles to refuse. | Everything, including Office, Adobe, CUDA, and most games. | VM-hostile anti-cheat. Blackwell reset quirks (section 2). | High | One whole GPU, about 8–16 GiB RAM, and cores |
| **Single-GPU passthrough** | Same as above, but the host gives up its only GPU while the VM runs. | Yes | Native | Same as above | Same as above | The host desktop disappears (Hyprland must exit). No Linux GPU work while the VM runs. | High, fragile | Same as above |
| **Looking Glass** | Sends the frames of a passthrough-GPU VM to a host window over shared memory (IVSHMEM/KVMFR). | Yes | Native in the guest, but **needs a guest GPU**. B8-rc1's IDD has a software fallback "for word processing and spreadsheets". | Same as passthrough | Low-latency viewing in a host window, with clipboard and audio | It needs a second GPU in practice, and the host also needs a GPU for its own display. | High | Same as passthrough, plus some host CPU and bandwidth |
| **virtio-gpu 3D for Windows guests (virgl / Venus)** | Paravirtual GPU. The guest's API calls are serialised and run by the host's driver, and the host keeps the GPU. | Yes, real Windows. It sees a virtual GPU. | **Experimental in 2026.** (a) viogpu3d/virgl (D3D10 over GL): PR #943 is still unmerged, and "Triton" v0.3 (2026-09) says NVIDIA hosts fail because of a virglrenderer `GL_PRIMITIVE_RESTART_NV` bug. (b) **WinBoat Helios**: a WDDM KMD plus a DXVK/vkd3d UMD over Mesa Venus. The README says "HEAVY DEVELOPMENT… NOWHERE PRODUCTION READY". (c) **VMVGA** (qemus): VMware SVGA3D emulation rendered through host dxvk-native. (d) VMLabDev/vmlab-win3d is a new one-star repo. Venus lists NVIDIA proprietary ≥ 570.86 as a tested host. | Same as a VM, and likely worse because there is no real GPU | Desktop composition and light 3D, when it works | Electron and VS Code black windows, WinUI3 flicker, BSODs (viogpu3d). Nothing is production-ready. | Medium (dockur `GPU=Y`) to high | Shares the GPU, so cheap |
| **NVIDIA vGPU / SR-IOV on RTX 50** | Hardware or mediated GPU partitioning | n/a | **Not possible.** NVIDIA supports it on datacenter and RTX PRO Blackwell only. `bird/vgpu-unlock-blackwell` reports the GSP crashing on fused-off VF registers (Xid 119) and calls it hardware-blocked. | | | | | |
| **AMD SR-IOV / GIM on consumer APUs** | AMD's open GIM module (April 2025) | n/a | **Not possible today.** It targets Instinct only. Radeon client support is "in the roadmap", and nothing mentions APUs. | | | | | |
| **Intel GVT-g / SR-IOV** | iGPU partitioning on Intel | n/a | Not applicable: neither machine has an Intel GPU. | | | | | |
| **RDP RemoteApp integration (WinApps, WinBoat, Cassowary)** | A Windows VM (libvirt or dockur) whose apps appear as single Linux windows through FreeRDP RemoteApp | Yes, real Windows | Whatever the VM has. Without a GPU, RDP uses software rendering (WARP). | Kernel anti-cheat is explicitly unsupported (WinApps README). | Office 2016–365, Adobe CC, Visual Studio, Fusion 360 (WinApps community list) | Games and latency-sensitive work. Some multi-monitor black screens (FreeRDP bug). Cassowary has had no commits in roughly 2–4 years. | Medium. WinBoat is the easiest and still beta. | About 4–8 GiB RAM, plus the VM |
| **dockur/windows ("Windows in Docker")** | **A full QEMU/KVM VM inside a container**, not a Windows container. The image copies the `qemux/qemu` userland and a custom `qemux/qemu-windows` `qemu-system-x86_64` binary. It needs `/dev/kvm`. | Yes, real Windows, a separate kernel | Off by default. `GPU=Y` turns on Venus (virtio-gpu-gl) or VMVGA + DXVK. NVIDIA goes through the Container Toolkit with ≥ 570.86. Experimental. | Same as a VM | Unattended install, RDP on 3389, web VNC on 8006, Samba `Shared` folder as `Z:`, disk and USB passthrough | Same as a VM | Low | Same as a VM, with a 64 GB default disk |
| **Windows NT on the Linux kernel ("Linux NT")** | NT semantics inside the Linux kernel so that unmodified binaries and drivers run | | | | | | | |
| - NTSync | NT sync primitives as a Linux driver (mainline since 6.14; used by Wine 11.0, released 2026-01-13) | | Speeds up Wine | No | | | | |
| - Wine NTOSKRNL | Wine 11.18 (2026-09) extends its `ntoskrnl.exe`/winedevice for PnP and kernel drivers. Wine docs say native kernel drivers can't run in general. | | | Not for anti-cheat | | | | |
| - Longene / LUK | NT kernel mechanisms as Linux modules, with Wine user-space DLLs | | | | | **Dead since 1.0-rc2 (2014).** | | |
| - Neptune OS | An NT personality on **seL4**, not Linux. Active (pushed 2026-11-14). Early stage. | | | | | | | |
| - ReactOS 0.4.15 (Mar 2025), LiberNT | Standalone NT clones, not on Linux. LiberNT targets Win11 compatibility, builds with RosBE (so it is probably ReactOS-lineage; that lineage is my inference), and ships debug pre-releases. | | | | | | | |
| - "Line", "WSL in reverse" | Line ran Linux ELF binaries on Windows, the opposite direction, and is long dead. No Microsoft "WSL in reverse" exists. Wine plus NTSync is the de facto version. | | | | | | | |

**"Container on the same kernel" answer.** A "Windows container" that runs on the Linux kernel, where unmodified apps believe they are on Windows, **does not exist** outside Wine. Wine *is* that idea, implemented in user space. dockur, WinBoat, and WinApps all run a **separate Windows kernel in KVM**. A same-kernel design *would* make GPU sharing trivial: that is exactly why Wine and Proton get native DXVK and VKD3D performance. The cost is compatibility: no kernel drivers, so no kernel anti-cheat, no driver-based DRM, and gaps in Office and Adobe installers.

## 2. What is realistic on this hardware

### Desktop (X570-I, 3700X, single RTX 5080)

1. **Wine/Proton for games, plus a GPU-less VM for apps.** This is the practical baseline today. Proton on the 5080 covers games that do not use kernel anti-cheat. A small Windows VM (no GPU, SPICE or RDP) covers Office and Adobe through WinApps or WinBoat RemoteApp, or as a full-desktop window on its own workspace. The VM has no 3D, which is fine for Office and adequate for light Adobe use; Premiere and After Effects will crawl.
2. **Single-GPU passthrough: possible but disruptive.** The GPU's IOMMU group is clean [local]. A libvirt hook must stop Hyprland and the Quickshell session (not just a display manager), stop `nvidia-persistenced`, unload `nvidia_drm`, `nvidia_modeset`, `nvidia_uvm`, and `nvidia`, then bind `vfio-pci`. Afterwards it reverses all of that. Both monitors go to Windows. Linux has no GUI while the VM runs, so the Windows session is not a Hyprland workspace in this mode. Blackwell risks [reported]: the RTX 5090 and PRO 6000 FLR hang needs a host reboot to recover (CloudRift; heise; NVIDIA bug bounty; an unmerged LKML patch, 2026-04, to skip FLR on the 5090). A 5080 instance was not found, but GB203 users have hit other failures (Proxmox iommufd ENODEV; kernel 7.2 regressions on a 5090M). Workarounds people use: clear `reset_method`, `vfio_pci.disable_idle_d3=1`, `d3cold_allowed=0`, and `x-no-geforce-quirks=on`. Expect to debug this.
3. **A second GPU in a second slot is not an option.** The board is mini-ITX with one slot. The workarounds are:
   - **(a) Swap the 3700X for a Ryzen 5000G APU (for example a 5700G).** The board has rear HDMI 2.0b and DP 1.4 for an APU. ASUS lists iGPU support for 2000G, 3000G, and 4000G. **5000G support was not confirmed** from the pages read, so check the ASUS CPU support list for BIOS 5044 (the installed version). After the swap, Hyprland runs on the iGPU and the 5080 goes to the VM with Looking Glass on its own workspace. That gives a real "Windows workspace with full GPU". Costs: the APU limits the GPU to PCIe 3.0 x16 and has less L3 cache than the 3700X, and Linux gaming on the 5080 then needs PRIME offload or rebinding the card when the VM is off [inference].
   - **(b) An M.2-to-PCIe/OCuLink adapter and a small external GPU** in the second M.2 slot (PCIe 3.0 x4). Hacky, and it costs that NVMe slot.
   - **(c) Move to a board with two slots.**
4. **Looking Glass without a second GPU:** in practice, no. The host needs a GPU for its own display while the 5080 is inside the VM. With single-GPU passthrough there is no host display left to show the Looking Glass client. B8-rc1's IDD software fallback still requires the VM to have *some* display path. It is meant for basic apps and does not solve GPU sharing [primary].
5. **Sharing the one RTX 5080 between host and Windows in 2026.** vGPU and SR-IOV are hardware-blocked on GeForce Blackwell [reported, consistent with NVIDIA's docs]. The only route is **API forwarding**: Venus-based Helios, or VMVGA/DXVK, through dockur (`GPU=Y`, NVIDIA ≥ 570.86) or a custom QEMU. This is real and moving fast, but it is pre-release, AI-built, and unsupported, and NVIDIA host paths have known bugs. Treat it as something to watch, not something to build karchy on.

### Laptop (Framework 13 AMD, iGPU only)

- Passthrough is impossible, because the only GPU drives the panel.
- Wine/Proton on RADV is the main path.
- Windows apps go through a GPU-less VM or dockur with WinApps or WinBoat.
- Paravirtual 3D (Venus/Helios, VMVGA) is *best* tested on RADV hosts (Venus docs list RADV ≥ 21.1). The laptop is therefore the better test bed for Helios once it ships [inference].
- AMD GIM/SR-IOV does not cover APUs.

## 3. Sharing the ext4 `BIG` disk with Windows

- **Windows cannot read ext4 natively.** WSL2's `wsl --mount` would need nested virtualisation inside the guest. Third-party ext4 drivers exist but are risky.
- **Raw disk or partition passthrough: avoid** while the host mounts `/mnt/big`. Two kernels with independent page caches and journals writing one non-cluster filesystem will corrupt it. Passthrough is only safe if the host unmounts it first (for example with a systemd mount conflict), and Windows still can't read ext4, so it would offer to format the disk.
- **virtiofs** (host `virtiofsd` 1.14 is installed): host-owned and safe for concurrent use. Libvirt needs `<memoryBacking><source type='memfd'/><access mode='shared'/>`. The guest needs WinFsp plus the virtio-win `VirtioFsSvc`, and gets `Z:` by default.
  - Caveats [primary + reported]: set `FileSystemName=NTFS` for admin executables. Some apps treat the share as a network drive. Heavy I/O on large trees has caused non-paged pool growth and virtiofsd open-file limits (virtio-win #1136). Saving with memory and snapshots are limited. Reported to be faster than SMB for many small files.
- **Samba from the host:** the most compatible and mature option. It works with dockur, WinApps, and RDP setups alike (dockur already embeds Samba). It is slower and some apps reject network paths.
- **9p:** no Windows guest driver. Not an option.
- **Steam libraries:** reports show Steam accepts virtiofs or SMB libraries but games can fail to launch (Factorio on virtio-fs) [reported]. Do not share the Proton Steam library live with a Windows Steam.

**Recommendation.** Use **virtiofs** for data folders on `BIG`, with Samba as a fallback for anything that misbehaves. For Windows *games*, put a separate sparse raw or qcow2 image file on `/mnt/big/vm/` and format it NTFS inside Windows. That is safe because the host only ever sees a file, and it keeps the NVMe system disk small.

## 4. Small Windows system disk on btrfs NVMe; TPM and Secure Boot

- **Format.**
  - **raw** (sparse, `fallocate` or `qemu-img create -f raw`) is the simplest and fastest. Snapshots then come from the host.
  - **qcow2** adds internal snapshots and backing chains, at a small overhead cost.
  - Either way, use virtio-blk or virtio-scsi with `cache='none'`, `io='native'` or `io_uring`, and `discard='unmap'` so TRIM shrinks the file.
- **btrfs.**
  - Keep `+C` (nocow) on the directory *before* creating images. It is already set on `/var/lib/libvirt/images` [local]. Nocow turns off btrfs checksums and compression for those files.
  - **Make it a dedicated subvolume** (for example `@vm` mounted at `/var/lib/libvirt/images`), because today the directory is inside `@` and so inside root snapshots [local]. Snapper does not cross subvolume boundaries, which excludes it automatically.
  - Snapshotting a nocow file forces copy-on-write on the next write, which causes fragmentation and lost space. That is another reason to keep VM images out of snapper.
- **Size.** Microsoft's Windows 11 minimum is 64 GB, and dockur's default is 64 GB. Plan on **80–100 GB** for the OS, updates, Office, and Adobe, with games and data kept on `BIG`.
- **TPM.** Use swtpm (installed): `<tpm model='tpm-crb'><backend type='emulator' version='2.0'/></tpm>`.
- **Secure Boot.**
  - Use `OVMF_CODE.secboot.4m.fd` on Q35 with SMM. With `<os firmware='efi'>`, libvirt auto-selects the descriptor.
  - Arch's VARS template has **no Microsoft keys enrolled** [local], so Secure Boot sits in setup mode. That is enough for the Windows 11 installer, but titles that check for Secure Boot *enabled* (BF6/Javelin, CoD BO7, Vanguard) need keys. Enrol them with `virt-fw-vars` (python `virt-firmware`) using MS keys [inference: standard practice, not tested here].
  - dockur switches to "windows_secure" mode (Secure Boot plus TPM) for Windows 11 automatically [primary].

## 5. Making it a Hyprland workspace

| Display path | How it maps to a workspace | Input capture/release | Clipboard | Audio | Multi-monitor |
|---|---|---|---|---|---|
| **QEMU GTK/SDL window** (`-display gtk,gl=on`) | A `windowrule` sends it to `workspace special:win` or `9` | Ctrl+Alt+G grabs. On Wayland the grab depends on the keyboard-shortcuts-inhibit protocol, and Hyprland's own binds can be swallowed. A Hyprland forum thread uses a passthrough submap or bypass rule. | None without SPICE | PipeWire backend | One window per head |
| **SPICE (virt-viewer / remote-viewer)** | Window rule, or fullscreen on a workspace | Auto-grab inside the window, Shift+F12 releases. Inhibit behaves as above. | Yes (spice-vdagent) | Yes | Multi-head is supported |
| **Looking Glass client** (needs a passthrough GPU) | A native Wayland client, set with a window rule | Scroll Lock toggles capture. B8 improves "automatic keyboard capture and X11/Wayland input parity" and pointer confinement. | B8: bidirectional text, images, and files over LGMP. B6/B7: through SPICE. | B6+: SPICE audio. B8: emulated USB Audio Class 2. | One captured display per client. B8 is still an rc (2026-11-06) and needs matching IDD and client versions. |
| **RDP full desktop** (sdl-freerdp3 or xfreerdp3 `/dynamic-resolution /gfx:AVC444`) | Window rule. RemoteApp mode (WinApps or WinBoat) instead gives per-app windows. | No hard grab, so host binds keep working unless the client inhibits them | Yes | Yes (`/sound`) | `/multimon` exists, but WinApps notes FreeRDP multi-monitor black-screen bugs |

Suggested shape for karchy:

- On the desktop today: a GPU-less libvirt VM with SPICE or RDP on a dedicated (special) workspace, plus WinApps for per-app launchers. Keep Proton as the gaming path.
- If the user wants a full-GPU Windows workspace, the clean route is an APU swap plus Looking Glass B8. Single-GPU passthrough only works as a "switch the whole machine to Windows" mode.

## Sources

- dockur/windows: https://github.com/dockur/windows, [Dockerfile](https://raw.githubusercontent.com/dockur/windows/master/Dockerfile), [src/display.sh](https://raw.githubusercontent.com/dockur/windows/master/src/display.sh), [docs/environment.md](https://raw.githubusercontent.com/dockur/windows/master/docs/environment.md)
- qemux/qemu-windows: https://hub.docker.com/r/qemux/qemu-windows
- qemux/qemu-helios: https://hub.docker.com/r/qemux/qemu-helios
- WinBoat Helios: https://github.com/winboat-org/helios
- qemus/qemu-vmvga: https://github.com/qemus/qemu-vmvga
- VMLabDev/vmlab-win3d: https://github.com/VMLabDev/vmlab-win3d
- WinApps: https://github.com/winapps-org/winapps
- WinBoat: https://github.com/TibixDev/winboat (now winboat-org)
- heise on WinBoat 0.9: https://heise.de/-11089324
- The Register on WinApps and WinBoat: https://www.theregister.com/2026/02/14/winapps_and_winboat/
- Cassowary: https://github.com/casualsnek/cassowary
- viogpu3d PR #943: https://github.com/virtio-win/kvm-guest-drivers-windows/pull/943
- Triton v0.3: https://www.linuxcompatible.org/story/triton-v03-lands-critical-fix-for-directx-gpu-acceleration-in-qemu-kvm-windows-vms/
- Mesa Venus: https://docs.mesa3d.org/drivers/venus.html
- Collabora, state of virglrenderer: https://www.collabora.com/news-and-blog/blog/2025/01/15/the-state-of-gfx-virtualization-using-virglrenderer/
- Looking Glass: [requirements (master)](https://raw.githubusercontent.com/gnif/LookingGlass/master/doc/requirements.rst), [releases (B6, B7, B8-rc1)](https://github.com/gnif/LookingGlass/releases), [B7 requirements](https://looking-glass.io/docs/B7/requirements/)
- Level1Techs, dual-Blackwell VFIO and Looking Glass on CachyOS 7.1: https://forum.level1techs.com/t/vfio-looking-glass-with-two-nvidia-blackwell-gpus-on-cachy-os-linux-7-1-amd-zen-5-cpu-x670e-motherboard/252871
- Blackwell reset bug: [Tom's Hardware](https://www.tomshardware.com/pc-components/gpus/rtx-5090-pro-6000-bug-forces-host-reboot), [heise](https://heise.de/-10636857), [LKML FLR patch](https://lkml.iu.edu/2604.2/00149.html), [Proxmox RTX 5080 thread](https://forum.proxmox.com/posts/861694/), [Arch BBS 5090M thread](https://bbs.archlinux.org/viewtopic.php?id=314899)
- NVIDIA GeForce passthrough support (driver 465): https://www.storagereview.com/news/nvidia-enables-beta-support-for-virtualization-on-geforce-gpus
- NVIDIA vGPU support matrix: https://docs.nvidia.com/vgpu/latest/product-support-matrix/index.html
- vgpu-unlock-blackwell: https://github.com/bird/vgpu-unlock-blackwell
- AMD GIM: https://www.tomshardware.com/pc-components/gpu-drivers/amd-releases-open-source-gim-driver-aimed-at-gpu-virtualization-support-for-mainstream-radeon-gpus-coming-later
- Wine 11.0, NTSync and WoW64: https://www.helpnetsecurity.com/2026/01/14/wine-11-released/
- Wine 11.18 NTOSKRNL work: https://www.phoronix.com/news/wine-11.18-released
- Longene: https://en.wikipedia.org/wiki/Longene
- Neptune OS: https://github.com/cl91/NeptuneOS
- LiberNT: https://github.com/LiberNT/LiberNT
- ReactOS 0.4.15: https://www.theregister.com/2025/03/25/reactos_drops_release_0415/
- Anti-cheat: [areweanticheatyet](https://areweanticheatyet.com/), [EA Secure Boot for BF6](https://www.ea.com/games/battlefield/battlefield-6/news/secure-boot-information), [PC Gamer on Secure Boot](https://www.pcgamer.com/hardware/battlefield-6-requires-secure-boot-to-run-and-its-coming-to-more-games-soon-including-call-of-duty-black-ops-7-heres-what-it-is-why-linux-gamers-are-mad-about-it-and-how-to-enable-it)
- virtiofs: [virtio-win quick start](https://virtio-win.github.io/Knowledge-Base/Virtiofs-qs), [libvirt kbase](https://libvirt.org/kbase/virtiofs.html), [WinFsp issue 534](https://github.com/winfsp/winfsp/issues/534), [Proxmox file-limit patch](https://lists.proxmox.com/pipermail/pve-devel/2025-May/070783.html), [Factorio on virtio-fs](https://forums.factorio.com/viewtopic.php?p=585708)
- Single-GPU passthrough: [QaidVoid guide](https://github.com/QaidVoid/Complete-Single-GPU-Passthrough), [joeknock90 guide](https://github.com/joeknock90/single-gpu-passthrough)
- Hyprland QEMU key grabbing: https://forum.hypr.land/t/qemu-grabbing-binds/1416
- Wayland keyboard-shortcuts-inhibit protocol: https://wayland.app/protocols/keyboard-shortcuts-inhibit-unstable-v1
- ASUS X570-I specs: https://rog.asus.com/motherboards/rog-strix/rog-strix-x570-i-gaming-model/spec
- Arch wiki (blocked by bot protection during this session, so it was not used as evidence): https://wiki.archlinux.org/title/QEMU/Guest_graphics_acceleration, https://wiki.archlinux.org/title/PCI_passthrough_via_OVMF
