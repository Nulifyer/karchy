#!/bin/bash
# The split of karchy-containers into karchy-podman (karchy's Podman setup)
# and karchy-containers-app (the Containers window), D-164, with the real
# pacman in a throwaway container of stock Arch. Each starting point a machine
# can be in comes through the update unharmed:
#   - real Docker and no karchy package: the update adds nothing; the app
#     installs beside Docker, and karchy's Podman setup is refused
#   - the old karchy-containers: the update puts both new packages in its
#     place, each the user's own; Podman and its parts stay dependencies of an
#     installed package, so no clean-up of orphans can take them; the socket
#     for every user, DOCKER_HOST and podman-docker's quiet switch are there
#     as before; removing the app leaves all of that alone; Docker is refused
#     beside it, naming Podman
#   - nothing installed: the app installs with no container engine, and
#     karchy-containers says none is installed
# The update is `pacman -Syu --noconfirm`, as `karchy update` runs it.
#
# Usage: tests/containers-split-container.sh OLD [NEW]
#   OLD  a folder holding the old karchy-containers package, built from a
#        commit before D-164 (`packaging/build --ref <commit> --repo OLD
#        karchy-containers` there)
#   NEW  a built [karchy] repository with karchy-podman,
#        karchy-containers-app and karchy-app-docker (default out/repo-dev)
# The app depends on karchy, whose own dependencies are the whole desktop and
# not what is tested here, so an empty stand-in package of that name is
# installed first.
# Needs podman (rootless) and the network; downloads about 400 MB.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

if [[ ${1:-} != "--inside" ]]; then
  [[ -n ${1:-} ]] || { sed -n 's/^# Usage: //p' "$0"; exit 2; }
  old=$(realpath "$1") new=$(realpath "${2:-$root/out/repo-dev}")
  compgen -G "$old/karchy-containers-[0-9]*.pkg.tar.zst" >/dev/null || { echo "no old karchy-containers package in $old"; exit 2; }
  for name in karchy-podman karchy-containers-app karchy-app-docker; do
    compgen -G "$new/$name-[0-9]*.pkg.tar.zst" >/dev/null || { echo "no $name package in $new: run packaging/build"; exit 2; }
  done
  image=$(sed -n 's/^FROM //p' "$root/packaging/container/Containerfile")
  exec podman run --quiet --rm --volume "$root:$root:ro" --volume "$old:/old:ro" --volume "$new:/new:ro" "$image" \
    "$root/tests/containers-split-container.sh" --inside "$root"
fi
root=$2

pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
# Exact names: pacman -Q also answers for what a package provides (docker,
# from podman-docker).
have() { pacman -Qq "$@" 2>/dev/null | grep -xF -f <(printf '%s\n' "$@") | paste -sd' ' -; }
reason() { if [[ $(pacman -Qeq -- "$1" 2>/dev/null) == "$1" ]]; then echo explicit; elif pacman -Qq -- "$1" >/dev/null 2>&1; then echo dependency; else echo absent; fi; }
owner() { pacman -Qqo "$1" 2>/dev/null || echo nobody; }
orphans() { pacman -Qdtq 2>/dev/null | sort | paste -sd' ' -; }
# How many files of karchy's set DOCKER_HOST for every session.
docker_host_files() { compgen -G '/usr/lib/environment.d/*karchy*' | wc -l; }
engines() { "$root/bin/karchy-containers" engines; }
PARTS=(podman crun netavark aardvark-dns passt podman-docker docker-compose)

