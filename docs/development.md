# Working on karchy

For people who change karchy: running it from a checkout, building its packages and its ISO, and testing an install in a virtual machine. To install or use karchy, see [Installing karchy](installing.md) and [Using karchy](using.md).

Related pages: [Architecture](architecture.md) for how the repository, the packages and the shell fit together, [Packaging](../packaging/README.md) for how the packages are built and published, and [Maintenance](maintenance.md) for what keeps an installed machine current.

## Dev mode

To try changes on one machine without building packages, clone karchy and point `KARCHY_PATH` at it in `/etc/karchy.conf`:

```sh
KARCHY_PATH=/home/you/Projects/karchy
```

The session then runs the shell, Hyprland layer and commands from the checkout after the next login. Anything root runs still uses the packaged copy in `/usr/share/karchy` (D-55).

## Building the packages

`packaging/build` builds the packages from the checkout, uncommitted changes included, into `out/repo-dev`. [Packaging](../packaging/README.md) has the options, the channels and the build container.

## Building the ISO

The karchy ISO is the Arch Linux ISO (archiso's `releng` profile) with the installer on it, so it doesn't fetch the installer first. It still downloads the packages, from the same repositories: `[karchy]` for the channel picked in the form, Arch's, and `[cachyos]` and `[omarchy]`, which the installer adds as it does on the Arch ISO. karchy's signing key is in the live system's keyring from boot.

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

## How parts of the install work

Details the install guide leaves out.

### The installer's screens

The installer's screens use karchy's default theme and its console font. On the Linux console it loads both itself, so they look the same from the stock Arch ISO and from the karchy ISO. When its output is not a terminal (a pipe, a file) or `KARCHY_UI=plain` is set, it prints one timestamped line per step instead, as the log has them. While the installer is on the screen the kernel's own messages are kept off it; the errors among them are at the end of `/var/log/karchy-install.log`.

**Restart now** restarts at once, without the live system's usual shutdown (the installed system is already unmounted and closed by then), so a stick pulled out too early doesn't leave the computer stuck on read errors.

### Secure Boot

What the setup does (D-31), in the installer and in `karchy secureboot setup`. The steps for a person are in [Installing karchy](installing.md#secure-boot).

- sbctl creates karchy's own keys and enrolls them together with Microsoft's. Microsoft's keys are needed for GPU firmware (option ROMs) and for booting Windows.
- Limine's EFI binary is signed, and the BLAKE2 hash of `limine.conf` is enrolled into it. Kernels and initramfs files aren't signed: `limine.conf` lists each file's hash, and Limine refuses any file that doesn't match. With a hash enrolled and Secure Boot on, Limine's config editor is disabled.
- After each kernel, initramfs or snapshot change, limine's hooks update the hashes, re-enroll and re-sign. karchy's `95-karchy-limine-fallback` hook keeps the firmware's fallback copy (`EFI/BOOT/BOOTX64.EFI`) identical to the signed binary.

If a firmware update clears the keys, the machine still boots, without Secure Boot. At login a notification offers to enroll the keys again (`karchy-secureboot enroll`).

### Saved passwords and how each person gets in

Saved passwords (the keyring) keep working when people are added or removed and when automatic login is turned on or off, and nothing ever asks for a keyring password (D-142). The rule: a person's keyring is locked with their login password whenever the login screen is how they get in. Only automatic login keeps a random key for it in `/etc/credstore` (D-57), because no password is typed there; the disk password is the lock.

- **Automatic login turned off, or a second person added.** The first person's keyring changes from its key to their login password at their next login at the login screen, by itself, and the key is deleted. From then on nobody else can open it: not a standard user, and not an administrator either, who could read the key before. A person added now never gets a key.
- **Automatic login turned on again** (one person left). While nobody has logged in since it was turned off, it is on at once. Otherwise the page says "Starts after you next log in at the login screen": that login gives the keyring a new key, and the computer logs in by itself from the next start.
- **Without disk encryption** the login password opens each keyring from the first login, as before (D-131).
- **A password reset by an administrator** can't give the keyring the new password. That person's saved passwords stay locked, a notification says so at their next login, and Settings › Security › Saved passwords › Reset… erases them so apps can save again ([Recovery](recovery.md#someone-cant-sign-in)). A password changed by its owner (Settings › Security, or `passwd`) changes the keyring's with it.
