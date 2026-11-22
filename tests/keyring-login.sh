#!/bin/bash
# The login keyring follows how its owner gets in (D-142): the root hook a
# login at karchy's login screen runs (system/keyring/keyring-login), the
# part of it that runs as the person (keyring-rekey), the key maker, and what
# Settings › Users' root helper decides about automatic login and the keyring.
# Usage: tests/keyring-login.sh [repo root]
#
# Runs as an ordinary user and changes nothing on the machine: everything
# happens in a user namespace where this user plays root, with a made-up /etc
# and /run, the checkout's scripts in /usr/lib/karchy, and made-up programs
# over the ones that need a real root or a real keyring:
#   unix_chkpwd   each person's password is a file
#   systemctl     says whether a person's user manager runs
#   pgrep         says whether their keyring daemon runs
#   setpriv, chown, dbus-run-session
#                 run the command as it is (one user here plays everyone)
#   findmnt, lsblk  the disk is encrypted or not, as the test says
#   oo7-cli       a keyring is a text file: its secret, then one line an
#                 entry. It asks for the secrets of change-secret on the
#                 terminal, as the real one does, so script(1) and the pipes
#                 in keyring-rekey are the real ones
#   logger        writes to a file, not to this machine's journal
# What the real oo7-cli, PAM and greetd do is tested in a VM (D-142's
# evidence). Skipped where the kernel doesn't allow such a namespace.
# shellcheck disable=SC2016 # the quoted scripts are for the inner shells
set -u
root=$(realpath "${1:-.}")
for needed in jq script unshare; do
  command -v "$needed" >/dev/null || { echo "keyring-login: $needed is needed"; exit 2; }
done

sandbox=$(mktemp -d)
trap 'chmod -R u+rwx "$sandbox" 2>/dev/null; rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox"/{etc.up,etc.work,bin.up,bin.work,lib.up/karchy/keyring-rekey-services,lib.work}

install -m755 "$root/system/keyring/keyring-login" "$root/system/keyring/keyring-rekey" \
  "$root/system/keyring/keyring-key" "$root/system/users/users-settings" "$sandbox/lib.up/karchy/"
install -m644 "$root/system/keyring/rekey-bus.conf" "$sandbox/lib.up/karchy/keyring-rekey-bus.conf"

stub() { cat >"$sandbox/bin.up/$1" && chmod 755 "$sandbox/bin.up/$1"; }
stub unix_chkpwd <<'STUB'
#!/bin/bash
IFS= read -r -d '' typed
[[ -f /run/t/password.$1 && $typed == "$(</run/t/password.$1)" ]] || exit 7
STUB
stub systemctl <<'STUB'
#!/bin/bash
# systemctl show -P ActiveState user@<uid>.service
if [[ -e /run/t/session-runs ]]; then echo active; else echo inactive; fi
STUB
stub pgrep <<'STUB'
#!/bin/bash
[[ -e /run/t/daemon-runs ]]
STUB
stub setpriv <<'STUB'
#!/bin/bash
while (($#)) && [[ $1 != -- ]]; do shift; done
shift
exec "$@"
STUB
stub dbus-run-session <<'STUB'
#!/bin/bash
[[ ${1:-} == --config-file=/usr/lib/karchy/keyring-rekey-bus.conf && -f ${1#--config-file=} && ${2:-} == -- ]] || exit 127
shift 2
[[ ! -e /run/t/no-bus ]] || exit 127
exec env KARCHY_TEST_BUS=1 "$@"
STUB
stub chown <<'STUB'
#!/bin/bash
exit 0
STUB
stub logger <<'STUB'
#!/bin/bash
echo "${*: -1}" >>/run/t/log
STUB
stub loginctl <<'STUB'
#!/bin/bash
exit 1
STUB
stub findmnt <<'STUB'
#!/bin/bash
echo /dev/mapper/root
STUB
stub lsblk <<'STUB'
#!/bin/bash
if [[ -e /run/t/plain-disk ]]; then echo btrfs; else printf 'btrfs\ncrypto_LUKS\n'; fi
STUB
stub oo7-cli <<'STUB'
#!/bin/bash
# A keyring is a text file: its secret, then one line an entry.
printf '%s\n' "$*" >>/run/t/oo7-argv
# The real one asks the bus for a keyring service first.
[[ -n ${KARCHY_TEST_BUS:-} ]] || { echo "Error: zbus error" >&2; exit 1; }
# As 0.7.3 does: the command comes first, its options after it.
case ${1:-} in
  list | change-secret) ;;
  *) echo "error: unexpected argument '${1:-}' found" >&2; exit 2 ;;
esac
file="" from_stdin=false command=""
while (($#)); do
  case $1 in
    --keyring) file=$2; shift 2 ;;
    --secret) [[ $2 == - ]] && from_stdin=true; shift 2 ;;
    list | change-secret) command=$1; shift ;;
    *) shift ;;
  esac
done
have=$(head -n 1 "$file") || exit 1
case $command in
  list)
    $from_stdin || exit 1
    IFS= read -r given
    if [[ $given == "$have" ]]; then tail -n +2 "$file" | jq -Rn '[inputs]'; else echo '[]'; fi
    ;;
  change-secret)
    [[ -t 0 ]] || { echo "Can't read secret" >&2; exit 1; }
    IFS= read -rs -p "Keyring Secret: " old </dev/tty; echo
    IFS= read -rs -p "Type the new secret: " new </dev/tty; echo
    [[ ! -e /run/t/change-fails ]] || exit 1
    [[ ! -e /run/t/change-hangs ]] || { touch /run/t/hung; exec -a karchy-test-hung sleep 600; }
    [[ ! -e /run/t/change-lies ]] || exit 0
    [[ $old == "$have" ]] || { echo "Error: wrong secret" >&2; exit 1; }
    { printf '%s\n' "$new"; tail -n +2 "$file"; } >"$file.new" && mv "$file.new" "$file"
    ;;
  *) exit 1 ;;
