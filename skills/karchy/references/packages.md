# Updates, packages and Quick install

Read this before you install, remove or update software, change the release channel, or explain what an update did.

## Where software comes from

- Install software with pacman from the configured repositories: Arch, `[cachyos]`, `[omarchy]` and `[karchy]`.
- Use paru for an AUR package only when no configured repository carries the software.
- Do not use `curl | bash` installers, mise, or Flatpak for system software. Do not suggest them as the first choice.
- Never run `pacman -Sy <package>` alone. A refresh without the full upgrade is a partial upgrade. Use `karchy update`, or `pacman -S` against the databases already synced.

## The AUR rules

An AUR package runs a stranger's build script with the user's rights.

- Prefer a package from a signed repository. Check with `pacman -Si <name>` before you look at the AUR.
- Accept an AUR package only when it is well kept: many votes, a current maintainer, not flagged out of date. Quick install applies that rule to its own list (100 or more votes).
- Prefer the `-bin` build when Arch has no package. Build from source only when no `-bin` exists.
- Let the user read paru's review of the build files. Do not pass `--skipreview` or `--noconfirm` to paru for a new AUR package.
- Run paru in a terminal with the user present. `karchy-pkg-install` is the interactive picker: one list, repository packages first, then the AUR, each row marked with its source.

## Updating

`karchy update` (`karchy-update`) is the only update path. It runs these steps:

1. Checks without root and shows the plan: the karchy release change, each package with old and new version, the download size, Arch news since the last update, and whether a restart is needed.
2. Asks once, then asks for the password once.
3. Installs keyrings first, then runs the full `pacman -Syu`. snap-pac takes a snapshot before and after.
4. Removes core packages karchy has retired, when nothing else needs them.
5. Updates AUR packages with paru.
6. Lists `.pacnew` files, runs karchy's migrations, and reloads the desktop.

- `karchy-update --plan` prints the plan as JSON and installs nothing. Use it to answer "what would an update change?".
- `karchy-update -y` skips the question and paru's review. Use it only when the user asks for an unattended update.
- `karchy updates` opens the Updates window, which shows the same plan.
- If the plan lists Arch news, tell the user to read it before the update. Arch announces manual steps there.
- After the update, report `.pacnew` files and tell the user to merge them with `pacdiff -s`. Do not merge them without the user.
- If the summary says a restart is needed, say so. The running kernel's modules are gone after a kernel update.
- `karchy-update-check` only checks. It writes `~/.local/state/karchy/updates.json` for the bar.

An update is a large change that already takes its own snapshots. If an update breaks the system, read `snapshots.md`.

## Release channels

`karchy channel` (`karchy-channel`) shows the channel. `karchy channel set <stable|rc|nightly>` changes it.

- The channel covers only karchy's own packages. Arch and CachyOS packages are the same on every channel.
- `/etc/pacman.d/karchy-server` names the channel's repository. Do not edit it by hand.
- A channel change installs that channel's version of every karchy package, also when it is older, then reloads the desktop. Treat it as a large change and get the user's agreement first.
- `karchy version` shows the installed release and channel.

## Installing and removing packages

| Need | Command |
| --- | --- |
| Install named repo packages without questions | `karchy-pkg-add <packages...>` |
| Remove named packages when installed | `karchy-pkg-drop <packages...>` |
| Test whether packages are installed | `karchy-pkg-present <packages...>`, `karchy-pkg-missing <packages...>` |
| Let the user pick packages, from the repositories or the AUR | `karchy-pkg-install` (interactive; repository packages are listed first, AUR rows say so; `--aur` lists only the AUR) |
| Let the user pick packages to remove | `karchy-pkg-remove` (interactive) |

`karchy-pkg-add` and `karchy-pkg-drop` use sudo. Run them in a terminal with the user present. `karchy-pkg-drop` removes with `pacman -Rns`, so it also removes unneeded dependencies and config files.

## Quick install

Quick install is the catalog of apps and karchy features. The catalog is `/usr/share/karchy/default/karchy/quick-install.json`.

