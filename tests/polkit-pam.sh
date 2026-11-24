#!/bin/bash
# /usr/lib/karchy/polkit-pam (D-163) against a made-up root: no file, polkit's
# stock stack, fingerprint and FIDO2 lines above it, a file of someone's own,
# and a second run. Then karchy-polkit-auth's pam_unix line.
# Usage: tests/polkit-pam.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }
helper=$root/system/pam.d/polkit-pam
file=$tmp/etc/pam.d/polkit-1
mkdir -p "$tmp/etc/pam.d"
auth() { grep -E '^[[:space:]]*auth' "$file" | tr -s ' \t' ' '; }

# No file: polkit's stack, its auth lines from karchy's file.
"$helper" --root "$tmp"; check "new: exit" "$?" 0
check "new: auth" "$(auth)" "auth include karchy-polkit-auth"
check "new: rest" "$(grep -Ec '^(account|password|session) +include +system-auth$' "$file")" 3
check "new: mode" "$(stat -c %a "$file")" 644
before=$(cat "$file")
"$helper" --root "$tmp"; check "again: exit" "$?" 0
check "again: unchanged" "$(cat "$file")" "$before"

# The stock stack, and fingerprint and FIDO2 lines added above it before.
printf '%s\n' 'auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/karchy-hw-laptop-closed' \
  'auth      sufficient pam_fprintd.so' 'auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2' \
  'auth      include system-auth' '' 'account   include system-auth' 'password  include system-auth' \
  'session   include system-auth' >"$file"
"$helper" --root "$tmp"; check "added lines: exit" "$?" 0
check "added lines: auth" "$(auth)" $'auth [success=1 default=ignore] pam_exec.so quiet /usr/bin/karchy-hw-laptop-closed\nauth sufficient pam_fprintd.so\nauth sufficient pam_u2f.so cue authfile=/etc/fido2/fido2\nauth include karchy-polkit-auth'
check "added lines: rest" "$(grep -c 'include system-auth' "$file")" 3

# Someone's own stack: left alone, said so, not a failure.
printf 'auth required pam_unix.so\naccount include system-auth\n' >"$file"
out=$("$helper" --root "$tmp" 2>&1); check "own: exit" "$?" 0
check "own: unchanged" "$(cat "$file")" $'auth required pam_unix.so\naccount include system-auth'
check "own: says so" "$([[ $out == *"left as it is"* ]] && echo yes)" yes

# The password check: only a prompt that got no answer skips the count.
line=$(grep -E '^auth .*pam_unix\.so' "$root/system/pam.d/karchy-polkit-auth" | tr -s ' ')
check "pam_unix line" "$line" "auth [success=1 authtok_err=die default=bad] pam_unix.so try_first_pass nullok"
check "authfail follows" "$(grep -A1 pam_unix.so "$root/system/pam.d/karchy-polkit-auth" | tail -1 | tr -s ' ')" "auth [default=die] pam_faillock.so authfail"

echo "polkit-pam: $pass passed, $failures failed"
((failures == 0))
