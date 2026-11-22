#!/bin/bash
# Settings › Users' root helper making real changes: accounts added, changed
# and removed with shadow's own tools, the keyring keys (made only while one
# person uses the computer, never kept past their account, D-142), and the
# automatic login it turns off. It runs as root and changes /etc/passwd, /home and
# /etc/greetd, so it only runs in a throwaway container:
#   podman run --rm --user 0 -v "$PWD":/repo:ro <an Arch image with jq> bash /repo/tests/users-accounts.sh
# (karchy's build image has what it needs: packaging/container/run builds it;
# `podman images` names it localhost/karchy-build:<hash>.) It refuses to
# start anywhere else. No systemd runs there, so nobody counts as signed in,
# and the disk doesn't count as encrypted; tests/users-settings.sh covers
# the rules that depend on those, and a VM the logins themselves.
# shellcheck disable=SC2016 # the quoted commands are for the inner shells
set -u
if ((EUID != 0)) || [[ ! -e /run/.containerenv && ! -e /.dockerenv ]]; then
  echo "users-accounts: run this as root in a throwaway container (see the top of this file)"
  exit 2
fi
cd /
H=${1:-/repo/system/users/users-settings}
KEY_MAKER=${H%/users/users-settings}/keyring/keyring-key
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }
t() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
[[ -x /usr/bin/fish ]] || ln -s bash /usr/bin/fish
install -Dm755 "$KEY_MAKER" /usr/lib/karchy/keyring-key
# The image's own account would count as a person.
while IFS=: read -r account _ number _; do
  ((number >= 1000 && number <= 59999)) && userdel --remove "$account" >/dev/null 2>&1
done </etc/passwd
mkdir -p /etc/greetd
printf '%s\n' '# top' '[terminal]' 'vt = 1' '' '[initial_session]' 'command = "/usr/lib/karchy/session"' 'user = "ada"' '' '[default_session]' 'command = "/usr/lib/karchy/greeter"' 'user = "greeter"' >/etc/greetd/config.toml

out=$(printf 'pw one\n' | $H add ada admin "Ada Example" 2>&1); rc=$?
t "add ada (administrator): exit 0, nothing printed" test "$rc:$out" = "0:"
uid=$(id -u ada)
t "ada is in wheel" bash -c 'id -nG ada | grep -qw wheel'
t "ada's shell is fish, full name set" bash -c 'getent passwd ada | grep -q ":Ada Example:/home/ada:/usr/bin/fish$"'
t "ada's home is 0700 and hers" test "$(stat -c '%a %U' /home/ada)" = "700 ada"
t "ada has a password hash" bash -c 'grep "^ada:" /etc/shadow | cut -d: -f2 | grep -q "^\\$"'
t "ada has a keyring key, root only" test "$(stat -c '%a %U %s' "/etc/credstore/karchy.keyring.$uid")" = "600 root 44"
t "one person: automatic login untouched" grep -q '^\[initial_session\]' /etc/greetd/config.toml
t "the password is in no process list or file" bash -c '! grep -rIl "pw one" /etc /run /tmp /home 2>/dev/null | grep .'

out=$(printf 'pw:two with spaces \n' | $H add sam standard 2>&1); rc=$?
t "add sam (standard): exit 0 and autologin=off" test "$rc:$out" = "0:autologin=off"
t "the config lost [initial_session]" bash -c '! grep -q initial_session /etc/greetd/config.toml && grep -q "^\[default_session\]" /etc/greetd/config.toml && grep -q "^# top" /etc/greetd/config.toml'
t "sam is not in wheel" bash -c '! id -nG sam | grep -qw wheel'
suid=$(id -u sam)
# A second person: the login screen is in force, keyrings open with the
# login password, and no key is made any more. Ada's stays until her next
# login gives her keyring the password (tests/keyring-login.sh).
t "the install is marked: keyrings open with the login password" test -f /etc/karchy/keyring-login-password
t "passwd changes the keyring's password too" test "$(grep -c pam_oo7 /etc/pam.d/passwd)" = 1
t "a login at the login screen goes through karchy's PAM service" bash -c 'grep -qxF "service = \"karchy-login\"" /etc/greetd/config.toml && grep -qxF "service = \"greetd\"" /etc/greetd/config.toml'
t "sam has no key" bash -c "! test -e /etc/credstore/karchy.keyring.$suid && ! test -e /etc/credstore/karchy.keyring.$suid.next"
t "ada's key is still there" test -s "/etc/credstore/karchy.keyring.$uid"
t "sam can't read ada's home" bash -c '! runuser -u sam -- ls /home/ada >/dev/null 2>&1'
t "sam can't read the keys" bash -c '! runuser -u sam -- cat /etc/credstore/karchy.keyring.'"$uid"' >/dev/null 2>&1'

out=$(printf 'x\n' | $H add pat standard "a:b" 2>&1); t "a bad full name adds nobody ($?)" bash -c '! getent passwd pat >/dev/null'
out=$(: | $H add pat standard 2>&1); rc=$?
t "no password: refused (65), nobody added" bash -c "test $rc = 65 && ! getent passwd pat >/dev/null"

