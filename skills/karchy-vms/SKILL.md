---
name: karchy-vms
description: Use on a karchy system when creating, starting, stopping, editing, snapshotting, deleting or debugging a virtual machine run by `karchy vm` (`karchy-vm`), or when the task touches `~/VMs/<name>/` (`vm.conf`, `disk.qcow2`, `vars.fd`, `tpm/`), a `karchy-vm-<name>.service` user unit, the sockets in `$XDG_RUNTIME_DIR/karchy-vm/`, a Windows 11 guest (TPM, Secure Boot), the SPICE viewer (`spicy`), `/dev/kvm`, the VMs bar panel or VMs window, or adding and removing the Virtual machines feature (`karchy-feature-vms`). Do not use for libvirt, virsh or virt-manager domains, for containers (use karchy-containers), or for karchy itself installed as a guest inside a VM.
---

# karchy virtual machines

karchy runs QEMU/KVM directly, as the user, with no libvirt. Do not reach for `virsh`, `virt-install` or libvirt XML. Every operation goes through `karchy vm` (the same program as `karchy-vm`). The VMs panel and window call the same command, so a change made here shows there.

Run `karchy vm` with a wrong argument to print the full usage. The header of `/usr/share/karchy/bin/karchy-vm` is the reference.

## Change rules

Follow the change rules in the `karchy` skill. Creating, starting, stopping and `set` on a VM are small changes: do them, then say what changed. These count as large, so describe them and get the user's agreement first:

- `karchy vm delete` and `karchy vm snapshot restore|delete`. Delete removes the folder and the disk and cannot be undone.
- `karchy vm kill`, which forces the VM off.
- Adding or removing the feature, and anything else that needs `sudo`.
- Editing or replacing `disk.qcow2`, `vars.fd` or `tpm/` by hand.

## Where things are

| What | Where |
| --- | --- |
| A VM | `~/VMs/<name>/` |
| Settings | `vm.conf`, lines of `key=value`, read as data |
| Disk | `disk.qcow2`, with snapshots stored inside it |
| UEFI variables | `vars.fd`, a copy of `/usr/share/edk2/x64/OVMF_VARS.4m.fd` |
| TPM state | `tpm/`, present when `tpm=yes` |
| Snapshot copies of the UEFI variables and TPM | `snapshots/<snapshot>.vars.fd`, `snapshots/<snapshot>.tpm` |
| The running VM | user unit `karchy-vm-<name>.service` |
| Sockets while it runs | `$XDG_RUNTIME_DIR/karchy-vm/<name>/`: `qmp.sock`, `spice.sock`, `qga.sock`, and `swtpm.sock` with a TPM |

A VM name starts with a letter or digit and uses letters, digits, `.`, `_` and `-`, up to 40 characters. Snapshot names follow the same rule.

`~/VMs` is marked no-copy-on-write on btrfs when it is first created, so disk images do not fragment. New files inherit the mark. A disk image copied in from elsewhere keeps it only if the copy creates a new file inside `~/VMs`.

## Check the feature first

VMs are an optional feature. Check before anything else:

```bash
karchy-feature-vms status     # installed | available
ls -l /dev/kvm
```

If the status is `available`, the user adds it from Quick install › System features › Virtual machines (`karchy quick-install window @system`), or with `karchy quick-install install vms` in a terminal. It installs `qemu-desktop`, `edk2-ovmf`, `swtpm` and `spice-gtk` with `sudo`. Removing it (`karchy quick-install remove vms`) refuses while a VM runs and keeps `~/VMs`.

`karchy vm start` needs a writable `/dev/kvm`. If the device is missing, virtualization (Intel VT-x or AMD-V) is off in the firmware settings, and only the user can turn it on. If the device exists but is not writable, the feature's install step adds the user to the `kvm` group, which takes effect at the next login.

## Create and run

```bash
karchy vm create <name> --iso <file> [--os linux|windows] [--disk 64G] [--ram 4G] [--cpus N] [--tpm] [--secureboot]
karchy vm start <name> [--iso <file>]
karchy vm open <name>            # the screen, in spicy
karchy vm stop <name> [--timeout SEC]
karchy vm list [--json]
karchy vm status <name> [--json]
```

