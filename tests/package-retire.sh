#!/bin/bash
# karchy-package-retire against a fake pacman: a retired package installed as
# a dependency is planned for removal and removed only once nothing requires
# it; one the user installed explicitly is kept; other orphans are only named.
# Usage: tests/package-retire.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

# The fake system: explicit, dependency and orphan (dependency, unrequired)
# package names, one file each.
mkdir -p "$tmp/karchy/default/karchy" "$tmp/bin"
cat >"$tmp/bin/pacman" <<'FAKE'
#!/bin/bash
db=$FAKE_DB
case $1 in
  -Qeq) grep -qxF -- "$3" "$db/explicit" && echo "$3" ;;
  -Qdq) grep -qxF -- "$3" "$db/deps" && echo "$3" ;;
  -Qtdq) grep -vxFf "$db/optional" "$db/orphans" ;;
  -Qttdq) cat "$db/orphans" ;;
  *) exit 1 ;;
esac
FAKE
chmod +x "$tmp/bin/pacman"
export PACMAN=$tmp/bin/pacman FAKE_DB=$tmp/db KARCHY_PATH=$tmp/karchy
mkdir -p "$FAKE_DB"
retire() { "$root/bin/karchy-package-retire" "$@"; }

# No list at all: nothing to do.
: >"$FAKE_DB/explicit"; : >"$FAKE_DB/deps"; : >"$FAKE_DB/orphans"; : >"$FAKE_DB/optional"
check "no list" "$(retire plan)" ""

cat >"$KARCHY_PATH/default/karchy/retired-packages" <<'LIST'
# 0.2.0
oldtool   # comment after a name
mine
needed
gone
LIST
printf 'mine\nfirefox\n' >"$FAKE_DB/explicit"
printf 'oldtool\nneeded\nlibfoo\n' >"$FAKE_DB/deps"

# Before the upgrade: dependencies are planned for removal, the explicit one
# kept, one not installed ignored.
check "plan" "$(retire plan)" $'keep mine\nremove needed\nremove oldtool'

# After the upgrade: oldtool is an orphan; needed is still required by
# something; libfoo is an orphan not on the list.
# oldtool is also an optional dependency of something: still removable.
printf 'oldtool\nlibfoo\n' >"$FAKE_DB/orphans"
echo oldtool >"$FAKE_DB/optional"
check "removable" "$(retire removable)" "oldtool"
check "other orphans" "$(retire orphans)" "libfoo"

# An explicit package never reaches removable: pacman -Qtdq lists only
# dependencies, and a stray orphan entry for it still can't be planned.
check "explicit never planned" "$(retire plan | grep -c 'remove mine')" "0"

check "usage" "$(retire bogus 2>&1 >/dev/null; echo $?)" $'Usage: karchy-package-retire plan | removable | orphans\n2'

echo "package-retire: $pass passed, $failures failed"
((failures == 0))
