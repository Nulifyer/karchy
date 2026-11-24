# Packaging

`pkgbuilds/` holds the PKGBUILDs for karchy's packages; `build` turns this repository into a `[karchy]` pacman repository for one release channel (D-51 to D-53, D-61).

| Package | What it is |
|---|---|
| `karchy` | The desktop: commands, Quickshell shell, Hyprland layer, theme engine, menu (`/usr/share/karchy`, `/usr/bin/karchy*`), and `/usr/share/karchy/release` (version, channel, commit) |
| `karchy-settings` | System defaults, lock-screen PAM, sudo rules, session units, starter configs in `/etc/skel` |
| `karchy-themes` | Themes and wallpapers |
| `karchy-hyprland-titlebars` | Native: Omarchy's titlebar plugin built against Arch's Hyprland (D-60) |
| `karchy-keyring` | The public signing key; built once `keyring/karchy.gpg` exists (see `keyring/README.md`) |
| `karchy-desktop` | Meta: the above plus the session, services, fonts and apps |
| `karchy-laptop` | Meta: what a machine with a battery adds |
| `karchy-nvidia` | Meta: NVIDIA drivers for both kernels |
| `karchy-nvidia-580xx` | Meta: NVIDIA's 580 legacy driver for both kernels (Maxwell, Pascal, Volta); provides and conflicts with `karchy-nvidia` |
| `karchy-vm` | Meta: SPICE and QEMU guest agents, for a VM |
| `karchy-bees` | Native: bees, the btrfs deduplicator, built from a pinned tag of karchy's fork Nulifyer/bees (D-85); provides and conflicts with Arch's `bees`; a `karchy-settings` dependency; `karchy-bees.service` runs it (D-86) |
| `karchy-vpn` | Transitional and empty (D-156): the VPN moved into `karchy-settings`; a machine with the old add-on upgrades to this in the same transaction, so the files change owner without the add-on's removal script running, and `karchy update` then retires it |
| `karchy-project-picker` | Add-on (D-106): the project picker overlay and its Ctrl+Alt+P binding, built from `addons/project-picker`; offered in Quick install › karchy |
| `karchy-containers-app` | karchy's own app (D-164): the Containers window's launcher entry and its agent skill; depends on `karchy` and on no container engine; offered in Quick install › karchy. Replaces `karchy-containers` |
| `karchy-podman` | Optional feature (D-67, D-164): karchy's rootless Podman setup with `podman-docker` and `docker-compose`, the user socket and `DOCKER_HOST`; installed by Quick install › System › Podman (`karchy-feature-podman`). Replaces `karchy-containers` |
| `karchy-printing` | Optional feature (D-67): the cups-browsed user and sandbox drop-in, ipp-usb; installed by Quick install › System › Printers & scanners |
| `guget`, `sqlgo` | Native: the user's own tools, repackaged from a pinned GitHub release's `linux_amd64` binary with its checksum (D-155); offered in Quick install › Developer tools and › Databases & APIs |
| `karchy-app-<id>` | Meta, one per Quick install app of several packages (D-150): no files, depends on the app's packages, so pacman removes them with the app. All made by one PKGBUILD, `pkgbuilds/karchy-apps`, from `default/karchy/quick-install.json` |

## Channels and versions (D-61)

| Channel | Gets | Versions | Repository |
|---|---|---|---|
| stable | releases | `3.0.0` | GitHub release `repo-stable` |
| rc | release candidates and releases | `3.1.0rc1`, `3.0.0` | `repo-rc` |
| nightly | every push to main | `3.0.0.r12.gabc1234` | `repo-nightly` |

Versions come from git tags (`v3.0.0`, `v3.1.0-rc.1`) through `git describe`, in pacman's ordering: `3.1.0rc1 < 3.1.0`, and a nightly `3.0.0.r12.g…` sits between `3.0.0` and the next release. Users pick a channel in the installer or in the Updates window (`karchy channel set <channel>`). Only karchy's packages follow the channel; Arch, CachyOS and AUR packages update through pacman and paru as usual, all in one `karchy update`.

Within a channel every package is rebuilt and compared by content hash with the repository's copy; only packages whose contents changed take the new version, so an update downloads what changed (`karchy` always changes: it carries the release file). Native packages and packages built from another repository compute their own version (`# karchy:version-cmd=`) and rebuild when it changes: for the titlebars when Arch's Hyprland changes, for `karchy-bees` when its `pkgver` is moved to a new tag. A version command that prints nothing skips the package. The add-ons (`karchy-project-picker`) are built from this repository like `karchy` and take its version.

