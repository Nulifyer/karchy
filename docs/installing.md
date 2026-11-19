# Installing karchy

karchy installs from the karchy ISO or from the stock Arch Linux ISO; both run the same installer. It erases one disk and sets up:

- a 4 GiB EFI partition
- LUKS2 encryption
- btrfs with the subvolumes `@ @home @root @srv @cache @log @tmp @swap`
- a swap file sized to RAM, with zswap
- `linux-cachyos` plus `linux-cachyos-lts`
- Limine, with snapshot boot entries (snapper + snap-pac + limine-snapper-sync)
- a splash screen that asks for the disk password (Plymouth, karchy's theme), with a text prompt behind it for a boot without the splash
- NetworkManager and systemd-resolved
- your user, with fish as the login shell
- the karchy desktop from the `[karchy]` package repository: `karchy-desktop`, plus `karchy-laptop` on a machine with a battery and the NVIDIA driver with an NVIDIA GPU: `karchy-nvidia` for Turing (RTX 20 / GTX 16) and newer, `karchy-nvidia-580xx` for Maxwell, Pascal and Volta (GTX 900 and 10 series, Quadro M and P, Titan V; this also enables `[multilib]`). Kepler and older cards are not supported by NVIDIA's current drivers, so they keep nouveau; the installer prints a message when it finds one

After that, the system updates through pacman: `karchy update` (or `paru -Syu`) brings new versions of karchy's packages along with everything else.

## From the Arch ISO

1. Boot the Arch ISO in UEFI mode and connect to the network (`iwctl` for Wi-Fi). The installer copies a Wi-Fi network joined here into the installed system, so the first boot is online.
2. Run:

   ```sh
   pacman -Sy --noconfirm git
   git clone https://github.com/Nulifyer/karchy.git
   karchy/install/karchy-install
   ```

3. Answer the form: keyboard, disk (typed confirmation), username, one password for both the disk and your login, name and email for git, computer name, timezone, release channel (stable, rc or nightly; only channels with a published release are offered, so stable appears from karchy's first release on), Secure Boot (asked only when the firmware is in Setup Mode; on by default then), and bees background deduplication (on by default; answer No to leave it off). The keyboard layout applies as soon as it's picked, so the password is typed in the layout the disk prompt will use. Esc or Ctrl-C at a question that asks for an answer stops the installer with nothing changed; at a yes/no question Esc means No.
4. Check the summary, which lists every answer and says in red which disk is erased, then confirm "Erase and install". Nothing is written to the disk before this.
5. The installer shows its steps as a numbered list: a check mark and the time for each finished one, the time of the step under way, and the last line of the log. A step that fails turns red, with the end of the log and how to try again under it.
6. The last screen says what to do next: remove the install media and restart (it offers to), then type the password at the disk-password screen.

Every step is logged to `/var/log/karchy-install.log`, which is copied into the installed system.

The installer's screens use karchy's default theme and its console font. On the Linux console it loads both itself, so they look the same from the stock Arch ISO and from the karchy ISO. When its output is not a terminal (a pipe, a file) or `KARCHY_UI=plain` is set, it prints one timestamped line per step instead, as the log has them.

The Wi-Fi networks the install media joined (WPA2/WPA3 personal and open ones) become NetworkManager profiles on the installed system, with the password. Enterprise (802.1X) networks are not copied: connect to those again from the network panel.

If the installed system does not boot, see [When karchy does not boot](recovery.md): snapshots, the LTS kernel, getting in from the install media, and the LUKS header backup to make on the first day.

## From the karchy ISO

> Each release and release candidate has the ISO and its checksum attached on its [GitHub release page](https://github.com/Nulifyer/karchy/releases). To make one from a checkout, see [Building the ISO](#building-the-iso).

The karchy ISO is the Arch Linux ISO (archiso's `releng` profile) with the installer on it, so it doesn't fetch the installer first. It still downloads the packages, from the same repositories: `[karchy]` for the channel picked in the form, Arch's, and `[cachyos]` and `[omarchy]`, which the installer adds as it does on the Arch ISO. karchy's signing key is in the live system's keyring from boot.

1. Write the ISO to a USB stick (`dd if=karchy-….iso of=/dev/sdX bs=4M oflag=sync`) and boot it in UEFI mode.
2. The installer starts by itself on the first console. It waits for the network: a cable connects by itself; otherwise it offers to retry, to connect to Wi-Fi with `iwctl`, or a shell.
3. Answer the form and confirm, as above.

Esc or Ctrl-C at a question leaves the installer for a root shell; `karchy-install` starts it again, and Alt+F2 opens another console. `karchy-install --config FILE` works there too. For an install with no form at all, add `karchy.config=<file or http(s) URL>` to the boot entry (`e` in the UEFI menu): the ISO downloads the answer file once the network is up and runs `karchy-install --config` with it. As with any answer file, the disk named in it is erased without asking. When such an install is done, the ISO says so and stays at the shell; remove the stick and reboot.

### Building the ISO

`packaging/iso/build` copies `releng`, adds `packaging/iso/` (the autostart, a `karchy-install` command, `gum` for the form, the boot menu's name "karchy installer", and the default theme's colours for the BIOS menu; the UEFI menu, systemd-boot, has no colours to set) and the working tree's installer (`install/`, `bin/`, `system/`, `packaging/keyring/`, uncommitted changes included), and writes `out/iso/karchy-<date>-x86_64.iso` with a `.sha256`:

```sh
packaging/iso/build                # as your user; needs podman
```

The build runs in a fresh container of karchy's build environment, removed afterwards (see [Build container](../packaging/README.md#build-container)). mkarchiso runs there without root, in archiso's user-namespace mode, so nothing needs sudo. The first build downloads about 1 GiB of packages; later builds reuse the container's package cache.

To try an ISO in a VM, boot it with `KARCHY_VM_ISO`, and hand it the VM test answers through the repository server:

```sh
packaging/build
cp tests/vm-install.conf out/
tools/vm repo                      # leave running
tools/vm new --name isotest
KARCHY_VM_ISO=out/iso/karchy-….iso tools/vm run --name isotest --iso
# at the boot menu: e, End, then add  karchy.config=http://10.0.2.2:8090/vm-install.conf  and Enter
# when it says karchy is installed: tools/vm stop --name isotest, then run it without --iso
```

## Unattended installs

`karchy-install --config FILE` reads the answers from FILE instead of showing the form. FILE sets `KARCHY_DISK`, `KARCHY_USER`, `KARCHY_PASSWORD`, `KARCHY_HOSTNAME` and `KARCHY_TIMEZONE`, and optionally `KARCHY_KEYMAP`, `KARCHY_FULL_NAME`, `KARCHY_EMAIL`, `KARCHY_BEES`, `KARCHY_CHANNEL` (`stable`, `rc`, `nightly`; `dev` for VM tests), `KARCHY_SECUREBOOT` (`auto`, the default, sets it up when the firmware is in Setup Mode; or `yes`/`no`), `KARCHY_REPO_SERVER` and `KARCHY_REPO_SIGLEVEL` for another `[karchy]` repository, `KARCHY_CACHYOS_LEVEL` (`generic` skips CachyOS's CPU-tuned repositories; otherwise the installer picks `v3`, `v4` or `znver4` from the CPU, as CachyOS's own installer does), and `KARCHY_KEYRING_KEY_FILE` (a key saved with `karchy keyring-key export`, so a home folder restored from a backup opens its keyring; D-57). `KARCHY_CONSOLE_FONT` names the console font (`karchy-10x20`, `karchy-12x24` or `karchy-16x32`) instead of the one picked from the screen's height. `tests/vm-install.conf` is the VM test example; its credentials are for throwaway VMs only.

## Testing in a VM

Build the packages from the checkout (uncommitted changes included) and serve them to the VM:

```sh
packaging/build                   # builds the packages into out/repo-dev
tools/vm repo                     # leave running: serves out/ at http://10.0.2.2:8090
tools/vm fetch
tools/vm new --name inst
tools/vm run --name inst --iso
# in the VM:
mkdir -p /root/karchy
mount -t 9p -o trans=virtio,version=9p2000.L,ro karchy /root/karchy
/root/karchy/install/karchy-install --config /root/karchy/tests/vm-install.conf
# then stop the VM and boot it without --iso
```

To test an update, change the checkout, run `packaging/build` again and run `karchy update` in the VM. Only the packages whose contents changed get new versions.

### On a Proxmox host, with 3D

Local VMs draw in software (llvmpipe), so anything that needs a GPU can't be tested in them. With `--pve <ssh-target>` (or `KARCHY_VM_PVE`), `tools/vm` drives a VM on a Proxmox VE host instead, with VirGL (`vga: virtio-gl`) rendering on the host's GPU. The host must accept `ssh <ssh-target>` as root with a key and have `libgl1` and `libegl1` installed. The VM is the Proxmox VM named `karchy-<name>`, tagged `temp`; it boots with an empty CD drive unless started with `run --iso`.

The guest is on the host's LAN bridge, so it can't see `10.0.2.2`. Instead, `repo` serves `out/` on this machine's loopback and opens an SSH reverse tunnel into the guest, through the Proxmox host. The guest reads the repository at `http://127.0.0.1:8090`, and this machine's firewall stays closed. `ssh`, `push` and `repo` log in with a throwaway key (`~/.local/state/karchy-vm/pve/`), which the guest agent installs for root along with starting sshd and, until the next reboot, an iptables rule that lets the Proxmox host through the installed system's ufw. Rerun `repo` after each guest reboot.

```sh
pve="tools/vm --pve root@pve --name test"
packaging/build
$pve fetch                  # current Arch ISO into the host's local ISO storage, checked
$pve new                    # 8 cores, 8 GiB, 48 GiB on local-zfs, VirGL; --vmid N to choose the ID
$pve run --iso              # watch it in the Proxmox web UI's console
$pve push                   # once the ISO has booted: copies the checkout to /root/karchy
$pve repo                   # leave running
$pve ssh /root/karchy/install/karchy-install --config /root/karchy/tests/pve-install.conf
$pve stop && $pve run       # boots the installed system; type karchy-test at the disk prompt
```

`screenshot`, `type`, `key`, `click`, `drag`, `exec [--user]`, `stop`, `status` and `snap`/`restore`/`snapshots` work as they do with libvirt. Screenshots come from the VM's VNC socket (QMP `screendump` has nothing to dump once the guest shows a VirGL frame), and need `gvnccapture` (gtk-vnc) on this machine. `define` and `destroy` aren't offered: change or delete the VM in the Proxmox web UI.

## Dev mode

To try changes on one machine without building packages, clone karchy and point `KARCHY_PATH` at it in `/etc/karchy.conf`:

```sh
KARCHY_PATH=/home/you/Projects/karchy
```

The session then runs the shell, Hyprland layer and commands from the checkout after the next login. Anything root runs still uses the packaged copy in `/usr/share/karchy` (D-55).

## Known limitations

- There is no stable release yet, so the installer offers rc and nightly only. Install on rc, then switch to stable (in the Updates window, or `karchy channel set stable`) once 0.1.0 is released.
- Nothing has been checked on real hardware yet (`.agents/TESTING.md` has the list).

## Secure Boot

To have the installer set up Secure Boot, put the firmware in Setup Mode first: in its Secure Boot settings, clear or delete the keys (sometimes called "Reset to Setup Mode" or "Erase all Secure Boot settings"). The form then offers Secure Boot (D-31):

- sbctl creates karchy's own keys and enrolls them together with Microsoft's. Microsoft's keys are needed for GPU firmware (option ROMs) and for booting Windows.
- Limine's EFI binary is signed, and the BLAKE2 hash of `limine.conf` is enrolled into it. Kernels and initramfs files aren't signed: `limine.conf` lists each file's hash, and Limine refuses any file that doesn't match. With a hash enrolled and Secure Boot on, Limine's config editor is disabled.
- After each kernel, initramfs or snapshot change, limine's hooks update the hashes, re-enroll and re-sign. karchy's `95-karchy-limine-fallback` hook keeps the firmware's fallback copy (`EFI/BOOT/BOOTX64.EFI`) identical to the signed binary.
- Then turn Secure Boot on in the firmware if it didn't turn on by itself.

If a firmware update clears the keys, the machine still boots, without Secure Boot. At login a notification offers to enroll the keys again (`karchy-secureboot enroll`).

### Turning it on after the install

A system installed without Secure Boot gets the same setup later from one command:

1. Put the firmware in Setup Mode, as above, and boot karchy.
2. Run `karchy secureboot setup` in a terminal. It asks for your password, then installs sbctl, creates the keys, turns on Limine's file checks, signs both copies of Limine and enrolls the keys.
3. Restart. If `sbctl status` still shows Secure Boot off, turn it on in the firmware settings.

Outside Setup Mode the command changes nothing and says how to get there. The keys are enrolled last, so if a step fails before that, the computer boots as before and the command can be run again.

## Updates and release channels

`karchy update` updates everything in one pass: karchy's own packages from `[karchy]`, and Arch, CachyOS and AUR packages through paru, with snapper snapshots before and after. It then reloads the desktop and shows the karchy release change with a link to its release notes.

The Updates window (the bar's updates indicator, Update › Update System in the menu, Settings › About, or `karchy updates`) shows what an update would install before it runs, with Arch's news since the last update first, and holds the release channel. Its Install button runs `karchy update` in a terminal.

karchy's packages come from one release channel (D-61):

| Channel | What you get |
|---|---|
| stable | releases, such as 3.0.0 |
| rc | release candidates (3.1.0-rc.1) as well as releases |
| nightly | every change to karchy's main branch |

Pick one in the installer, change it in the Updates window or with `karchy channel set <channel>`. Moving to an older channel (nightly back to stable) installs that channel's versions even though they are older. `karchy channel` shows the channel and the installed release.