# Two repositories of this machine's own: the one before the split and the
# one after, each with only the packages under test.
use_repo() {
  sed -i "s|^Server = file:///repo-.*|Server = file:///repo-$1|" /etc/pacman.conf
  # -yy: the two databases were made in the same minute, and pacman takes one
  # that is no newer than its copy for the same.
  pacman -Syy >>/tmp/pacman.log 2>&1
}
{
  mkdir -p /repo-old /repo-new /tmp/stub
  cp /old/karchy-containers-[0-9]*.pkg.tar.zst /repo-old/
  cp /new/karchy-podman-[0-9]*.pkg.tar.zst /new/karchy-containers-app-[0-9]*.pkg.tar.zst /new/karchy-app-docker-[0-9]*.pkg.tar.zst /repo-new/
  repo-add -q /repo-old/karchy.db.tar.gz /repo-old/*.pkg.tar.zst
  repo-add -q /repo-new/karchy.db.tar.gz /repo-new/*.pkg.tar.zst
  printf '\n[karchy]\nSigLevel = Optional TrustAll\nServer = file:///repo-old\n' >>/etc/pacman.conf
  pacman-key --init && pacman-key --populate archlinux
  pacman -Sy --noconfirm --needed archlinux-keyring
  pacman -S --noconfirm --needed jq
  # The stand-in for karchy.
  printf 'pkgname = karchy\npkgbase = karchy\npkgver = 0.0.1-1\npkgdesc = stand-in for the test\narch = any\nsize = 0\n' >/tmp/stub/.PKGINFO
  bsdtar -C /tmp/stub --zstd -cf /tmp/karchy-0.0.1-1-any.pkg.tar.zst .PKGINFO
  pacman -U --noconfirm /tmp/karchy-0.0.1-1-any.pkg.tar.zst
} >/tmp/setup.log 2>&1 || { tail -n 20 /tmp/setup.log; echo "setup failed"; exit 2; }
install -Dm644 "$root/default/karchy/quick-install.json" /usr/share/karchy/default/karchy/quick-install.json
install -Dm755 "$root/system/packages/app-packages" /usr/lib/karchy/app-packages
helper() { /usr/lib/karchy/app-packages "$@" 2>>/tmp/pacman.log | grep -E '^(done|failed) ' | paste -sd';' -; }
clean=$(orphans)

# ---- a machine with real Docker and no karchy package for containers
pacman -S --noconfirm --needed docker >>/tmp/pacman.log 2>&1
use_repo new
pacman -Syu --noconfirm >>/tmp/pacman.log 2>&1
check "Docker: the update adds neither new package" "$(have karchy-podman karchy-containers-app)" ""
check "Docker: the Containers app installs beside it" "$(helper install containers) $(reason karchy-containers-app)" "done containers explicit"
check "Docker: and brings no Podman" "$(have podman podman-docker)" ""
check "Docker: the app uses Docker" "$(engines)" '{"engine":"docker","also":"","cli":"docker"}'
check "Docker: karchy's Podman setup is refused" "$(pacman -S --noconfirm karchy-podman >>/tmp/pacman.log 2>&1; echo $?) $(have docker karchy-podman)" "1 docker"
pacman -S --noconfirm --needed podman >>/tmp/pacman.log 2>&1
check "both engines: the app uses Podman and says Docker is there too" "$(engines)" '{"engine":"podman","also":"docker","cli":"podman"}'
pacman -Rns --noconfirm karchy-containers-app docker podman >>/tmp/pacman.log 2>&1
check "Docker: removed again, nothing left behind" "$(have docker podman karchy-containers-app) [$(orphans)]" " [$clean]"

# ---- a machine with the old karchy-containers, as its feature installed it
use_repo old
pacman -S --noconfirm karchy-containers >>/tmp/pacman.log 2>&1
check "old: karchy-containers is the user's, with Podman" "$(reason karchy-containers) $(have "${PARTS[@]}" | wc -w)" "explicit ${#PARTS[@]}"
check "old: it owns the socket link and DOCKER_HOST" \
  "$(owner /usr/lib/systemd/user/sockets.target.wants/podman.socket) $(owner /usr/lib/environment.d/50-karchy-containers.conf)" "karchy-containers karchy-containers"
before=$(pacman -Q "${PARTS[@]}" 2>/dev/null)

use_repo new
check "update: pacman plans both new packages, and nothing of Podman's" \
  "$(pacman -Sup --print-format '%n' 2>/dev/null | sort | paste -sd' ' -)" "karchy-containers-app karchy-podman"
pacman -Syu --noconfirm >>/tmp/pacman.log 2>&1
check "update: it succeeded and the old package is gone" "$? [$(have karchy-containers)]" "0 []"
check "update: karchy's Podman setup is the user's" "$(reason karchy-podman)" explicit
check "update: the Containers app is the user's" "$(reason karchy-containers-app)" explicit
check "update: Podman and its parts are as they were" "$(pacman -Q "${PARTS[@]}" 2>/dev/null)" "$before"
check "update: each of them is needed by an installed package" \
  "$(for part in "${PARTS[@]}"; do [[ -n $(pacman -Qi "$part" | sed -n 's/^Required By *: *//p' | grep -v '^None$') ]] || echo "$part"; done | paste -sd' ' -)" ""
check "update: pacman sees no orphan" "$(orphans)" "$clean"
check "update: the socket is on for every user" \
  "$(readlink /usr/lib/systemd/user/sockets.target.wants/podman.socket) $(owner /usr/lib/systemd/user/sockets.target.wants/podman.socket) $([[ -e /usr/lib/systemd/user/podman.socket ]] && echo unit)" \
  "../podman.socket karchy-podman unit"
check "update: DOCKER_HOST points at Podman's socket" \
  "$(grep -h '^DOCKER_HOST=' /usr/lib/environment.d/*.conf)" 'DOCKER_HOST=unix://${XDG_RUNTIME_DIR}/podman/podman.sock'
check "update: once, from the new package's file" "$(docker_host_files) $(owner /usr/lib/environment.d/50-karchy-podman.conf)" "1 karchy-podman"
check "update: podman-docker's notice stays off, Compose's banner too" \
  "$(owner /etc/containers/nodocker) $(owner /usr/share/containers/containers.conf.d/50-karchy.conf)" "karchy-podman karchy-podman"
check "update: the window's launcher entry and both skills" \
  "$(owner /usr/share/applications/karchy-containers.desktop) $(owner /usr/share/karchy/agents/skills/karchy-containers/SKILL.md) $(owner /usr/share/karchy/agents/skills/karchy-podman/SKILL.md)" \
  "karchy-containers-app karchy-containers-app karchy-podman"
check "update: podman runs, and docker is Podman" "$(podman --version | cut -d' ' -f1) $(docker --version 2>/dev/null | cut -d' ' -f1)" "podman podman"
check "update: the app uses Podman, typed as docker" "$(engines)" '{"engine":"podman","also":"","cli":"docker"}'
check "update: a second update has nothing to do" "$(pacman -Sup --print-format '%n' 2>/dev/null | paste -sd' ' -)" ""

check "Docker is refused beside it, naming Podman" "$(helper install docker)" \
  "failed docker It can't be installed beside Podman (podman-docker). Remove that first"
check "and nothing changed" "$(have docker karchy-app-docker) $(reason karchy-podman)" " explicit"

check "the Containers app is removed alone" "$(helper remove containers) [$(have karchy-containers-app)]" "done containers []"
check "the engine stays the user's, whole" "$(reason karchy-podman) $(pacman -Q "${PARTS[@]}" 2>/dev/null | wc -l)" "explicit ${#PARTS[@]}"
check "with its socket and DOCKER_HOST" \
  "$(owner /usr/lib/systemd/user/sockets.target.wants/podman.socket) $(owner /usr/lib/environment.d/50-karchy-podman.conf)" "karchy-podman karchy-podman"
check "and still no orphan" "$(orphans)" "$clean"
check "the app comes back from Quick install" "$(helper install containers) $(reason karchy-containers-app)" "done containers explicit"
check "the old package can't be installed any more" "$(pacman -S --noconfirm karchy-containers >>/tmp/pacman.log 2>&1; echo $?)" "1"

# ---- removing karchy's Podman setup leaves the app; then a machine with nothing
pacman -Rns --noconfirm karchy-podman >>/tmp/pacman.log 2>&1
check "Podman's setup removed: its parts go, the app stays" "$(have "${PARTS[@]}" karchy-podman) [$(have karchy-containers-app)]" " [karchy-containers-app]"
check "nothing: no DOCKER_HOST, no socket link" \
  "$(docker_host_files) $([[ -L /usr/lib/systemd/user/sockets.target.wants/podman.socket ]] && echo link)" "0 "
check "nothing: the app says no engine is installed" "$(engines)" '{"engine":"","also":"","cli":""}'
check "nothing: and its command says what to install" "$("$root/bin/karchy-containers" list 2>&1; echo $?)" \
  $'No container engine is installed. Install Podman or Docker from Quick install › System.\n3'
pacman -Rns --noconfirm karchy-containers-app >>/tmp/pacman.log 2>&1
check "nothing: a fresh install of the app is the app and nothing else" \
  "$(LC_ALL=C pacman -Sp --print-format '%n' karchy-containers-app 2>/dev/null | paste -sd' ' -)" "karchy-containers-app"
check "nothing: the update adds neither package" "$(pacman -Syu --noconfirm >>/tmp/pacman.log 2>&1; have karchy-podman karchy-containers-app)" ""

echo "containers-split-container: $pass passed, $failures failed"
((failures == 0)) || { echo "--- pacman's output"; tail -n 60 /tmp/pacman.log; }
((failures == 0))
