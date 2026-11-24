#!/bin/bash
# The apps' own packages (D-150): an app of several packages is installed as
# karchy-app-<id>, which depends on them. Checks, without pacman or root:
#   - the rule for which package stands for an app is written the same in the
#     three places that install apps;
#   - packaging/pkgbuilds/karchy-apps makes exactly the packages that rule
#     names, each depending on its entry's packages (an AUR app's packages
#     from the AUR left out, a gpu32 app with the driver names), and refuses a
#     catalog whose names aren't plain package names;
#   - `karchy-quick-install status`, against a fake pacman: an app with its
#     own package counts as installed by that package or by its first
#     package installed by hand, not when that came as a dependency.
# Usage: tests/app-packages-rule.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
catalog=$root/default/karchy/quick-install.json

# ------------------------------------------------------------------ the rule
rule() { grep -m1 -oE "TARGET='[^']+'" "$root/$1"; }
want=$(rule bin/karchy-quick-install)
check "the rule is found" "${want:0:11}" "TARGET='if "
for file in system/packages/app-packages install/setup.sh; do
  check "$file has the same rule" "$(rule "$file")" "$want"
done
TARGET=${want#TARGET=\'}
TARGET=${TARGET%\'}

# ------------------------------------------------------------- the PKGBUILD
# Sourced as makepkg does, with the catalog beside it; prints
# "<package><TAB><dependencies>".
made() {
  local dir=$1
  (
    cd "$dir" || exit 1
    # shellcheck disable=SC1091
    source ./PKGBUILD || exit 1
    for name in "${pkgname[@]}"; do
      depends=()
      "package_$name"
      printf '%s\t%s\n' "$name" "${depends[*]}"
    done
  )
}
mkdir "$tmp/real"
cp "$root/packaging/pkgbuilds/karchy-apps/PKGBUILD" "$catalog" "$tmp/real/"
packages=$(made "$tmp/real" | sort)
check "the PKGBUILD makes the packages the rule names" \
  "$(cut -f1 <<<"$packages")" \
  "$(jq -r ".apps[] | select(.feature | not) | $TARGET | select(startswith(\"karchy-app-\"))" "$catalog" | sort)"
check "and at least thirty of them" "$(($(wc -l <<<"$packages") >= 30))" 1
expected=$(jq -r '.apps[] | select(.feature | not)
  | select((.packages | length) > 1 or .setup.gpu32 == true)
  | "karchy-app-\(.id)\t\((if .source == "aur" then .packages - (.aur // [.packages[0]]) else .packages end
      + (if .setup.gpu32 == true then ["vulkan-driver", "lib32-vulkan-driver", "lib32-opengl-driver"] else [] end)) | join(" "))"' \
  "$catalog" | sort)
check "each depends on its entry's packages" "$packages" "$expected"
check "Lutris brings its parts and a 32-bit driver" \
  "$(grep -P '^karchy-app-lutris\t' <<<"$packages" | cut -f2)" \
  "lutris umu-launcher wine-staging winetricks vulkan-driver lib32-vulkan-driver lib32-opengl-driver"
check "Mission Center brings nethogs" \
  "$(grep -P '^karchy-app-mission-center\t' <<<"$packages" | cut -f2)" "mission-center nethogs"
check "DroidCam's package holds the headers its module is built with, not the AUR's two" \
  "$(grep -P '^karchy-app-droidcam\t' <<<"$packages" | cut -f2)" \
  "android-tools usbmuxd linux-cachyos-headers linux-cachyos-lts-headers"
# An AUR entry without an `aur` list: only its first package is the AUR's.
mkdir "$tmp/aur"
cp "$root/packaging/pkgbuilds/karchy-apps/PKGBUILD" "$tmp/aur/"
echo '{"apps":[{"id":"cam","name":"Cam","packages":["cam-aur","v4l-utils","dkms"],"source":"aur"}]}' >"$tmp/aur/quick-install.json"
check "an AUR app's package holds only what the repositories carry" \
  "$(made "$tmp/aur")" $'karchy-app-cam\tv4l-utils dkms'
check "an app of one package gets none" "$(grep -c '^karchy-app-firefox' <<<"$packages")" 0

# A name that isn't a plain package name never reaches the generated code.
for bad in '{"apps":[{"id":"x","name":"X","packages":["a","b;touch /tmp/owned"],"source":"arch"}]}' \
           '{"apps":[{"id":"X y","name":"X","packages":["a","b"],"source":"arch"}]}' \
           '{"apps":[{"id":"one","name":"One","packages":["a"],"source":"arch"}]}'; do
  mkdir -p "$tmp/bad"
  cp "$root/packaging/pkgbuilds/karchy-apps/PKGBUILD" "$tmp/bad/"
  echo "$bad" >"$tmp/bad/quick-install.json"
  made "$tmp/bad" >/dev/null 2>&1
  check "a bad catalog is refused: ${bad:0:40}" "$?" 1
done

# ---------------------------------------------------------------- the status
mkdir -p "$tmp/bin" "$tmp/karchy/default/karchy"
cp "$catalog" "$tmp/karchy/default/karchy/"
cat >"$tmp/bin/pacman" <<'FAKE'
#!/bin/bash
case $1 in
  -Qq) cat "$FAKE_DB/all" ;;
  -Qeq) cat "$FAKE_DB/explicit" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$tmp/bin/pacman"
