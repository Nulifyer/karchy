#!/bin/bash
# Quick install's root helper with the real pacman (D-150), in a throwaway
# container of stock Arch: an app of several packages is installed as its
# karchy-app-<id> package and removed with what came with it, a part the user
# asked for by name stays, and pacman's refusal names the app that still
# needs a package. Also that an app asking for the 32-bit graphics driver
# takes the driver installed for the machine, not the first one pacman knows.
#
# Usage: tests/app-packages-container.sh [REPO]
#   REPO  a built [karchy] repository holding the karchy-app-* packages
#         (default out/repo-dev; `packaging/build karchy-apps` makes them)
# Needs podman (rootless) and the network; downloads about 150 MB.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${1:-} != "--inside" ]]; then
  repo=$(realpath "${1:-$root/out/repo-dev}")
  compgen -G "$repo/karchy-app-*.pkg.tar.zst" >/dev/null || { echo "no karchy-app-* packages in $repo: run packaging/build karchy-apps"; exit 2; }
  image=$(sed -n 's/^FROM //p' "$root/packaging/container/Containerfile")
  exec podman run --quiet --rm --volume "$root:$root:ro" --volume "$repo:/repo:ro" "$image" \
    "$root/tests/app-packages-container.sh" --inside "$root"
fi
root=$2

pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
have() { pacman -Qq "$@" 2>/dev/null | paste -sd' ' -; }
reason() { if [[ $(pacman -Qeq -- "$1" 2>/dev/null) == "$1" ]]; then echo explicit; elif pacman -Qq -- "$1" >/dev/null 2>&1; then echo dependency; else echo absent; fi; }

{
  printf '\n[karchy]\nSigLevel = Optional TrustAll\nServer = file:///repo\n' >>/etc/pacman.conf
  printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' >>/etc/pacman.conf
  pacman-key --init && pacman-key --populate archlinux
  pacman -Sy --noconfirm --needed archlinux-keyring
  pacman -S --noconfirm --needed jq
} >/tmp/setup.log 2>&1 || { tail -n 20 /tmp/setup.log; echo "setup failed"; exit 2; }
install -Dm644 "$root/default/karchy/quick-install.json" /usr/share/karchy/default/karchy/quick-install.json
install -Dm755 "$root/system/packages/app-packages" /usr/lib/karchy/app-packages
helper() { /usr/lib/karchy/app-packages "$@" 2>>/tmp/pacman.log | grep -E '^(done|failed) ' | paste -sd';' -; }

check "Node.js installs" "$(helper install node-js)" "done node-js"
check "its package is the user's" "$(reason karchy-app-node-js)" explicit
check "its parts are dependencies" "$(reason nodejs) $(reason npm) $(reason pnpm)" "dependency dependency dependency"
check "pacman sees no orphan among them" "$(pacman -Qdtq | grep -xE 'nodejs|npm|pnpm' | paste -sd' ' -)" ""
check "pnpm, asked for by name, becomes the user's" "$(helper install pnpm) $(reason pnpm)" "done pnpm explicit"
check "removing pnpm is refused, naming the app" "$(helper remove pnpm)" "failed pnpm Node.js still needs it; nothing was changed"
check "Node.js is removed" "$(helper remove node-js)" "done node-js"
check "with its parts, except the user's pnpm" "$(have karchy-app-node-js nodejs npm pnpm)" "pnpm"
check "pnpm is removed" "$(helper remove pnpm) [$(have pnpm)]" "done pnpm []"
check "removing what isn't there is done" "$(helper remove node-js)" "done node-js"

# An app installed by hand, without its package: removed as itself.
pacman -S --noconfirm --needed uv python-pipx >>/tmp/pacman.log 2>&1
check "uv installed by hand is removed" "$(helper remove uv) [$(have uv)]" "done uv []"
check "and what the user installed beside it stays" "$(have python-pipx)" "python-pipx"

# The 32-bit driver: with this machine's drivers installed as dependencies
# (no GPU here: Mesa's software drivers), Steam's package takes them.
pacman -S --noconfirm --needed --asdeps lib32-mesa lib32-vulkan-swrast vulkan-swrast >>/tmp/pacman.log 2>&1
check "Steam's package pulls in no other graphics driver" \
  "$(LC_ALL=C pacman -Sp --noconfirm --print-format '%n' karchy-app-steam 2>&1 | grep -E 'vulkan-(radeon|intel|nouveau|virtio|swrast)|nvidia|amdvlk' | paste -sd' ' -)" ""

echo "app-packages-container: $pass passed, $failures failed"
((failures == 0)) || { echo "--- pacman's output"; tail -n 40 /tmp/pacman.log; }
((failures == 0))