- `karchy-quick-install` opens the window. `karchy-quick-install window <search>` opens it with a search, `karchy-quick-install window @<category id>` at a category.
- Each app names its `category`. Most categories also list `groups`, what their apps are for ("Coding agents", "Run models on this computer"), and an app of such a category names one in `group`; the window shows them as headings. List one group with `jq -r '.apps[] | select(.category == "ai" and .group == "agents") | .id' <catalog>`.
- `karchy-quick-install status` prints which catalog apps are installed, as JSON.
- `karchy-quick-install install <id>` and `remove <id>` work in a terminal for one catalog id. They also apply the entry's declared setup: multilib, the 32-bit graphics driver, services, groups, kernel modules to load and firewall ports.
- An entry that lists several packages is installed as one package, `karchy-app-<id>` (for example `karchy-app-lutris`). It has no files and depends on the entry's packages, so `remove <id>` also removes what came with the app, unless something else needs it or the user installed it by name. `pacman -R` on one of those parts is refused while the app is installed; remove the app instead.
- An entry's `conflicts` are packages the app can't be installed beside. Install refuses while one is installed and names the app it belongs to: Docker is refused beside `podman-docker`, which is part of Podman. Remove that app first.
- An AUR entry builds its AUR packages with paru (the first package, or the ones its `aur` list names: DroidCam and its kernel module `v4l2loopback-dc-dkms`); the rest come with its `karchy-app-<id>` package.
- Such an app counts as installed when `karchy-app-<id>` is installed, or when its first package was installed by hand.
- Prefer a catalog id over raw package names when the catalog has the app. Find the id with `jq '.apps[] | select(.name | test("<name>"; "i")) | .id' <catalog>`.
- karchy features are catalog entries with a `feature` script: `containers`, `vms` and `printing`. Install them with `karchy-quick-install install <id>` or the window, not by package name, so that their setup runs.
- An app marked `required` cannot be removed.

The window installs repo apps through the root helper `/usr/lib/karchy/app-packages`, which asks for the administrator's password and accepts catalog ids only. Do not call the helper directly.

## Core packages, apps and retired packages

- Core packages are the dependencies of `karchy`, `karchy-desktop`, `karchy-settings` and the meta-packages. karchy owns that set. Do not remove a core package, even when the user does not use it. An update can bring it back or break on its absence.
- The apps a fresh install adds (the catalog's `default` entries) belong to the user. Remove them when the user asks. An update never reinstalls them.
- `/usr/share/karchy/default/karchy/retired-packages` lists core packages karchy dropped. `karchy update` removes one only when it is installed as a dependency and nothing needs it. A copy the user installed explicitly stays.
- `karchy-package-retire plan` shows what the next update would remove or keep.
- The update summary names other orphans and leaves them. Remove them only when the user agrees.

## Migrations

A migration is a script that changes what pacman cannot: files in the home folder, or files in `/etc` that the package no longer owns. `karchy update` runs pending migrations in step 6.

- `karchy-migrate status` lists each migration as done or pending.
- A failed migration does not stop the update. Its output is in `~/.local/state/karchy/migrations/<name>.log`. The next update runs it again.
- Do not mark a migration done by hand, and do not run `karchy-migrate baseline` on an installed system. It marks every migration done without running it.

## Mirrors and firmware

- A mirror in the middle of a sync can fail an update with `failed retrieving file '<package>.sig' from <mirror>`: pacman asks for a signature only where the package came from. `karchy update` gets round it by itself (it repeats the step with that mirror last, in a copy of the mirror lists; `/etc` stays as it is). For a bare `pacman` that fails this way: `sudo pacman -Syu 2>&1 | tee /tmp/out`, then `conf=$(karchy-mirrors-demote --config </tmp/out)` and `sudo pacman --config "$conf" -Syu`. Or wait an hour and try again.
- `karchy-mirrors.timer` ranks Arch mirrors each week (`karchy-mirrors-rank`, as root). The old list stays as `/etc/pacman.d/mirrorlist.karchy-backup`. If downloads fail after a ranking, restore that file.
- `karchy-update-firmware` updates device firmware with fwupd (the Updates window's Firmware part runs it; `karchy updates firmware` opens there). It uses sudo and can require a restart. Treat it as a large change: get the user's agreement and keep a laptop on AC power.