- The disk boots first. While the disk is empty, the firmware falls through to the ISO saved in `vm.conf`. `start --iso <file>` boots that ISO first, for one boot only.
- A VM runs headless and keeps running when its window closes, when the shell restarts and after `open` exits. Closing `spicy` does not stop it.
- `stop` sends an ACPI power-off over QMP and waits, 90 seconds by default. A guest that ignores the power button stays up and the command fails. Only then consider `kill`, with the user's agreement.
- `start` fails with QEMU's own message when a setting is wrong, for example a missing ISO or more memory than the host has.
- Use `--json` output when you need state. The `state` field is `running`, `starting`, `stopping` or `stopped`.
- `karchy vm manage [name]` opens the VMs window. `karchy vm choose-iso` opens the desktop file chooser and prints the path. Both need the desktop session.

## Change a VM

Stop the VM first. `set` refuses while it runs.

```bash
karchy vm set <name> <key> <value>
```

| Key | Values |
| --- | --- |
| `os` | `linux`, `windows` |
| `ram` | a size such as `4G` or `512M` |
| `cpus` | a number |
| `disk_bus` | `virtio`, `sata` |
| `nic` | `virtio`, `e1000e` |
| `net` | `user`, `none` |
| `uefi`, `secureboot`, `tpm`, `gl` | `yes`, `no` |
| `iso` | a file path, or `none` to detach |
| `display` | `virtio`, `qxl`, `std` |
| `audio` | `spice`, `pipewire`, `none` |
| `disk_size` | a size such as `128G` |

- Prefer `set` to editing `vm.conf`. `set` checks the value, and the file is rewritten whole on every `set`, so comments and unknown keys in it are lost.
- `disk_size` only grows the image. Grow the partition inside the guest afterwards.
- `secureboot=yes` needs `uefi=yes`. Setting `uefi=no` turns Secure Boot off.
- `net=user` is QEMU's user-mode network: the guest reaches out, and nothing on the host or the local network reaches the guest. `karchy vm` has no port forwarding or bridge setting. Say so instead of inventing one.
- `gl=yes` applies to `display=virtio` only.
- Changing `disk_bus` or `uefi` on an installed guest can stop it from booting. Take a snapshot first.

## Snapshots

```bash
karchy vm snapshot create|restore|delete <name> <snapshot>
karchy vm snapshot list <name> [--json]
```

`create`, `restore` and `delete` need the VM stopped. A snapshot holds the disk state, plus copies of the UEFI variables and the TPM state, and `restore` brings back all three. These are not snapper snapshots of the host. Take one before a risky change inside a guest or to its settings.

## Windows 11

`--os windows` picks a profile without virtio devices, because Windows has no virtio drivers until the user adds them: SATA disk, `e1000e` network card, QXL display, 8G of memory, 4 CPUs, TPM on and the Secure Boot firmware.

```bash
karchy vm create win11 --os windows --iso ~/Downloads/Win11.iso
```

- The Secure Boot firmware starts in Setup Mode, with no keys enrolled. karchy enrolls none.
- The TPM is `swtpm`, started with the VM. Its state in `tpm/` belongs to that Windows install. Do not delete it or copy it between VMs.
- Windows integration beyond this is not built. Do not promise shared folders or automatic guest drivers.

## When a VM misbehaves

```bash
karchy vm log <name>                                   # last 100 journal lines of the unit
journalctl --user -u karchy-vm-<name>.service -b       # the full log; the first line is the QEMU command
systemctl --user status karchy-vm-<name>.service
karchy vm screenshot <name> <file.png>                 # what the screen shows, without opening a window
```

- "`<command>` is missing" from `karchy vm` means the feature is not installed.
- "the VM has a TPM but swtpm is missing" means the same, or `swtpm` was removed.
- `open` reports "no display socket" when the VM is not fully up. Check `status` and the log.
- A unit left in the failed state is cleared by the next `start`.
- Do not run `karchy-vm __run` or `__stopped` by hand. The unit calls them.
- Talking to `qmp.sock` directly can change or stop the VM. Use it only when `karchy vm` has no command for the job, and say what was sent.

## Panel and window

The bar shows a VMs icon only while a VM runs. Its panel lists up to six VMs with a run switch and a button for the screen. The window (`karchy vm manage`) has creation, settings, snapshots, force off and delete. Both update from `karchy vm` itself, so no refresh is needed after a command.

## karchy as a guest

When karchy itself is installed inside a VM, the installer adds the `karchy-vm` package, which is the SPICE and QEMU guest agents. That package is unrelated to running VMs on this machine.
