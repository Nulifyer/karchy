#!/bin/bash
# Quick install's root helper: what it turns away. Needs karchy's catalog in
# /usr/share/karchy (a karchy machine or test VM).
# Usage: tests/app-packages.sh [helper]   (default /usr/lib/karchy/app-packages)
# As a user: a malformed request exits 64, an id that isn't a repository app
# of the list 65, and a good request only fails for not being root (77): the
# request is judged first. It never sends a good request as root.
helper=${1:-/usr/lib/karchy/app-packages}
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }
expect() {
  local name=$1 want=$2 code=0 out
  shift 2
  out=$("$helper" "$@" 2>/dev/null) || code=$?
  if ((code == want)) && [[ -z $out ]]; then ok "$name"; else bad "$name: exit $code (want $want), stdout [$out]"; fi
}

catalog=/usr/share/karchy/default/karchy/quick-install.json
[[ -f $catalog ]] || { echo "no catalog at $catalog: run this on a karchy machine"; exit 2; }
repo_id=$(jq -r '[.apps[] | select(.source == "arch" and (.feature | not))][0].id' "$catalog")
aur_id=$(jq -r '[.apps[] | select(.source == "aur")][0].id' "$catalog")
feature_id=$(jq -r '[.apps[] | select(.feature)][0].id' "$catalog")

expect "no request" 64
expect "a verb alone" 64 install
expect "an unknown verb" 64 upgrade "$repo_id"
expect "a package option as an id" 64 install --overwrite
expect "a path as an id" 64 install /etc/passwd
expect "a path through an id" 64 install ../x
expect "an id in capitals" 64 install Firefox
expect "an id with a space" 64 install "fire fox"
expect "an id with shell text" 64 install 'x;rm'
mapfile -t many < <(printf 'a%d\n' $(seq 1 65))
expect "65 ids" 64 install "${many[@]}"
expect "an unknown id" 65 install no-such-app
expect "an AUR id ($aur_id)" 65 install "$aur_id"
expect "a feature id ($feature_id)" 65 install "$feature_id"
expect "a good id after a bad one" 65 install no-such-app "$repo_id"
if ((EUID != 0)); then
  expect "a good request, not as root ($repo_id)" 77 install "$repo_id"
  expect "a good removal, not as root ($repo_id)" 77 remove "$repo_id"
fi
((fails == 0)) && echo "app-packages: all refused as expected"
exit "$fails"
