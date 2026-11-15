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
| `nulifyer-vpn` | The VPN's system half (D-68): policy service, kill switch, sign-in pause, polkit rule. Built from a pinned tag of Nulifyer/omarchy-vpn-plugin, not from this repository; optional, controlled from the network panel |

## Channels and versions (D-61)

| Channel | Gets | Versions | Repository |
|---|---|---|---|
| stable | releases | `3.0.0` | GitHub release `repo-stable` |
| rc | release candidates and releases | `3.1.0rc1`, `3.0.0` | `repo-rc` |
| nightly | every push to main | `3.0.0.r12.gabc1234` | `repo-nightly` |

Versions come from git tags (`v3.0.0`, `v3.1.0-rc.1`) through `git describe`, in pacman's ordering: `3.1.0rc1 < 3.1.0`, and a nightly `3.0.0.r12.g…` sits between `3.0.0` and the next release. Users pick a channel in the installer or in Settings › About (`karchy channel set <channel>`). Only karchy's packages follow the channel; Arch, CachyOS and AUR packages update through pacman and paru as usual, all in one `karchy update`.

Within a channel every package is rebuilt and compared by content hash with the repository's copy; only packages whose contents changed take the new version, so an update downloads what changed (`karchy` always changes: it carries the release file). Native packages and packages built from another repository compute their own version (`# karchy:version-cmd=`) and rebuild when it changes: for the titlebars when Arch's Hyprland changes, for `nulifyer-vpn` when its `pkgver` is moved to a new tag. A version command that prints nothing skips the package (`nulifyer-vpn` until a release is pinned).

## Building

```sh
packaging/build                                   # dev channel from the working tree, into out/repo-dev
packaging/build --channel stable --version 0.1.0  # a local stand-in for a release
packaging/build --ref main                        # package a commit instead of the working tree
packaging/build karchy-themes                     # only some packages
NULIFYER_VPN_GIT=/path/to/omarchy-vpn-plugin NULIFYER_VPN_REF=my-branch \
  packaging/build nulifyer-vpn                    # the VPN from a local branch, before it is tagged
```

Releasing the VPN: tag `vX.Y.Z` in Nulifyer/omarchy-vpn-plugin and push it, then in `pkgbuilds/nulifyer-vpn/PKGBUILD` set `pkgver=X.Y.Z` and `_commit` to the tag's commit (`git rev-parse vX.Y.Z^{commit}`); `prepare()` refuses a tag that points elsewhere.

`tools/vm repo` serves `out/` so test VMs reach `http://10.0.2.2:8090/repo-<channel>`; `tests/vm-install.conf` installs from `dev`.

## Publishing

`.github/workflows/release.yml` runs `ci/publish` in an Arch container, one job per channel so each repository has one writer at a time. `ci/publish` downloads the channel's repository from its GitHub release, builds with `--native --sign`, and uploads only new and changed files, packages before the database. Tags `vX.Y.Z` publish stable and rc (rc is skipped when it is already ahead), `vX.Y.Z-rc.N` publishes rc, each with release notes; pushes to main publish nightly; a daily run rebuilds each channel's titlebars from that channel's released commit when Arch's Hyprland changes. The version always comes from the pushed tag.

Before the first run: the signing key (`keyring/README.md`) and the `KARCHY_SIGNING_KEY` secret and `KARCHY_SIGNING_KEY_ID` variable on GitHub.