export FAKE_DB=$tmp/db KARCHY_PATH=$tmp/karchy
mkdir -p "$FAKE_DB"
installed() { PATH=$tmp/bin:$PATH "$root/bin/karchy-quick-install" status | jq -r '.installed | keys | map(select(IN("winboat", "docker", "pnpm", "node-js", "mpv"))) | join(" ")'; }

printf '%s\n' karchy-app-winboat winboat docker docker-compose mpv >"$FAKE_DB/all"
printf '%s\n' karchy-app-winboat mpv >"$FAKE_DB/explicit"
check "WinBoat is installed, Docker under it is not" "$(installed)" "mpv winboat"
printf '%s\n' karchy-app-winboat mpv docker >"$FAKE_DB/explicit"
check "Docker installed by hand counts" "$(installed)" "docker mpv winboat"
printf '%s\n' karchy-app-node-js nodejs npm pnpm >"$FAKE_DB/all"
printf '%s\n' karchy-app-node-js >"$FAKE_DB/explicit"
check "an app of one package counts whenever it is there" "$(installed)" "node-js pnpm"

# ------------------------------------------- refusals before the password
# The window's install or removal (apply) refuses what needs no root before
# pkexec asks for the password: Docker beside karchy's Podman setup, an app
# that is part of karchy, one another package still needs. The rest goes to
# the helper.
cat >"$tmp/bin/pacman" <<'FAKE'
#!/bin/bash
case $1 in
  -Qq) shift; [[ $1 == -- ]] && shift; grep -xF -- "$1" "$FAKE_DB/all" ;;
  -Qeq) shift; [[ $1 == -- ]] && shift; grep -xF -- "$1" "$FAKE_DB/explicit" ;;
  -Rs)
    [[ " $* " == *" docker "* ]] || exit 0
    echo "error: failed to prepare transaction (could not satisfy dependencies)"
    echo ":: removing docker breaks dependency 'docker' required by karchy-app-winboat"
    exit 1
    ;;
  *) exit 1 ;;
esac
FAKE
cat >"$tmp/bin/pkexec" <<'FAKE'
#!/bin/bash
echo "$*" >>"$FAKE_DB/pkexec"
shift 2
for id in "$@"; do echo "done $id"; done
FAKE
chmod +x "$tmp/bin/pkexec"
export XDG_STATE_HOME=$tmp/state # apply's log, never the real home's
apply() { rm -f "$FAKE_DB/pkexec"; PATH=$tmp/bin:$PATH "$root/bin/karchy-quick-install" apply "$@" 2>/dev/null | grep -E '^(done|failed) ' | paste -sd';' -; }
asked() { cat "$FAKE_DB/pkexec" 2>/dev/null; }
printf '%s\n' podman podman-docker mpv foot docker >"$FAKE_DB/all"
printf '%s\n' mpv foot docker >"$FAKE_DB/explicit"
check "Docker beside Podman: refused before the password" "$(apply install docker)" \
  "failed docker It can't be installed beside Podman (podman-docker). Remove that first"
check "and no password was asked" "$(asked)" ""
check "the log the window points to says why" "$(tail -n 1 "$XDG_STATE_HOME/karchy/quick-install.log")" \
  "docker: It can't be installed beside Podman (podman-docker). Remove that first"
check "Docker refused, mpv still goes to the helper" "$(apply install docker mpv)" \
  "failed docker It can't be installed beside Podman (podman-docker). Remove that first;done mpv"
check "only mpv was asked for" "$(asked)" "/usr/lib/karchy/app-packages install mpv"
check "a part of karchy: refused before the password" "$(apply remove foot)" "failed foot It is part of karchy and can't be removed"
check "and no password was asked" "$(asked)" ""
check "still needed: refused before the password, naming the app" "$(apply remove docker)" \
  "failed docker WinBoat still needs it; nothing was changed"
check "and no password was asked" "$(asked)" ""
check "the command refuses Docker as well, before sudo" \
  "$(PATH=$tmp/bin:$PATH "$root/bin/karchy-quick-install" install docker 2>&1)" \
  "Docker can't be installed beside Podman (podman-docker). Remove that first. Nothing was changed."

echo "app-packages-rule: $pass passed, $failures failed"
((failures == 0))
