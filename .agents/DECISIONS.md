# Project decisions

All rows were confirmed by the user during inception (2026-11-13). Tags: [O] Omarchy does it, [C] CachyOS does it, [New] neither does. Component-level picks are in `docs/components.md`, the keybindings in `docs/keybindings.md`, and the menu tree in `docs/menu.md`. Those three docs are binding too.

## Binding decisions

| ID | Decision | Reason | Evidence |
| --- | --- | --- | --- |
| D-01 | Name: **karchy**. The old Nulifyer/karchy Go launcher repo gets renamed to `karchy-launcher` and archived, then a fresh Nulifyer/karchy is created. GitHub changes need the user's approval at the time. | User doesn't want the old launcher | Inception round, last round |
| D-02 | Deliver as an install script first (run from the stock Arch ISO); a karchy ISO later | Fast to test in a VM | Round 1 |
| D-03 | Base is Arch with live mirrors. `[omarchy]` and then `[cachyos]` are listed after Arch's repos | Arch builds win on overlaps; Omarchy's prebuilt apps and CachyOS's kernel are still available | Rounds 1–2; live `[omarchy]` db has 257 packages |
| D-04 | Kernel: `linux-cachyos` + `linux-cachyos-nvidia-open` on NVIDIA machines, with Arch `linux-lts` as the fallback entry [C] | Newest stable kernel fastest (7.3.3 vs Arch 7.2.15 on 2026-11-13) | `pacman -Si` comparison |
| D-05 | Vendor the Omarchy code karchy keeps, from release tags, with a sync script. Not a full fork | Karchy is mostly package and config choices; upstream matters only for the shell, themes, templates, Hyprland helpers and their commands | Round "Upstream" |
| D-06 | Update model: git checkout plus `karchy update` (paru -Syu, git pull --ff-only, karchy migrations, reload). No `omarchy update` and no update guard | Edits take effect immediately; no build step | Round "Update" |
| D-07 | Two repos: karchy (system + defaults) and Nulifyer/dotfiles reshaped into the user layer (link tool, KDE code and theme renderer removed). `~/.config` holds include stubs or symlinks, created once | Portable dotfiles, no dotfile binary, the update never overwrites user files | Rounds "Dotfiles" |
| D-08 | Installer: Omarchy-style gum form asking for disk, keyboard, username, one password (disk and login), name and email for git, hostname and timezone. Then an unattended install via archinstall and a reboot. It picks one disk and wipes it after a typed confirmation | User likes Omarchy's installer | Rounds "Installer", "Target" |
| D-09 | Disk layout: 4 GiB ESP at `/boot`, LUKS2, btrfs `zstd:1,noatime` with subvolumes `@ @home @root @srv @cache @log @tmp(/var/tmp) @swap`. Snapper snapshots `@` only | Proven on this host with two kernels plus snapshot entries (1.4 GiB used) | Host `lsblk`/`findmnt` |
| D-10 | Swap: zswap (zstd) in front of a swap file on `@swap` sized to RAM. No zram | Current kernel guidance: zram plus disk swap causes LRU inversion | Chris Down, 2026-03-24; ArchWiki Zswap |
| D-11 | `/tmp`: tmpfs capped at the RAM size. Cold pages swap out, it is cleared at boot, and files age out after 10 days | Page-level hot/cold tiering; this host filled the 50% cap | Host `/tmp` 6.5 GiB of 16 GiB |
| D-12 | Boot: Limine + limine-snapper-sync [O+C]. systemd initramfs with `sd-encrypt` [C]. Plain text console, no Plymouth | Snapshot boot entries; keyring unlock needs `sd-encrypt`; user chose no splash | Rounds 2 and 4 |
| D-13 | Login: greetd auto-login after the disk unlock, into uwsm + Hyprland [New]. Omarchy uses SDDM | Minimal; has a PAM stack for the keyring unlock | Round 4 |
| D-14 | Auth: Omarchy model [O]. Shell polkit overlay; sudo cached per terminal (`timestamp_timeout=10`, `passwd_tries=10`); fingerprint for sudo and polkit on the laptop with the lid-closed gate. NOPASSWD rules only for features that are kept | User likes the overlay and the fingerprint flow | Round 3 |
| D-15 | Firewall: ufw, deny incoming [O]. Network: NetworkManager + wpa_supplicant + systemd-resolved [O], without Omarchy's ping.omacom.io connectivity check | The VPN plugin requires ufw, NetworkManager and resolved | Round 3 |
| D-16 | Desktop: Hyprland + the Omarchy Quickshell shell. Keep only the shell parts listed in `docs/components.md` | The plugins need the shell | Rounds 4–5 |
| D-17 | Keybindings: exactly `docs/keybindings.md`. Bindings are approved group by group; new bindings need user approval | User finds Omarchy's ~170 binds too many | Keybind rounds |
| D-18 | Menu: exactly `docs/menu.md` | Functional entries only, no branded catalogs | Menu rounds |
| D-19 | No mise. Runtimes (dotnet, go, zig, rust, bun), Podman, AI CLIs, Steam and Flatpak are installed after setup with pacman/paru. The base gets no menu entries for them | User preference | Apps rounds |
| D-20 | AUR helper: paru [C] | User choice | Menu round |
| D-21 | Plugins stay in their own repos (omarchy-vpn-plugin, omarchy-project-picker); setup installs them with `omarchy plugin add` | Others can still use them on stock Omarchy | Plugin round |
| D-22 | Themes: all 23 Omarchy themes and the theme system, plus a new **nulifyer** theme (the user's gruvbox, background `#202020`) as the default | Omarchy's gruvbox leans green | Themes round |
| D-23 | Theming must never rewrite files in the dotfiles user layer. VS Code gets a generated theme extension, not `settings.json` edits. The Font menu entry must not rewrite terminal configs | Omarchy's VS Code sync and `omarchy-font-set` write into symlinked dotfiles | Audit THM-14, CFG-02 |
| D-24 | Mounts: USB through udisks2 + udiskie [O]. Internal data disks go into fstab at `/mnt/<label>` (`nofail`, `x-gvfs-show`, owned by the user, `ntfs3`): the installer sets up existing ones and a notification offers new ones [New]. NAS shares: browse with gvfs-smb, then a Thunar action "Keep this mount" writes an fstab systemd automount (`nofail,_netdev,x-systemd.idle-timeout`) with root-only credentials; "Remove kept mount" undoes it [New] | Windows-like, system-level mounts that work when the laptop is away from the NAS | Files and disks rounds |
| D-25 | Moving to real hardware is a fresh install followed by a data restore | Cleanest | Hardware round |
| D-26 | Work delivery: a branch and a PR per change, with atomic commits. No GitHub changes (repo create, rename, push) without the user's approval at the time | User choice | Last round |
| D-27 | karchy Settings window: an optional GUI next to editing files by hand. It is a shell plugin following Omarchy's unmerged `input-settings-panel` pattern: the GUI writes JSON in `~/.config/karchy/`, a generator writes includes into `~/.local/state/karchy/`, and the user's hand-edited files load after those and always win. Sections are hidden per machine (laptop vs desktop). Built in phase 2 | A second flow besides editing files; never writes into dotfiles (D-23) | Omarchy branch `input-settings-panel` (`bin/omarchy-input-config`) |
| D-28 | Three install tiers: **Always** (health and ease of use), **Detected** at install (hardware-specific), **Optional** (shown in Settings › Optional features; one click installs packages *and* their setup). Plain apps that need no setup are either in Always or installed by the user. The lists are in `docs/components.md` | Don't install everything everywhere, but make it available | Follow-up round |
| D-29 | Mirror ranking: rate-mirrors on a weekly timer, never during `karchy update` (lock). HTTPS only, `--completion 1`, `--max-delay` about 6 h. The result is validated (at least 5 servers serving the current package database), then swapped in atomically with a backup; the old list is kept on any failure. Arch's GeoDNS mirror is always the last entry. Updates are always the full `-Syu`, never `-Sy` alone | User has had mirror changes break the system before | `rate-mirrors arch --help` on host |
| D-30 | Dedup: bees on btrfs filesystems, as an installer choice. Details and defaults are in D-39, which replaces "always on" | btrfs has no built-in background dedup | btrfs docs; bees in Arch extra 0.11 |
| D-31 | Secure Boot as an installer step [C]: detect Setup Mode; create keys with sbctl and enroll them together with Microsoft's (needed for NVIDIA's GPU firmware and dual boot); sign `limine_x64.efi` and `BOOTX64.EFI`; set `ENABLE_ENROLL_LIMINE_CONFIG=yes` in limine-entry-tool so kernels are verified by hash rather than signed. Offer re-enrollment if a BIOS update wipes the keys. Tested in the VM with `OVMF_CODE.secboot.4m.fd` in phase 2 | Wanted, but must stay easy to boot | CachyOS Secure Boot guide; host OVMF |
| D-32 | Laptop sleep: suspend-then-hibernate, hibernating after 2 h asleep (swap file = RAM). Detected tier (battery) | Proper long-term sleep | Follow-up round |
| D-33 | LocalSend in the base install (`[omarchy]`). A NetworkManager hook opens its port in ufw only on trusted networks. The trusted-network list is shared with the VPN plugin and editable in Settings | Sharing at home, closed elsewhere | Follow-up round |
| D-34 | Base apps: Omasnap for screenshots and annotation [O] (backs Print and Super+Shift+S); GNOME Disks [O]; omacalc [O]. The password manager is the user's choice and not in base | User choices | Follow-up round |
| D-35 | Home backup to the NAS comes last (phase 7) | User priority | Follow-up round |
| D-36 | Thunar right-click menu: Thunar's own Open With and Set Default Application; Open in VS Code; Open Terminal Here (foot); Extract Here / Extract To / Create Archive (`thunar-archive-plugin` + archive tool + `7zip`); Send with LocalSend (ported from Omarchy's Nautilus `localsend.py`); Copy Path; Keep This Mount / Remove Kept Mount. karchy's actions sit in the default layer and get merged into `~/.config/Thunar/uca.xml` under a `karchy-` id prefix, so actions the user adds are preserved | One right-click menu for common jobs | Follow-up round; Omarchy `default/nautilus-python/extensions/` |
| D-37 | Settings › Default apps: browser, file manager, terminal, text editor, image, video, music, PDF and archive handlers. karchy's defaults live in `/etc/xdg/mimeapps.list` (system layer); the GUI writes overrides to `~/.config/mimeapps.list`, the same file Thunar's Set Default Application writes; the terminal goes through `xdg-terminal-exec`'s list | One default-apps screen that agrees with Thunar | Follow-up round |
| D-38 | Printing and scanning are one Optional feature, Settings › Printers & scanners: CUPS with Omarchy's hardened cups-browsed, plus `sane`, `sane-airscan`, `simple-scan`. Not in the base install. Supersedes the earlier "printing in base". `avahi` + `nss-mdns` stay in Always for NAS name lookup | The user has no printer | Follow-up round |
| D-39 | bees is a yes/no choice in the installer form, **off by default** (opt-in, with a one-line explanation). When chosen: `/etc/bees/<fs>.conf` with `UUID=` and `DB_SIZE=256M`, run by the upstream `beesd@` unit (lowest priority). On laptops it runs only on AC power. Soak-tested on the desktop in phase 5 before it could ever become the default. This replaces "always on" in D-30 | The docs say it works best from the start; 7.x kernels aren't covered by the docs; one unfixed kernel-hang case (no data loss) | bees docs config.md, gotchas.md, btrfs-kernel.md; `beesd.conf.sample` |
| D-40 | Archive tool: xarchiver + `7zip` (7z and RAR extraction) behind `thunar-archive-plugin`. Right-click also gets **Set as Wallpaper** (images, sets the current theme's background) and **Checksum** (SHA-256, copied to the clipboard) | Lightest option; user picks | Follow-up round |

## Open decisions

- **Keyring:** evaluate `oo7` (Arch extra 0.7.1, a Secret Service provider) in the VM, including whether it can unlock through PAM. Fallback: gnome-keyring + `pam_systemd_loadkey` in greetd's PAM stack, with the keyring password equal to the LUKS passphrase. Decide in phase 2.
- **Terminal editor:** micro vs nano (with `nano-syntax-highlighting`). Try both in the VM.
- **Minimize in floating mode:** Omarchy restores minimized windows through the dock, which is dropped. Choose a restore path, such as a menu entry or a bar indicator, or remove the minimize button.
- **Command naming:** vendored commands keep `omarchy-*` names for syncing; karchy's own commands use `karchy-*`. Confirm in phase 1 that the `omarchy` router (needed for `omarchy plugin` and `omarchy bar`) can sit next to a `karchy` command.
- **Where the dotfiles checkout lives** on each machine, and how its stubs are created.
- **Web-app icons:** decide the icon source for the improved web-app flow.
- **LocalSend port:** confirm 53317 TCP/UDP in the VM.
- **bees and kernel 7.x:** watch upstream bees for 7.x kernel notes before the phase 5 soak test.

## Superseded decisions

- Audit `DECISIONS.md` gate G1 (stay on CachyOS) is replaced by D-03/D-04. The audit's recommendations are background only.

## Project notes

- The user's current host stays on CachyOS + KDE while karchy is built and tested in a VM on it.
