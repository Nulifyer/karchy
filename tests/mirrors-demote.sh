#!/bin/bash
# karchy-mirrors-demote: which mirrors it takes from pacman's output, how it
# reorders a mirror list in place, and when it says there was nothing to do.
# Usage: tests/mirrors-demote.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tool=$root/bin/karchy-mirrors-demote
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

lists=$tmp/etc/pacman.d
mkdir -p "$lists"
fresh() {
  # shellcheck disable=SC2016  # pacman's variables, written literally
  printf '%s\n' '## CDN' 'Server = https://cdn77.cachyos.org/repo/$arch/$repo' '# Server = https://off.example/repo' \
    'Server = https://us.cachyos.org/repo/$arch/$repo' 'Server = https://good.example/cachy/$arch/$repo' \
    'Server = http://10.0.2.2:8093/b/$repo' >"$lists/cachyos-mirrorlist"
  printf '%s\n' 'Server = https://geo.example/$repo/os/$arch' >"$lists/mirrorlist"
  printf '%s\n' 'Server = https://us.cachyos.org/karchy' >"$lists/karchy-server"
}
servers() { sed -n 's|^Server = [a-z]*://\([^/]*\)/.*|\1|p' "$lists/$1" | tr '\n' ' '; }

# The failure that started this: the package 404s on one mirror, the next has
# it but not its signature, and pacman stops there.
out="error: failed retrieving file 'glibc-2.44-3-x86_64_v3.pkg.tar.zst' from cdn77.cachyos.org : The requested URL returned error: 404
error: failed retrieving file 'glibc-2.44-3-x86_64_v3.pkg.tar.zst.sig' from us.cachyos.org : The requested URL returned error: 404
warning: failed to retrieve some files
error: failed to commit transaction (failed to retrieve some files)"
fresh
said=$("$tool" --in-place --root "$tmp" <<<"$out" 2>&1); code=$?
check "both mirrors go last: exit" "$code" 0
check "both mirrors go last: order" "$(servers cachyos-mirrorlist)" "good.example 10.0.2.2:8093 cdn77.cachyos.org us.cachyos.org "
check "comments stay where they are" "$(grep -c '^#' "$lists/cachyos-mirrorlist")" 2
check "it names what it moved" "$said" $'demoted cdn77.cachyos.org\ndemoted us.cachyos.org'
check "a list without those mirrors is left alone" "$(servers mirrorlist)" "geo.example "
check "only mirror lists are touched" "$(servers karchy-server)" "us.cachyos.org "

# The same failure again: they are last already, so there is nothing to try.
"$tool" --in-place --root "$tmp" <<<"$out" >/dev/null 2>&1; check "already last: exit 1" "$?" 1

# A host with a port, and a timeout instead of a 404.
fresh
"$tool" --in-place --root "$tmp" <<<"error: failed retrieving file 'cachyos.db' from 10.0.2.2:8093 : Operation too slow. Less than 1 bytes/sec" >/dev/null 2>&1
check "host with a port" "$(servers cachyos-mirrorlist)" "cdn77.cachyos.org us.cachyos.org good.example 10.0.2.2:8093 "

# Failures that name no mirror, or none of ours: nothing moves.
fresh
before=$(cat "$lists"/*)
"$tool" --in-place --root "$tmp" <<<"error: failed to prepare transaction (conflicting dependencies)" >/dev/null 2>&1; check "no mirror named: exit 1" "$?" 1
"$tool" --in-place --root "$tmp" <<<"error: failed retrieving file 'x' from elsewhere.example : 404" >/dev/null 2>&1; check "an unknown mirror: exit 1" "$?" 1
"$tool" --in-place --root "$tmp" </dev/null >/dev/null 2>&1; check "no output: exit 1" "$?" 1
check "nothing was rewritten" "$(cat "$lists"/*)" "$before"

# A mirror name can't reach the lists as anything but a name to compare.
"$tool" --in-place --root "$tmp" <<<"error: failed retrieving file 'x' from \$(touch\${IFS}$tmp/pwned) : 404" >/dev/null 2>&1
check "a hostile mirror name runs nothing" "$([[ -e $tmp/pwned ]] && echo ran || echo no)" "no"

"$tool" >/dev/null 2>&1; check "no mode: usage" "$?" 2
"$tool" --wipe >/dev/null 2>&1; check "unknown option: usage" "$?" 2

if ((failures == 0)); then echo "mirrors-demote: $pass passed, 0 failed"; else echo "mirrors-demote: $pass passed, $failures failed"; exit 1; fi