esac
STUB

inside='
  sandbox=$1; shift
  mount -t overlay overlay -o "lowerdir=/etc,upperdir=$sandbox/etc.up,workdir=$sandbox/etc.work" /etc &&
    mount -t overlay overlay -o "lowerdir=/usr/bin,upperdir=$sandbox/bin.up,workdir=$sandbox/bin.work" /usr/bin &&
    mount -t overlay overlay -o "lowerdir=/usr/lib,upperdir=$sandbox/lib.up,workdir=$sandbox/lib.work" /usr/lib &&
    mount -t tmpfs tmpfs /run || exit 90
  for made in /etc/greetd /etc/karchy /etc/credstore /etc/pam.d /etc/environment.d; do
    mkdir -p "$made" && mount -t tmpfs tmpfs "$made" || exit 90
  done
  mkdir -p /run/t /run/home
  exec bash "$@"'
if ! unshare -rm bash -c "$inside" _ "$sandbox" -c true 2>/dev/null; then
  echo "skip keyring-login (no user namespace with an overlay here)"
  exit 0
fi

cat >"$sandbox/cases" <<'CASES'
set -u
hook=/usr/lib/karchy/keyring-login
rekey=/usr/lib/karchy/keyring-rekey
maker=/usr/lib/karchy/keyring-key
users=/usr/lib/karchy/users-settings
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }
t() { local name=$1; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }

MARK=/etc/karchy/keyring-login-password
WANTED=/etc/karchy/autologin-pending
store=/etc/credstore
key=$store/karchy.keyring.1100
KEY_A="AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
KEY_B="BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB="

# One user plays everyone: the person logging in is whoever /run/home/now
# points at, which is this "root"'s home in the made-up passwd file.
accounts() {
  rm -f /etc/passwd
  {
    echo "root:x:0:0::/run/home/now:/usr/bin/bash"
    echo "greeter:x:960:960::/:/usr/bin/nologin"
    printf '%s\n' "$@"
  } >/etc/passwd
}
ada="ada:x:1100:1100:Ada Example:/home/ada:/usr/bin/fish"
sam="sam:x:1101:1101::/home/sam:/usr/bin/fish"
config() {
  printf '%s\n' "[terminal]" "vt = 1" "" "$@" "[default_session]" 'command = "/usr/lib/karchy/greeter"' 'user = "greeter"' >/etc/greetd/config.toml
}
printf '#%%PAM-1.0\npassword\tinclude\t\tsystem-auth\n' >/etc/pam.d/passwd
rm -f /etc/group; echo "wheel:x:998:ada" >/etc/group
echo "pw ada 1" >/run/t/password.ada
echo "pw sam 1" >/run/t/password.sam

