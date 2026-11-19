#!/bin/bash
# karchy-migrate: baseline marks every shipped migration done without running
# it; run runs the rest in name order, keeps going past a failure, and leaves
# a failed one pending with its log. Usage: tests/migrations.sh [repo root]
# shellcheck disable=SC2016,SC2012  # migration bodies are written literally; test file names are plain
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

export KARCHY_PATH=$tmp/karchy XDG_STATE_HOME=$tmp/state HOME=$tmp/home
mkdir -p "$KARCHY_PATH/migrations" "$HOME"
m=$KARCHY_PATH/migrations
done_dir=$XDG_STATE_HOME/karchy/migrations
migrate() { "$root/bin/karchy-migrate" "$@"; }

# No migrations folder at all: nothing to do, success.
rmdir "$m"
out=$(migrate run); check "run without migrations" "$?:$out" "0:"
mkdir -p "$m"

# A fresh user: baseline marks the shipped ones, which then never run.
echo 'echo ran >>"$HOME/old"' >"$m/1700000000-old.sh"
migrate baseline
check "baseline marks" "$(ls "$done_dir")" "1700000000-old.sh"
out=$(migrate run); check "baseline then run" "$?:$out" "0:"
check "baselined migration did not run" "$(cat "$HOME/old" 2>/dev/null)" ""

# Later migrations: run in name order; a failing one doesn't stop the rest.
echo 'echo a >>"$HOME/order"' >"$m/1800000000-a.sh"
printf 'echo before-failure\nfalse\necho after\n' >"$m/1800000100-broken.sh"
echo 'set -e; false; echo never' >"$m/1800000150-strict.sh"
echo 'echo c >>"$HOME/order"' >"$m/1800000200-c.sh"
out=$(migrate run); rc=$?
check "run exit code with a failure" "$rc" "1"
# Migrations run with errexit: a failing command fails one even when its
# last command succeeds.
check "run report" "$out" $'done 1800000000-a.sh\nfailed 1800000100-broken.sh\nfailed 1800000150-strict.sh\ndone 1800000200-c.sh'
check "broken stopped at the failure" "$(cat "$done_dir/1800000100-broken.sh.log")" "before-failure"
check "order" "$(tr '\n' ' ' <"$HOME/order")" "a c "
check "failed not marked" "$([[ -e $done_dir/1800000150-strict.sh ]] && echo marked || echo pending)" "pending"
check "failed log kept" "$([[ -f $done_dir/1800000150-strict.sh.log ]] && echo yes)" "yes"
check "done log removed" "$([[ -e $done_dir/1800000000-a.sh.log ]] && echo kept || echo gone)" "gone"

# The next run tries only the failed one again; once fixed it is marked.
echo 'echo fixed >>"$HOME/fixed"' >"$m/1800000150-strict.sh"
out=$(migrate run); check "retry" "$?:$out" $'1:failed 1800000100-broken.sh\ndone 1800000150-strict.sh'
check "status" "$(migrate status | grep -c '^done ')" "4"
echo 'echo fixed' >"$m/1800000100-broken.sh"
out=$(migrate run); check "retry fixed" "$?:$out" "0:done 1800000100-broken.sh"
check "ran once each" "$(tr '\n' ' ' <"$HOME/order")" "a c "
check "status" "$(migrate status | grep -c '^done ')" "5"

# The package's /etc/skel marks: one per shipped migration.
pkg=$tmp/pkg
mkdir -p "$pkg"
(
  cd "$tmp/karchy" || exit 1
  pkgdir=$pkg
  install -d "$pkgdir/etc/skel/.local/state/karchy/migrations"
  for migration in migrations/*.sh; do
    if [[ -f $migration ]]; then : >"$pkgdir/etc/skel/.local/state/karchy/migrations/${migration##*/}"; fi
  done
)
check "skel marks" "$(ls "$pkg/etc/skel/.local/state/karchy/migrations" | wc -l)" "5"
grep -q 'etc/skel/.local/state/karchy/migrations' "$root/packaging/pkgbuilds/karchy/PKGBUILD"
check "PKGBUILD writes skel marks" "$?" "0"
# The baseline is in the one program that sets up any new account's home
# (D-139), which the installer runs for the first user.
grep -q 'karchy-migrate baseline' "$root/system/users/user-setup" && grep -q 'user-setup' "$root/install/setup.sh"
check "installer baselines the first user" "$?" "0"

echo "migrations: $pass passed, $failures failed"
((failures == 0))