$H full-name sam "Sam Q. Example" 2>&1; t "full name changed" bash -c 'getent passwd sam | cut -d: -f5 | grep -qx "Sam Q. Example"'
$H full-name sam 2>&1; t "full name cleared" bash -c 'test -z "$(getent passwd sam | cut -d: -f5)"'
$H role sam admin 2>&1; t "sam made an administrator" bash -c 'id -nG sam | grep -qw wheel'
PKEXEC_UID=$suid $H role ada standard 2>&1; t "with two administrators one takes the other's role" bash -c '! id -nG ada | grep -qw wheel'
out=$(PKEXEC_UID=$uid $H role sam standard 2>&1); rc=$?
t "the last administrator keeps the role (65)" bash -c "test $rc = 65 && id -nG sam | grep -qw wheel"
$H role ada admin; $H role sam standard; t "roles put back" bash -c 'id -nG ada | grep -qw wheel && ! id -nG sam | grep -qw wheel'

before=$(grep '^sam:' /etc/shadow | cut -d: -f2)
out=$(printf 'new pass\n' | PKEXEC_UID=$uid $H reset-password sam 2>&1); rc=$?
t "reset sam's password: exit 0, nothing printed" test "$rc:$out" = "0:"
t "sam's hash changed" bash -c "test \"\$(grep '^sam:' /etc/shadow | cut -d: -f2)\" != '$before'"
out=$(printf 'x\n' | PKEXEC_UID=$uid $H reset-password ada 2>&1); t "not your own here ($?)" grep -q Security <<<"$out"

out=$(PKEXEC_UID=$suid $H remove ada 2>&1); rc=$?
t "the only administrator isn't removed (65)" bash -c "test $rc = 65 && getent passwd ada >/dev/null"
out=$(PKEXEC_UID=$uid $H remove ada 2>&1); rc=$?
t "nor by herself (65)" bash -c "test $rc = 65 && test -d /home/ada"
out=$(PKEXEC_UID=$uid $H remove sam keep-home 2>&1); rc=$?
t "there is no keeping the home: the old form is refused (64)" bash -c "test $rc = 64 && getent passwd sam >/dev/null && test -d /home/sam"

runuser -u sam -- bash -c 'echo secret > /home/sam/note'
# (A key sam still had, had he been here before the second person came.)
echo "a-key-as-keyring-key-makes-them-0000000000000=" >"/etc/credstore/karchy.keyring.$suid"
cp "/etc/credstore/karchy.keyring.$suid" "/etc/credstore/karchy.keyring.$suid.next"
out=$(PKEXEC_UID=$uid $H remove sam 2>&1); rc=$?
t "remove sam: exit 0 [$out]" test "$rc" = 0
t "sam is gone" bash -c '! getent passwd sam >/dev/null && ! grep -q "^sam:" /etc/shadow'
t "the home and its file are gone with the account" bash -c '! test -e /home/sam'
t "no key outlives the account, and none is set aside" bash -c "! ls /etc/credstore | grep -v '^karchy.keyring.$uid\$' | grep ."
printf 'x\n' | $H add pat standard >/dev/null 2>&1
t "pat got sam's old number, with nothing of sam's to find" bash -c "test \$(id -u pat) = $suid && ! test -e /home/sam"
t "pat got no key" bash -c "! test -e /etc/credstore/karchy.keyring.$suid"
mkdir /home/sam
out=$(printf 'x\n' | $H add sam standard 2>&1); rc=$?
t "a name whose home folder is already there is refused (65)" bash -c "test $rc = 65 && grep -q 'already there' <<<'$out'"
rmdir /home/sam
out=$(PKEXEC_UID=$uid $H remove pat 2>&1); rc=$?
t "remove pat: exit 0 [$out]" test "$rc" = 0
t "pat and the home are gone" bash -c "! getent passwd pat >/dev/null && ! test -e /home/pat && ! test -e /etc/credstore/karchy.keyring.$suid"
out=$(PKEXEC_UID=$suid $H remove ada 2>&1); rc=$?
t "the only account stays (65)" bash -c "test $rc = 65"

# A step that fails takes the half-made account away again.
printf '#!/bin/bash\nexit 1\n' >/usr/lib/karchy/keyring-key
out=$(printf 'x\n' | $H add kim standard 2>&1); rc=$?
t "a failed step: exit 1 and a reason [$out]" bash -c "test $rc = 1 && grep -q \"Couldn't add kim\" <<<\"$out\""
t "and no kim, no home" bash -c '! getent passwd kim >/dev/null && ! test -e /home/kim'
install -Dm755 "$KEY_MAKER" /usr/lib/karchy/keyring-key

# With the mark (it is there since sam was added): no key is made.
printf 'x\n' | $H add lee standard >/dev/null 2>&1
t "with the login-password mark, no key for lee" bash -c "getent passwd lee >/dev/null && ! test -e /etc/credstore/karchy.keyring.\$(id -u lee)"
out=$($H autologin on 2>&1); rc=$?
t "automatic login on is refused here ($rc: $out)" test "$rc" = 65
out=$($H autologin off 2>&1); rc=$?
t "automatic login off again: exit 0, and one oo7 line in passwd's file" bash -c "test '$rc:$out' = '0:' && test \$(grep -c pam_oo7 /etc/pam.d/passwd) = 1"
t "status lists the two who are left" test "$($H status | jq -c '[.users[].name]')" = '["ada","lee"]'
((fails == 0)) && echo "users-accounts: all as expected"
exit "$fails"