# A fresh start: the keyring of $1 (or none) holding two entries under
# secret $2, and nothing that waits.
fresh() {
  rm -rf /run/home/* /run/t/{session-runs,daemon-runs,no-bus,change-fails,change-lies,change-hangs,hung,plain-disk,log,oo7-argv}
  rm -f "$MARK" "$WANTED" "$store"/* "$store"/.[!.]* /etc/environment.d/*
  mkdir -p /run/home/ada /run/home/sam
  ln -sfn "/run/home/${1:-ada}" /run/home/now
  [[ -z ${2:-} ]] || keyring "${1:-ada}" "$2"
  accounts "$ada"
  config
}
keyring() {
  mkdir -p "/run/home/$1/.local/share/keyrings/v1"
  printf '%s\n' "$2" "brave: saved logins" "code: sign-in" >"/run/home/$1/.local/share/keyrings/v1/login.keyring"
}
kr() { echo "/run/home/${1:-ada}/.local/share/keyrings/v1/login.keyring"; }
secret_of() { head -n 1 "$(kr "${1:-ada}")" 2>/dev/null; }
entries_of() { tail -n +2 "$(kr "${1:-ada}")" 2>/dev/null | wc -l; }
mark() { echo "# mark" >"$MARK"; }
# login <user> <password, or what stands in for it> [PAM_TYPE]: the exit status.
login() {
  local code=0
  ln -sfn "/run/home/$1" /run/home/now
  printf '%s\0' "$2" | PAM_USER=$1 PAM_TYPE=${3:-auth} "$hook" >/run/t/out 2>&1 || code=$?
  [[ ! -s /run/t/out ]] || { bad "the hook printed: $(</run/t/out)"; }
  echo "$code"
}
said() { grep -q -- "$1" /run/t/log 2>/dev/null; }

# ---- the key maker ----
fresh
"$maker" 1100; t "keyring-key: a key for one person, root only" test "$(stat -c '%a %s' "$key")" = "600 44"
first=$(<"$key"); "$maker" 1100; t "keyring-key: made once" test "$(<"$key")" = "$first"
[[ $first =~ ^[A-Za-z0-9+/]{43}=$ ]] && ok "keyring-key: 32 random bytes as text, no line end" || bad "key: $first"
"$maker" 999; t "keyring-key: none for a system account" test ! -e "$store/karchy.keyring.999"
"$maker" 1100 again 2>/dev/null; t "keyring-key: an unknown word is refused" test $? = 1
rm -f "$key"; mark
"$maker" 1100; t "keyring-key: none where keyrings open with the login password" test ! -e "$key"
"$maker" 1100 next; t "keyring-key next: the key a keyring is about to get, whatever the mark" test "$(stat -c '%a %s' "$key.next")" = "600 44"
kept=$(<"$key.next"); "$maker" 1100 next; t "keyring-key next: one that is there is kept" test "$(<"$key.next")" = "$kept"
t "keyring-key next: and the key itself is not made" test ! -e "$key"

# ---- keyring-rekey, as the person ----
fresh ada "$KEY_A"
bus() { env KARCHY_TEST_BUS=1 "$@"; }
bus "$rekey" has; t "rekey has: a keyring (0)" test $? = 0
ln -sfn /run/home/sam /run/home/now; bus "$rekey" has; t "rekey has: none (44)" test $? = 44
mkdir -p /run/home/sam/.local/share/keyrings && : >/run/home/sam/.local/share/keyrings/login.keyring
bus "$rekey" has; t "rekey has: only the old format, can't tell (3)" test $? = 3
ln -sfn /run/home/ada /run/home/now
echo 'XDG_DATA_HOME=/somewhere' >/etc/environment.d/50-data.conf
bus "$rekey" has; t "rekey has: a moved data folder, can't tell (3)" test $? = 3
rm -f /etc/environment.d/50-data.conf
echo "$KEY_A" | bus "$rekey" opens; t "rekey opens: the right secret" test $? = 0
echo "$KEY_B" | bus "$rekey" opens; t "rekey opens: a wrong one" test $? = 1
: | bus "$rekey" opens; t "rekey opens: no secret" test $? = 1
printf '%s\n%s\n' "$KEY_A" "new pass word" | bus "$rekey" change; rc=$?
t "rekey change: exit 0, the new secret, both entries, no copy left" bash -c "test $rc = 0 && test \"$(secret_of)\" = 'new pass word' && test $(entries_of) = 2 && ! ls -A /run/home/ada/.local/share/keyrings/v1 | grep -v '^login.keyring\$' | grep ."
t "rekey change: the keyring is the person's alone (0600)" test "$(stat -c %a "$(kr)")" = 600
printf '%s\n%s\n' "$KEY_A" "another" | bus "$rekey" change; rc=$?
t "rekey change: a wrong old secret changes nothing (1)" bash -c "test $rc = 1 && test \"$(secret_of)\" = 'new pass word'"
printf '%s\n%s\n' "new pass word" $'bad\x03secret' | bus "$rekey" change; rc=$?
t "rekey change: a secret with a control character is refused" bash -c "test $rc = 1 && test \"$(secret_of)\" = 'new pass word'"
printf '%s\n' "new pass word" | bus "$rekey" change; t "rekey change: one secret is not enough" test $? = 1
touch /run/t/change-lies
printf '%s\n%s\n' "new pass word" "$KEY_B" | bus "$rekey" change; rc=$?
t "rekey change: oo7-cli says done but the copy doesn't open: the keyring stays" bash -c "test $rc = 1 && test \"$(secret_of)\" = 'new pass word' && test $(entries_of) = 2"
rm -f /run/t/change-lies
printf '%s\n%s\n' "new pass word" "$KEY_B" | "$rekey" change; rc=$?
t "rekey change: without a bus oo7-cli fails and nothing changes" bash -c "test $rc = 1 && test \"$(secret_of)\" = 'new pass word'"
t "no secret was ever an argument" bash -c "! grep -qF -e '$KEY_A' -e '$KEY_B' -e 'new pass word' -e another /run/t/oo7-argv"
"$rekey" 2>/dev/null; t "rekey: no verb is not a request (64)" test $? = 64

# ---- the hook: what it leaves alone ----
fresh ada "$KEY_A"; echo "$KEY_A" >"$key"
t "automatic login (a key, no mark): the key is in force (0)" test "$(login ada 'pw ada 1')" = 0
t "...and nothing changed" bash -c "test \"$(secret_of)\" = '$KEY_A' && test \"\$(<$key)\" = '$KEY_A' && test ! -e /run/t/log"
rm -f "$key"
t "no mark and no key yet: still the key's turn (one is made at the start)" test "$(login ada 'pw ada 1')" = 0
mark
t "the login password is in force and no key is left: the password (1)" test "$(login ada 'pw ada 1')" = 1
t "a second person who never had a key: the password (1)" test "$(login sam 'pw sam 1')" = 1
t "...and no key was made for them" bash -c "! ls -A $store | grep ."
code=0; PAM_TYPE=auth "$hook" </dev/null >/dev/null 2>&1 || code=$?; t "no user from PAM: 1" test "$code" = 1
t "root is not a person: 1" test "$(login root x)" = 1
code=0; printf 'x\0' | PAM_USER='ada;id' PAM_TYPE=auth "$hook" >/dev/null 2>&1 || code=$?; t "shell text as the user: 1" test "$code" = 1
code=0; printf 'x\0' | PAM_USER='../ada' PAM_TYPE=auth "$hook" >/dev/null 2>&1 || code=$?; t "a path as the user: 1" test "$code" = 1
t "someone PAM knows and the passwd file doesn't: 1" test "$(login pat x)" = 1

# Automatic login in force, and a keyring that has the login password: the
# system went back to a snapshot from before it was turned off.
fresh ada "pw ada 1"; echo "$KEY_A" >"$key"
t "a key in force that no longer opens the keyring, and the password does: the keyring gets the key back (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"$(secret_of)\" = '$KEY_A' && test $(entries_of) = 2 && test \"\$(<$key)\" = '$KEY_A'"
said "has its key again" && ok "...and said so" || bad "log: $(cat /run/t/log 2>/dev/null)"
fresh ada "pw ada 1"; echo "$KEY_A" >"$key"
t "...but not with a wrong password (0)" bash -c "test $(login ada 'guess') = 0 && test \"$(secret_of)\" = 'pw ada 1'"
touch /run/t/session-runs
t "...nor while their session runs (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"$(secret_of)\" = 'pw ada 1'"
fresh ada "something else"; echo "$KEY_A" >"$key"
t "a key in force and a keyring neither it nor the password opens: left alone (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"$(secret_of)\" = 'something else' && test \"\$(<$key)\" = '$KEY_A' && test ! -e /run/t/log"

fresh ada "$KEY_A"; echo "$KEY_A" >"$key"; mark
unchanged() { [[ $(secret_of) == "$KEY_A" && $(<"$key") == "$KEY_A" && $(entries_of) == 2 ]]; }
t "a wrong password: the key stays in force (0)" test "$(login ada 'not it')" = 0
t "...and nothing changed" unchanged
t "no password: 0" test "$(login ada '')" = 0; t "...and nothing changed" unchanged
t "another person's password: 0" test "$(login ada 'pw sam 1')" = 0; t "...and nothing changed" unchanged
t "not an authentication (a session opening): 0" test "$(login ada 'pw ada 1' open_session)" = 0; t "...and nothing changed" unchanged
touch /run/t/session-runs
t "their session is still running: skipped (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
said "still running" && ok "...and said so" || bad "log: $(cat /run/t/log 2>/dev/null)"
rm -f /run/t/session-runs; touch /run/t/daemon-runs
t "a keyring daemon of theirs is running: skipped (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
rm -f /run/t/daemon-runs
(
  exec 9>/run/karchy-keyring-login.1100.lock; flock 9
  t "another login of theirs is in the hook: skipped (0)" test "$(login ada 'pw ada 1')" = 0
)
t "...and nothing changed" unchanged
echo 'XDG_DATA_HOME=/elsewhere' >/etc/environment.d/50-data.conf
t "a moved data folder: the key stays (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
rm -f /etc/environment.d/50-data.conf
touch /run/t/no-bus
t "no bus for oo7-cli: the key stays (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
rm -f /run/t/no-bus; touch /run/t/change-fails
t "oo7-cli fails: the key stays (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
rm -f /run/t/change-fails; touch /run/t/change-lies
t "oo7-cli says done and did nothing: the key stays (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
rm -f /run/t/change-lies
# (This one waits for the hook's time limit for a step, 10 seconds.)
touch /run/t/change-hangs; started=$SECONDS
t "oo7-cli hangs: the login goes on at the time limit, and the key stays (0)" test "$(login ada 'pw ada 1')" = 0; t "...and nothing changed" unchanged
t "...within the limits" test $((SECONDS - started)) -lt 30
t "...and what hung is not left running" bash -c 'test -e /run/t/hung && ! grep -qs "^[k]archy-test-hung" /proc/[0-9]*/cmdline'
rm -f /run/t/change-hangs
echo $'pw\x03ada' >/run/t/password.ada
t "a password with a control character: the key stays (0)" test "$(login ada $'pw\x03ada')" = 0; t "...and nothing changed" unchanged
echo "pw ada 1" >/run/t/password.ada

# ---- to the password ----
t "the next login gives the keyring the password (1)" test "$(login ada 'pw ada 1')" = 1
t "...the keyring opens with the password, with both entries" bash -c "test \"$(secret_of)\" = 'pw ada 1' && test $(entries_of) = 2"
t "...and the key is gone" bash -c "! ls -A $store | grep ."
said "now opens with the login password" && ok "...and said so" || bad "log: $(cat /run/t/log)"
t "no copy of the keyring is left" bash -c "! ls -A /run/home/ada/.local/share/keyrings/v1 | grep -v '^login.keyring\$' | grep ."
t "nothing of the hook's is left in /run" bash -c "! ls -d /run/karchy-keyring.* 2>/dev/null | grep ."
t "a login after that changes nothing (1)" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1'"
t "no secret was ever an argument" bash -c "! grep -qF -e '$KEY_A' -e 'pw ada 1' /run/t/oo7-argv"
t "nor is one in the log" bash -c "! grep -qF -e '$KEY_A' -e 'pw ada 1' /run/t/log"

fresh ada ""; echo "$KEY_A" >"$key"; mark
t "no keyring yet: the key is deleted (1)" bash -c "test $(login ada 'pw ada 1') = 1 && ! test -e $key"
fresh ada "pw ada 1"; echo "$KEY_A" >"$key"; mark
t "a stale key (the keyring opens with the password already): deleted (1)" bash -c "test $(login ada 'pw ada 1') = 1 && ! test -e $key && test \"$(secret_of)\" = 'pw ada 1'"
said "stale key" && ok "...and said so" || bad "log: $(cat /run/t/log)"
fresh ada "$KEY_A"; echo "$KEY_A" >"$key"; mark
cp "$(kr)" "$(dirname "$(kr)")/.login.keyring.rekey"
t "a copy left by an interrupted run: the change is made again (1)" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1' && ! test -e $key && ! test -e $(dirname "$(kr)")/.login.keyring.rekey"
fresh ada "an old password"; echo "$KEY_A" >"$key"; mark
t "neither the key nor the password opens it: nothing is deleted (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test -e $key && test \"$(secret_of)\" = 'an old password'"
fresh ada "$KEY_B"; echo "$KEY_B" >"$key.next"; mark
t "a key left by an interrupted change to automatic login: back to the password (1)" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1' && ! ls -A $store | grep ."
fresh ada "$KEY_A"; echo "not a key" >"$key"; mark
t "a key file that holds no key is not used (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"$(secret_of)\" = '$KEY_A' && test -e $key"

# ---- Settings › Users' helper: the mark, the wish, the config ----
as() { PKEXEC_UID=1100 "$users" "$@"; }
fresh ada "$KEY_A"; echo "$KEY_A" >"$key"; config "[initial_session]" 'command = "/usr/lib/karchy/session"' 'user = "ada"' ""
out=$(as autologin off 2>&1); t "automatic login off: exit 0, nothing printed" test "$?:$out" = "0:"
t "...marks the install, and leaves the key for the next login" bash -c "test -f $MARK && test \"\$(<$key)\" = '$KEY_A'"
t "...passwd changes the keyring too" test "$(grep -c pam_oo7 /etc/pam.d/passwd)" = 1
t "...and the config sends logins through karchy's PAM service, without [initial_session]" bash -c '! grep -q initial_session /etc/greetd/config.toml && grep -qxF "service = \"karchy-login\"" /etc/greetd/config.toml'
t "status: keyrings open with the login password, nothing pending" test "$(as status | jq -c '[.keyringPassword, .autologin.on, .autologin.pending]')" = "[true,false,false]"
out=$(as autologin on 2>&1); t "on again before any login (the key is still there): at once" test "$?:$out" = "0:"
t "...the mark is gone, the key kept, the config logs ada in, nothing waits" bash -c "! test -e $MARK && test \"\$(<$key)\" = '$KEY_A' && grep -qxF 'user = \"ada\"' /etc/greetd/config.toml && ! test -e $WANTED"

as autologin off >/dev/null 2>&1
t "off, and a login: the keyring has the password" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1' && ! test -e $key"
out=$(as autologin on 2>&1); t "on now has to wait for a login: autologin=pending" test "$?:$out" = "0:autologin=pending"
t "...the wish is recorded, the mark stays, the config logs nobody in" bash -c "test \"\$(<$WANTED)\" = ada && test -f $MARK && ! grep -q initial_session /etc/greetd/config.toml"
t "status: pending, and not on" test "$(as status | jq -c '[.autologin.on, .autologin.pending]')" = "[false,true]"
out=$(as autologin on 2>&1); t "on again while it waits: the same" bash -c "test '$out' = autologin=pending && test \"\$(<$WANTED)\" = ada"
out=$("$users" autologin-finish ada 2>&1); t "autologin-finish without a key: refused (65)" bash -c "test $? = 65 && test -f $MARK && ! grep -q initial_session /etc/greetd/config.toml"
out=$(as autologin off 2>&1); t "off takes the wish back" bash -c "test '$?:$out' = '0:' && ! test -e $WANTED && test -f $MARK"
echo "$KEY_A" >"$key"
out=$("$users" autologin-finish ada 2>&1); t "autologin-finish that nobody asked for: refused (65)" bash -c "test $? = 65 && test -f $MARK"
rm -f "$key"
out=$("$users" check autologin-finish sam 2>&1); t "autologin-finish for nobody here: refused (65)" test $? = 65
touch /run/t/plain-disk
out=$(as autologin on 2>&1); t "no automatic login without disk encryption (65)" test $? = 65
rm -f /run/t/plain-disk

# ---- to a key ----
as autologin on >/dev/null 2>&1
t "a wrong password while automatic login waits: the password stays in force (1)" bash -c "test $(login ada 'nope') = 1 && test \"$(secret_of)\" = 'pw ada 1' && ! ls -A $store | grep ."
touch /run/t/session-runs
t "their session still running: it waits (1)" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1' && test -f $WANTED"
rm -f /run/t/session-runs; touch /run/t/change-fails
t "oo7-cli fails: it waits, with the new key kept for the next try (1)" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1' && test -f $WANTED && test -s $key.next && ! test -e $key"
rm -f /run/t/change-fails; made=$(<"$key.next")
t "the next login gives the keyring a key (0)" test "$(login ada 'pw ada 1')" = 0
t "...the key made at the first try, now in the store" bash -c "test \"\$(<$key)\" = '$made' && ! test -e $key.next && test \"\$(stat -c %a $key)\" = 600"
t "...the keyring opens with it, with both entries" bash -c "test \"$(secret_of)\" = '$made' && test $(entries_of) = 2"
t "...the mark and the wish are gone, and the config logs ada in" bash -c "! test -e $MARK && ! test -e $WANTED && grep -qxF 'user = \"ada\"' /etc/greetd/config.toml"
said "automatic login is on from the next start" && ok "...and said so" || bad "log: $(cat /run/t/log)"
t "a login after that: the key is in force and nothing changes (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"$(secret_of)\" = '$made'"
t "no secret was ever an argument, or logged" bash -c "! grep -qF -e '$made' -e 'pw ada 1' /run/t/oo7-argv /run/t/log"

fresh ada "$KEY_B"; mark; echo ada >"$WANTED"; echo "$KEY_B" >"$key.next"
t "interrupted after the keyring took its key: the next login finishes (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"\$(<$key)\" = '$KEY_B' && test \"$(secret_of)\" = '$KEY_B' && ! test -e $MARK && ! test -e $WANTED"
fresh ada "$KEY_B"; mark; echo ada >"$WANTED"; echo "$KEY_B" >"$key"
t "interrupted after the key was put in place: finished, and not turned back (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test \"\$(<$key)\" = '$KEY_B' && test \"$(secret_of)\" = '$KEY_B' && ! test -e $MARK && grep -qxF 'user = \"ada\"' /etc/greetd/config.toml"
fresh ada ""; mark; echo ada >"$WANTED"
t "no keyring yet: a key is made and automatic login turned on (0)" bash -c "test $(login ada 'pw ada 1') = 0 && test -s $key && ! test -e $MARK && ! test -e $WANTED"
fresh ada "pw ada 1"; mark; echo ada >"$WANTED"; accounts "$ada" "$sam"
t "a second person since: the wish is dropped and the password stays (1)" bash -c "test $(login ada 'pw ada 1') = 1 && ! test -e $WANTED && test -f $MARK && test \"$(secret_of)\" = 'pw ada 1' && ! ls -A $store | grep . && ! grep -q initial_session /etc/greetd/config.toml"
fresh ada "pw ada 1"; mark; echo sam >"$WANTED"
t "a wish that names someone who is not a person here changes nothing (1)" bash -c "test $(login ada 'pw ada 1') = 1 && test \"$(secret_of)\" = 'pw ada 1' && ! ls -A $store | grep ."
exit "$fails"
CASES

fails=0
unshare -rm bash -c "$inside" _ "$sandbox" "$sandbox/cases" || fails=1
((fails == 0)) && echo "keyring-login: all as expected"
exit "$fails"
