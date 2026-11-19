# Maintenance

What keeps a karchy machine current after it is installed, and what needs a person. karchy maintains only what it has to own (D-89). Nothing here runs on a calendar: work starts when a check or a machine reports a problem. Update the register in the same change that adds a pin, a fork or a copied file.

## What updates itself

An installed machine runs `karchy update` (or the Updates window). That is one full `pacman -Syu` plus `paru` for AUR packages, so everything on the machine comes straight from its own project:

| Part | Comes from | Who keeps it current |
| --- | --- | --- |
| Kernel, NVIDIA driver, pacman, Mesa, CPU-tuned builds | `[cachyos]` | CachyOS |
| Everything else in the base (Hyprland, Quickshell, PipeWire, apps) | Arch `core` and `extra` | Arch |
| omasnap, omarchy-speedtest, ttfx, and the apps omawrite, omacalc, localsend-bin, disktree-bin | `[omarchy]` | Omarchy |
| Signing keys and CachyOS's mirror list | each project's `-keyring` and `-mirrorlist` packages; keyrings are installed first in every update | each project |
| Apps the user added from the AUR | AUR, built by paru | each AUR maintainer |
| karchy's own packages | `[karchy]`, the machine's channel | karchy (CI builds, signs and publishes each push and tag) |

The base install has no AUR package. karchy rebuilds no third-party package except the two in the register (titlebars, bees).

### Changes pacman can't make: migrations

pacman replaces packaged files in `/usr` on its own, so a change there needs nothing more. A change that alters files in a user's home, or files in `/etc` that pacman no longer updates (a copy the installer or a command wrote, or a config file the user changed), ships with a migration in the same commit. Without one, machines installed before the change keep the old files, and a karchy machine is updated, never reinstalled.

- **Where:** `migrations/` in the repository; the karchy package installs it as `/usr/share/karchy/migrations`.
- **Name:** `<unix time>-<what it does>.sh`, the time the migration was written (`date +%s`), so the names sort in the order they were written and run in that order: `1795100000-indicators-hidden.sh`.
- **How it runs:** `karchy update` (step 6) runs `karchy-migrate run` as the user who runs the update, after the packages are installed, each migration with `bash -euo pipefail`. A migration may change that user's home and, through `sudo` (the update already holds the password), files in `/etc`. It may not install or remove packages (that is the packages' job) and doesn't ask questions. Every user of a machine runs it once, so a change to `/etc` must be idempotent, and so must everything else: it can meet files that are already new.
- **When it fails:** it is not marked done, its output stays in `~/.local/state/karchy/migrations/<name>.log`, the update's summary and a notification name it, the update carries on with the rest, and the next update runs it again.
- **New users:** the installer runs `karchy-migrate baseline` for the first user, marking every migration shipped at install time as done without running it; the karchy package puts the same marks in `/etc/skel`, so a user created later starts with the migrations of that day done. Their files are made by the karchy installed then, so older fixes don't apply.
- **Test it** on a machine, or VM, installed before the change: `karchy-migrate status` shows it pending, `karchy update` runs it, `status` shows it done.

The release channel (stable, rc, nightly) covers only karchy's packages. Arch and CachyOS packages are the same on every channel, on the day the machine updates.

## What is watched

`.github/workflows/upkeep.yml` runs every day and reports through one GitHub issue, "Upkeep: karchy no longer installs cleanly from the repositories". The repositories are often out of step for a day or two (a CachyOS rebuild behind Arch's update), and that passes by itself, so the issue is opened when a failure lasts into its third day and closes by itself when the checks pass again. No issue means nothing needs doing.

| Check | What it proves | Covers |
| --- | --- | --- |
| `tools/repos-check` | In a stock Arch container, the installer's own repository setup works (pinned keys, bootstrap mirror list, the projects' keyring and mirror list packages), and pacman can resolve everything a karchy machine installs, for an empty system: the base, every `[karchy]` package with its dependencies, the apps karchy ships, and the legacy NVIDIA driver. Once with CachyOS's generic repository and once with each set of its CPU-tuned ones (v3, v4, znver4), for each channel with a release | Items 3, 7, 8 and 10 |
| `tools/catalog-check` | Every Quick install entry's packages exist where the entry says | Item 9 |

The daily scheduled run of `release.yml` rebuilds the titlebars; when that fails, GitHub emails the failed run (item 2).

## Register: what needs a person

