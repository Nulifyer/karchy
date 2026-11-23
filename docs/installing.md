# Installing karchy

You install karchy from its ISO: download it, write it to a USB stick, boot the stick and answer a short form. The installer downloads the system while it runs, so the computer needs a network connection.

## Before you start

You need:

- a 64-bit PC (x86_64) that boots in UEFI mode
- a USB stick of 2 GB or more; everything on it is erased
- a network connection: a cable, or Wi-Fi with a password

Know this before you begin:

- **The installer erases one whole disk.** karchy can't be installed beside another system on the same disk. Copy anything you want to keep to another disk first.
- **The ISO is not signed for Secure Boot.** If the stick doesn't boot, turn Secure Boot off in the firmware settings. To have karchy set up Secure Boot with its own keys, see [Secure Boot](#secure-boot) before you start.

## 1. Download the ISO

1. Open the [releases page](https://github.com/Nulifyer/karchy/releases) and pick the newest release.
2. Under **Assets**, download `karchy-<version>-x86_64.iso` and `karchy-<version>-x86_64.iso.sha256`.
3. Check the download. In the folder that holds both files:

   ```sh
   sha256sum -c karchy-<version>-x86_64.iso.sha256
   ```

   It must print `OK`. On Windows, run `Get-FileHash karchy-<version>-x86_64.iso` in PowerShell and compare the result with the text in the `.sha256` file.

## 2. Write it to the USB stick

On Linux, find the stick's name with `lsblk`, then write the ISO to it. Replace `/dev/sdX` with the stick. This erases the stick, and a wrong name erases another disk.

```sh
sudo dd if=karchy-<version>-x86_64.iso of=/dev/sdX bs=4M oflag=sync status=progress
```

On Windows or macOS, use a tool that writes the image unchanged, such as balenaEtcher, or Rufus in "DD Image" mode.

## 3. Boot the stick

1. Plug the stick in and start the computer. Open the firmware's boot menu (often F12, F10 or Esc) and choose the stick's UEFI entry.
2. Choose **karchy installer**. The installer starts by itself.
3. The installer needs the network. A cable, or a phone sharing its connection over USB, connects by itself. Without one the installer says **No network connection**: choose **Connect to Wi-Fi**, pick your network from the list and type its password. A wrong password asks again; **Look again** scans once more; a network that hides its name can be typed in.

   The installed system keeps that Wi-Fi network and its password, so the first start is online. A network with a work or school sign-in (802.1X) can't be joined from the list: use another network, a cable or a phone for the install, and join it from the network panel afterwards.

## 4. Answer the form

The installer asks these questions in order. Nothing is written to a disk while you answer.

| Question | What to know |
| --- | --- |
| Keyboard | Applies at once, so you type the password in the layout the computer will use at boot. |
| Disk | The disk that is erased. You type its name to confirm. |
| Disk encryption | **Encrypted** is selected already. See [Disk encryption](#disk-encryption). |
| Other internal disks | Asked only with encryption, and only when the computer has more disks. See [Other internal disks](#other-internal-disks). |
| Username and password | One password. On an encrypted install it opens the disk and logs you in. |
| Name and email | Used to set up git. |
| Computer name | The name the computer has on the network. |
| Timezone | |
| Release channel | Where karchy's own updates come from. **stable** gets releases, **rc** also gets release candidates, **nightly** gets every change. Only channels that have a release are offered. You can change it later. |
| Secure Boot | Asked only when the firmware is in Setup Mode. See [Secure Boot](#secure-boot). |
| Deduplication (bees) | On by default. It stores identical data once, in idle time. |

Esc or Ctrl-C at a question leaves the installer for a shell, with nothing changed; type `karchy-install` to start again. At a yes/no question, Esc means No.

## 5. Check the summary and install

The summary lists every answer. It shows in red which disks are erased and, without encryption, who can then read the disk. Confirm **Erase and install** to start. Until then nothing is written.

The installer shows its steps as a list, with a check mark for each finished one. A step that fails turns red, with the end of the log and how to try again.

If a step that downloads packages fails, run `karchy-install` again; it starts over and nothing is lost. The usual cause is a package mirror in the middle of an update. The installer already works round such a mirror by itself, up to ten times, before it gives up.

## 6. Restart

Choose **Restart now** on the last screen and leave the stick in. When the screen goes dark, take the stick out.

If the installer's boot menu comes up again, the computer started from the stick: take it out and restart.

## The first start

- On an encrypted install, karchy asks for the disk password, then goes straight to the desktop.
- Without encryption, karchy's login screen asks for your password.

Then:

1. Press `Super` + `Space` for the menu. [Using karchy](using.md) covers the keys, Settings, apps and updates.
2. On an encrypted install, back up the disk's LUKS header on the first day. It takes a minute and saves your data if the header is ever damaged: see [Back up the LUKS header](recovery.md#back-up-the-luks-header-now-while-everything-works).

If the installed system doesn't start, see [When karchy does not boot](recovery.md).

## The choices in detail

### Disk encryption

One question decides how the disk is protected and how you get in.

| Answer | The disk | At boot |
| --- | --- | --- |
| **Encrypted** (the default) | Encrypted with LUKS2. Nobody reads it without the password. | You type the disk password. The same password logs you in. |
| **Not encrypted** | Plain. Anyone who has the computer or the disk can read your files. | karchy's login screen asks for your password. |

Every install asks for a password at boot. Your saved passwords (the keyring) stay protected in both cases.

The choice is made at install time. To change it later you install again.

### Other internal disks

With **Encrypted**, the installer shows each other internal disk with its size, model and partitions, and asks what to do with it. USB sticks and the install stick are not listed.

- **Keep it as it is** (selected already). Nothing on it changes. Its partitions are mounted under `/mnt/<label>`.
- **Erase and encrypt it.** Everything on it is erased; you type its name to confirm. It becomes an encrypted data disk, mounted at `/mnt/data` (`/mnt/data2` for the next one) and yours to write to. It opens at boot together with the system disk, without a second question. Your install password opens it too, for example in another computer.

Without encryption on the system disk the question isn't asked, and the other disks are kept as they are.

### Secure Boot

karchy can set up Secure Boot with its own keys. Microsoft's keys are enrolled beside them, because GPU firmware and Windows need them.

**During the install:**

1. Before you boot the stick, put the firmware in Setup Mode. In the firmware's Secure Boot settings, clear or delete the keys. Some firmware calls this "Reset to Setup Mode" or "Erase all Secure Boot settings".
2. The form then asks about Secure Boot, with Yes selected.
3. After the install, turn Secure Boot on in the firmware if it didn't turn on by itself.

**After the install:**

1. Put the firmware in Setup Mode, as above, and start karchy.
2. Run `karchy secureboot setup` in a terminal. It asks for your password and does the rest.
3. Restart. If `sbctl status` still shows Secure Boot off, turn it on in the firmware settings.

Outside Setup Mode the command changes nothing and says how to get there. If a step fails, the computer boots as before and you can run the command again.

If a firmware update clears the keys, the computer still boots, without Secure Boot. A notification at login offers to enroll the keys again.

### Laptops and NVIDIA

The installer looks at the computer and adds what it needs:

- A computer with a battery gets the laptop settings: power profiles, lid and sleep handling, and Thunderbolt support.
- A computer with an NVIDIA GPU gets NVIDIA's driver. RTX 20 and GTX 16 series and newer get the current driver. GTX 900 and 10 series, Quadro M and P, and Titan V get the 580 legacy driver. NVIDIA's drivers don't support older cards; those use the open nouveau driver, and the installer says so.

### What the installer sets up

- a 4 GiB EFI partition, and the rest of the disk as btrfs (inside LUKS2 when encrypted)
- a swap file the size of the memory, which hibernation uses
- two kernels: `linux-cachyos`, and `linux-cachyos-lts` as the fallback
- the Limine boot menu, with a snapshot of the system before and after every package change
- your account, with fish as the shell
- the karchy desktop

Every step is logged to `/var/log/karchy-install.log`, which is copied into the installed system.

## Other ways to install

### From the Arch Linux ISO

The same installer runs from the stock Arch ISO.

1. Boot the Arch ISO in UEFI mode and connect to the network (`iwctl` for Wi-Fi).
2. Run:

   ```sh
   pacman -Sy --noconfirm git
   git clone https://github.com/Nulifyer/karchy.git
   karchy/install/karchy-install
   ```

3. Continue from [Answer the form](#4-answer-the-form).

### Without the form: an answer file

`karchy-install --config FILE` reads the answers from a file and asks nothing. The disk named in the file is erased without a confirmation.

On the karchy ISO, press Esc at the first question to get a shell, then run the command. Or add `karchy.config=<file or http(s) URL>` to the boot entry (press `e` in the boot menu): the ISO fetches the file once the network is up and installs from it.

The file sets shell variables, one per line:

```sh
KARCHY_DISK=/dev/nvme0n1
KARCHY_USER=ada
KARCHY_PASSWORD='a long password'
KARCHY_HOSTNAME=desk
KARCHY_TIMEZONE=Europe/London
```

Those five are required. The optional ones:

| Variable | Values | Default |
| --- | --- | --- |
| `KARCHY_KEYMAP` | a console keyboard layout, such as `de` | `us` |
| `KARCHY_FULL_NAME`, `KARCHY_EMAIL` | for git | none |
| `KARCHY_ENCRYPT` | `encrypted`, or `login` for no encryption | `encrypted` |
| `KARCHY_ENCRYPT_DISKS` | other internal disks to erase and encrypt, separated by spaces: `"/dev/sdb /dev/nvme1n1"`. Needs `KARCHY_ENCRYPT=encrypted` | none |
| `KARCHY_CHANNEL` | `stable`, `rc` or `nightly` | `stable` |
| `KARCHY_SECUREBOOT` | `auto` sets it up when the firmware is in Setup Mode; `yes`; `no` | `auto` |
| `KARCHY_BEES` | `yes` or `no` | `yes` |
| `KARCHY_CACHYOS_LEVEL` | `generic` skips CachyOS's CPU-tuned packages; otherwise the installer picks `v3`, `v4` or `znver4` from the CPU | from the CPU |
| `KARCHY_KEYRING_KEY_FILE` | a key saved with `karchy keyring-key export`, so a home folder restored from a backup opens its saved passwords. Not with `KARCHY_ENCRYPT=login` | none |
| `KARCHY_CONSOLE_FONT` | `karchy-10x20`, `karchy-12x24` or `karchy-16x32` | from the screen's height |
| `KARCHY_REPO_SERVER`, `KARCHY_REPO_SIGLEVEL` | another `[karchy]` package repository | karchy's own |

An install from an answer file ends at a shell: type `reboot`, and take the stick out once the screen goes dark. With `--reboot` it restarts by itself.

To build the ISO yourself or test in a virtual machine, see [Working on karchy](development.md).