A package whose folder in `pkgbuilds/` is deleted is taken out of each channel's repository by that channel's next full build, so a renamed or split package doesn't stay installable beside the ones that replace it (`karchy-containers`, D-164).

`pkgbuilds/karchy-apps` is the one PKGBUILD that makes several packages (`# karchy:split=karchy-app-`). It reads the catalog, which the build puts beside it (`# karchy:beside=`), so an app's packages are written down once. Each `karchy-app-<id>` is compared and versioned on its own, so a release that changes one entry publishes one small package; an entry that stops being several packages has its package taken out of the repository.

## Building

```sh
packaging/build                                   # dev channel from the working tree, into out/repo-dev
packaging/build --channel stable --version 0.1.0  # a local stand-in for a release
packaging/build --ref main                        # package a commit instead of the working tree
packaging/build karchy-themes                     # only some packages
```

Releasing bees: tag `v<version>` on the fork's `karchy` branch (Nulifyer/bees) and push it, then in `pkgbuilds/karchy-bees/PKGBUILD` set `pkgver` and `_commit` to the tag's commit (`git rev-parse v<version>^{commit}`). Versions use `_` where a tag would use `-` (`0.11_karchy1`). It is a native package: `packaging/build --native karchy-bees`.

Releasing guget or sqlgo into `[karchy]`: in `pkgbuilds/<name>/PKGBUILD` set `pkgver` to the GitHub release's tag without the `v` and `sha256sums` to the `linux_amd64` line of that release's `checksums.txt`. Each channel publishes it with its next build (`packaging/build --native guget sqlgo` locally).

`tools/vm repo` serves `out/` so test VMs reach `http://10.0.2.2:8090/repo-<channel>`; `tests/vm-install.conf` installs from `dev`.

## Build container

Builds run in a fresh container of `container/Containerfile`, removed when the build ends: `packaging/build` and `packaging/iso/build` start one themselves, and CI runs `ci/publish` in one. Every build, here or in CI, starts from the same files: stock Arch, pinned by image digest, with the build tools and Arch's own makepkg settings. Nothing comes from the machine running it, such as a CachyOS `makepkg.conf` that compiles for that machine's CPU.

- `container/run [--writable] [--volume DIR] [--env NAME] [--iso] [--refresh] -- COMMAND` runs a command in one (`--help`). It needs rootless podman. Your account is the container's `builder`, so files it writes belong to you. The checkout is mounted read-only at its own path, with `out/` writable. In a git worktree, the repository it belongs to (`git rev-parse --git-common-dir`) is mounted read-only too, so a build there packages the same files and takes the same version as in a plain checkout; git inside can't commit or check out there, even with `--writable`.
- The image is built the first time and tagged with the Containerfile's hash, so a changed Containerfile builds a new one. `--refresh` rebuilds it with the current tools.
- Downloaded packages stay in the podman volume `karchy-build-pkg-cache`.
- Native builds (`--native`) upgrade the container's packages first, so they build against Arch as it is that day.
- The image build, native builds and the ISO build each install Arch's current keyring before any other package, so the pinned base keeps verifying packages signed by newer packagers.
- To move the base image forward, put a new digest in the Containerfile (its comment says how). That is rarely needed (docs/maintenance.md, item 7).

## Publishing

`.github/workflows/release.yml` runs `ci/publish` in the build container, one job per channel so each repository has one writer at a time. `ci/publish` downloads the channel's repository from its GitHub release, builds with `--native --sign`, and uploads only new and changed files, packages before the database. Tags `vX.Y.Z` publish stable and rc (rc is skipped when it is already ahead), `vX.Y.Z-rc.N` publishes rc, each with a release page: `.github/release-notes.md`'s install and update steps, GitHub's list of changes (highlights are added by hand), and the ISO with its checksum, built in the build container by `.github/workflows/iso.yml` (which can also rebuild an existing release's ISO by hand); pushes to main publish nightly; a daily run rebuilds each channel's titlebars from that channel's released commit when Arch's Hyprland changes. The version always comes from the pushed tag.

`.github/workflows/upkeep.yml` runs `ci/upkeep` every day: `tools/repos-check` (karchy still installs from the live repositories) and `tools/catalog-check`. A failure that lasts into its third day becomes one issue, closed again when the checks pass (docs/maintenance.md).

Before the first run: the signing key (`keyring/README.md`) and the `KARCHY_SIGNING_KEY` secret and `KARCHY_SIGNING_KEY_ID` variable on GitHub.