| # | Item | When it needs work | How it is noticed | What to do |
| --- | --- | --- | --- | --- |
| 1 | karchy's own code against new Hyprland, Quickshell, uwsm and PipeWire releases | A release changes a config option, the Lua API or a QML type karchy uses | A machine updates and something is broken. No check runs before that | Boot the pre-update snapshot from the boot menu, fix karchy, release |
| 2 | `karchy-hyprland-titlebars` (Omarchy's hyprbars fork, v0.4.0) | Every Hyprland update needs a rebuild; an update that changes the plugin API needs a source fix or a newer upstream tag | Rebuild: automatic, daily at 06:17 UTC on all three channels. Build failure: GitHub's failed-run email | Patch or raise `_upstream` in the PKGBUILD. Until then floating windows have no titlebars; nothing else breaks |
| 3 | `[omarchy]` packages karchy depends on | Omarchy builds them for its own older, pinned Arch. A library version change in Arch can break one; Omarchy can rename or drop one | The upkeep issue | Rebuild the package in `[karchy]`, replace it, or drop it |
| 4 | `karchy-bees` (fork Nulifyer/bees, pinned tag and commit; owned for now, D-85) | Upstream bees fixes; a new kernel series | By hand | Merge upstream into the fork's `karchy` branch, test, tag, set `pkgver` and `_commit` |
| 5 | `nulifyer-vpn` (Nulifyer/omarchy-vpn-plugin, pinned tag and commit) | Each release of the plugin | By hand | Set `pkgver` and `_commit` |
| 6 | karchy's signing key | Only if it leaks or is lost. It has no expiry | — | `packaging/keyring/README.md` |
| 7 | Build container (`packaging/container/Containerfile`, Arch base-devel pinned by digest) | Rarely: every build refreshes Arch's keyring before anything else, so an old image keeps working. Only when the image is too old even for that | A failed CI build, or the upkeep issue (the check runs in the same image) | Pull, set the new digest and label |
| 8 | The installer's starting copies: `packaging/keyring/omarchy.gpg` and `cachyos.gpg`, their fingerprints in `install/base.sh`, and `install/cachyos-mirrorlist` | Rarely: they only fetch the projects' keyring and mirror list packages, which take over for the rest of the install. Only when a project replaces its key, or every bootstrap mirror is gone | The upkeep issue | Refresh the files and fingerprints |
| 9 | Quick install list (`default/karchy/quick-install.json`: 534 apps, 30 from the AUR; owned for now) | A package is renamed, dropped, or an AUR package is abandoned | The upkeep issue | Fix or remove the entry |
| 10 | NVIDIA: the GPU generation table (`karchy-hw-nvidia-generation`) and CachyOS's driver package names | A new GPU generation; CachyOS retires the 580xx branch | Package names: the upkeep issue. A new generation: a new install picks the wrong driver | Update the table or the meta-package's depends |
| 11 | Arch manual interventions | Arch announces one | The Updates window and `karchy update` show Arch news since the last update | Follow it on each machine; if it concerns files karchy owns, ship a migration (`migrations/*.sh`) |
| 12 | GitHub's scheduled runs | GitHub turns them off in a public repository after 60 days without repository activity. That stops the titlebars rebuild and the upkeep check | The Actions page shows the workflows as disabled; floating windows lose their titlebars after the next Hyprland update | Actions › the workflow › Enable workflow. Any work on karchy within 60 days avoids it. karchy doesn't work around the limit: the best-known tool for that was removed by GitHub for breaking its terms |

## Not tracked

Omarchy's later changes to the code karchy took (D-46). karchy owns that code, and nothing follows upstream. `tools/upstream-review` can still show what Omarchy changed in a file, for the day a bug in borrowed code makes it worth a look.

## When something reports

- **The upkeep issue opens:** its text carries pacman's own errors. If they name an Arch or CachyOS package pair (one repository behind the other), wait for it to close; otherwise find the item in the register. A failure of the legacy NVIDIA driver on a `lib32-` package means every 32-bit package (Steam) fails to install on machines of that CPU level until CachyOS rebuilds the 64-bit library; karchy has nothing to fix.
- **A failed-run email:** read the run. The scheduled run of `release.yml` builds only the titlebars, so a failure there is item 2 or 7. A failed `upkeep` run means the check itself is broken.
- **A machine breaks after an update:** boot the pre-update snapshot, fix karchy, release (item 1).
- **Before tagging a release:** update a nightly machine or VM first and use it.
