#!/bin/bash
# packaging/container/run in a git worktree: git inside sees the same files
# and tags as in a plain checkout (what packaging/build packages and
# versions by), the repository the worktree belongs to is read-only inside,
# and a plain checkout gets no extra mount.
#
# Usage: tests/build-container-worktree.sh
# Needs podman (rootless); builds the build image if it doesn't exist yet.
set -uo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/karchy-worktree-test-XXXXXX")
trap 'rm -rf "$tmp"' EXIT

# A made-up repository holding the container tooling, tagged, with a worktree.
main=$tmp/main
mkdir -p "$main/packaging/container"
cp "$root/packaging/container/run" "$root/packaging/container/Containerfile" "$main/packaging/container/"
printf 'out/\nignored\n' >"$main/.gitignore"
{
  git -C "$main" init --quiet --initial-branch=main
  git -C "$main" add .
  git -C "$main" -c user.name=test -c user.email=test@invalid commit --quiet -m one
  git -C "$main" tag v1.0.0
  git -C "$main" -c user.name=test -c user.email=test@invalid commit --quiet --allow-empty -m two
  git -C "$main" worktree add --quiet "$tmp/tree" -b tree
} || { echo "setup failed"; exit 2; }
touch "$tmp/tree/untracked" "$tmp/tree/ignored" "$main/untracked" "$main/ignored"

inside() { "$1/packaging/container/run" -- bash -c "$2" 2>&1; }
files='git ls-files --cached --others --exclude-standard | paste -sd" " -'
describe='git describe --tags --long --match "v[0-9]*"'

for dir in "$main" "$tmp/tree"; do
  name=${dir##*/}
  check "$name: files" "$(inside "$dir" "$files")" "$(git -C "$dir" ls-files --cached --others --exclude-standard | paste -sd' ' -)"
  check "$name: version" "$(inside "$dir" "$describe")" "v1.0.0-1-g$(git -C "$main" rev-parse --short=7 HEAD)"
  check "$name: archive of a ref" "$(inside "$dir" 'git archive HEAD~1 | tar -t | paste -sd" " -')" \
    "$(git -C "$dir" archive HEAD~1 | tar -t | paste -sd' ' -)"
done
check "tree: repository is read-only" "$(inside "$tmp/tree" "touch $main/.git/x 2>/dev/null && echo writable || echo read-only")" read-only
check "main: nothing outside the checkout" "$(inside "$main" "ls -d $tmp/tree 2>/dev/null || echo absent")" absent

echo "build-container-worktree: $pass passed, $failures failed"
((failures == 0))
