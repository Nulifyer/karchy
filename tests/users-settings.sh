#!/bin/bash
# Settings › Users' root helper: what it turns away, and what it says about
# this computer. Runs as an ordinary user on any Linux machine with accounts
# in /etc/passwd; it never changes one.
# Usage: tests/users-settings.sh [helper]
#   from a checkout:   tests/users-settings.sh system/users/users-settings
#   on an install:     tests/users-settings.sh            (/usr/lib/karchy)
# A request that is not one it takes exits 64; one it refuses 65, with a
# sentence on stderr and nothing on stdout; a good one fails only for not
# being root (77), since the request is judged before who is asking. `check`
# gives the same judgement and exits 0 for a good request. It never sends a
# good request as root: as root only the refusals are run.
helper=${1:-/usr/lib/karchy/users-settings}
fails=0
scratch=$(mktemp)
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }

# expect <name> <exit> <words stderr must hold, or ""> [arguments...]
expect() {
  local name=$1 want=$2 words=$3 code=0 out err
  shift 3
  out=$("$helper" "$@" 2>"$scratch" </dev/null) || code=$?
  err=$(<"$scratch")
  if ((code == want)) && [[ -z $out ]] && [[ -z $words || $err == *"$words"* ]]; then ok "$name"
  else bad "$name: exit $code (want $want), stdout [$out], stderr [$err]"; fi
}

[[ -x $helper ]] || { echo "no helper at $helper"; exit 2; }
me=$(id -un)
free=karchytest$$
free=${free:0:32}

# Not a request.
expect "no request" 64 usage:
expect "a verb alone" 64 usage: add
expect "an unknown verb" 64 usage: delete "$me" keep-home
expect "status with more" 64 usage: status now
expect "check alone" 64 usage: check
expect "too many arguments" 64 usage: add "$free" standard "A Name" more
expect "a role that isn't one" 64 usage: add "$free" owner
expect "a role that isn't one, for role" 64 usage: role "$me" root
expect "a home choice that isn't one" 64 usage: remove "$me" shred
expect "remove without a home choice" 64 usage: remove "$me"
expect "autologin without on or off" 64 usage: autologin maybe
expect "autologin with more" 64 usage: autologin on "$me"
expect "an option as an account" 64 usage: remove --force delete-home
expect "a path as an account" 64 usage: reset-password /etc/shadow
expect "a path through an account" 64 usage: full-name ../root "A Name"
expect "shell text as an account" 64 usage: role 'x;id' admin

# A new account's name: the installer's rule.
expect "a name in capitals" 65 "lowercase letters" add Sam standard
expect "a name starting with a digit" 65 "lowercase letters" add 1sam standard
expect "a name with a space" 65 "lowercase letters" add "sam i" standard
expect "an empty name" 65 "lowercase letters" add "" standard
expect "a name with shell text" 65 "lowercase letters" add 'sam;id' standard
expect "an option as a new name" 65 "lowercase letters" add --system standard
expect "a name of 33 characters" 65 "lowercase letters" add aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa standard
expect "root as a new name" 65 "the system uses" add root admin
expect "a group's name as a new name" 65 "the system uses" add wheel standard
expect "a service's name as a new name" 65 "the system uses" add systemd-coredump standard
expect "a name that has an account ($me)" 65 "already has an account" add "$me" standard

# A full name: nothing that splits a passwd line.
expect "a full name with a colon" 65 "full name" add "$free" standard "a:b"
expect "a full name with a comma" 65 "full name" add "$free" standard "Example, Sam"
expect "a full name with =" 65 "full name" full-name "$me" "a=b"
expect "a full name with a line break" 65 "full name" full-name "$me" $'Sam\nroot:x:0:0'
expect "a full name of 81 characters" 65 "full name" full-name "$me" "$(printf 'a%.0s' {1..81})"

# Accounts that aren't a person's.
expect "removing root" 65 "not a person" remove root delete-home
expect "a password for root" 65 "not a person" reset-password root
expect "a role for a service account" 65 "not a person" role nobody admin
expect "removing nobody in particular" 65 "not a person" remove "$free" keep-home

# Yourself.
expect "removing yourself" 65 "signed in with" remove "$me" delete-home
expect "removing yourself, keeping the home" 65 "signed in with" remove "$me" keep-home
expect "your own role" 65 "your own role" role "$me" standard
expect "your own password" 65 "Security" reset-password "$me"

# check judges without doing; without it, a good request needs root.
code=0
out=$("$helper" check add "$free" standard "Sam Example" 2>&1 </dev/null) || code=$?
if ((code == 0)) && [[ -z $out ]]; then ok "check: a good new account"; else bad "check add: exit $code [$out]"; fi
code=0
out=$("$helper" check autologin off 2>&1 </dev/null) || code=$?
if ((code == 0)) && [[ -z $out ]]; then ok "check: automatic login off"; else bad "check autologin off: exit $code [$out]"; fi
expect "check refuses as the call would" 65 "signed in with" check remove "$me" delete-home
if ((EUID != 0)); then
  expect "a good new account, not as root" 77 "root" add "$free" standard "Sam Example"
  expect "a good name change, not as root" 77 "root" full-name "$me" "Sam Example"
  expect "automatic login off, not as root" 77 "root" autologin off
fi
if getent passwd "$free" >/dev/null; then bad "an account named $free exists after the checks"; else ok "no account was made"; fi

# status: who is here, and what each account allows.
if command -v jq >/dev/null; then
  status=$("$helper" status 2>"$scratch") || bad "status failed: $(<"$scratch")"
  if jq -e --arg me "$me" '
      .you == $me and (.encrypted | type) == "boolean" and (.autologin.on | type) == "boolean"
      and ([.users[] | select(.you)] | length) == 1
      and ([.users[] | select(.you)][0] | .name == $me and .cannotRemove != "" and .cannotChangeRole != "")
      and ([.users[] | select(.uid < 1000 or .uid > 59999)] | length) == 0' <<<"$status" >/dev/null
  then ok "status: you, once, and neither removable nor demotable by yourself"
  else bad "status: $status"; fi
  if ((EUID != 0)) && [[ $(jq '.users | length' <<<"$status") == 1 ]]; then
    if jq -e '.users[0].cannotRemove | test("signed in with")' <<<"$status" >/dev/null; then ok "status: the only person can't be removed"; else bad "status: $status"; fi
  fi
  # Automatic login can be turned on exactly when status gives no reason.
  code=0
  "$helper" check autologin on >/dev/null 2>&1 </dev/null || code=$?
  reason=$(jq -r .autologin.cannotTurnOn <<<"$status")
  if { ((code == 0)) && [[ -z $reason ]]; } || { ((code == 65)) && [[ -n $reason ]]; }; then ok "automatic login: status and the check agree"
  else bad "autologin on: exit $code, status says [$reason]"; fi
else
  echo "skip status (no jq)"
fi

# The rules between several people, and the one file automatic login
# writes, in a made-up /etc: a user namespace where this user plays root and
# an overlay stands over /etc, so nothing of the machine's is read as
# another person's or written at all. Skipped where the kernel doesn't allow
# that. /run is empty there but for udev's records (lsblk reads a disk's
# encryption from them): room for the helper's lock, and no logind, so nobody
# counts as signed in. PKEXEC_UID says who is asking, as pkexec does.
sandbox=$(mktemp -d)
# (The overlay leaves a work folder nobody may read.)
trap 'rm -f "$scratch"; chmod -R u+rwx "$sandbox" 2>/dev/null; rm -rf "$sandbox"' EXIT
mkdir -p "$sandbox/upper" "$sandbox/work" "$sandbox/udev"
# shellcheck disable=SC2016 # expanded by the inner shell
inside='
  mount -t overlay overlay -o "lowerdir=/etc,upperdir=$1/upper,workdir=$1/work" /etc || exit 90
  mount --bind /run/udev "$1/udev" && mount -t tmpfs tmpfs /run && mkdir /run/udev &&
    mount --bind "$1/udev" /run/udev || exit 90
  shift
  exec bash "$@"'
if ! unshare -rm bash -c "$inside" _ "$sandbox" -c true 2>/dev/null; then
  echo "skip the made-up /etc (no user namespace with an overlay here)"
else
  cat >"$sandbox/cases" <<'CASES'
helper=$1
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }
groups() { rm -f /etc/group; echo "$1" >/etc/group; }
# as <uid> <name> <exit> <words> [arguments...]
as() {
  local uid=$1 name=$2 want=$3 words=$4 code=0 err
  shift 4
  err=$(PKEXEC_UID=$uid "$helper" "$@" 2>&1 >/dev/null </dev/null) || code=$?
  if ((code == want)) && [[ -z $words || $err == *"$words"* ]]; then ok "$name"; else bad "$name: exit $code (want $want) [$err]"; fi
}
accounts() {
  rm -f /etc/passwd
  {
    echo "root:x:0:0::/root:/usr/bin/bash"
    echo "greeter:x:960:960::/:/usr/bin/nologin"
    echo "svc:x:1150:1150:A service::/usr/bin/nologin"
    printf '%s\n' "$@"
  } >/etc/passwd
}
config() {
  mkdir -p /etc/greetd
  printf '%s\n' "# a comment at the top" "[terminal]" "vt = 1" "" "$@" \
    "[default_session]" 'command = "/usr/lib/karchy/greeter"' 'user = "greeter"' >/etc/greetd/config.toml
}
initial=("[initial_session]" 'command = "/usr/lib/karchy/session"' 'user = "ada"' "")
ada="ada:x:1100:1100:Ada Example,,,:/home/ada:/usr/bin/fish"
sam="sam:x:1101:1101::/home/sam:/usr/bin/fish"
pat="pat:x:1102:1102:Pat:/home/pat:/usr/bin/bash"

# Two people, one administrator.
accounts "$ada" "$sam"
groups "wheel:x:998:ada"
config "${initial[@]}"
status=$(PKEXEC_UID=1100 "$helper" status)
if jq -e '.you == "ada" and .admin and (.users | map(.name) == ["ada", "sam"])
    and .users[0].fullName == "Ada Example" and .users[0].admin and (.users[1].admin | not)
    and .autologin.on and .autologin.user == "ada" and .autologin.cannotTurnOn != ""
    and .users[1].cannotRemove == "" and .users[1].cannotChangeRole == ""' <<<"$status" >/dev/null
then ok "status: two people, the service accounts left out"; else bad "status: $status"; fi
as 1100 "the administrator removes the other person" 0 "" check remove sam delete-home
as 1100 "the administrator makes the other one too" 0 "" check role sam admin
as 1100 "the administrator resets the other's password" 0 "" check reset-password sam
as 1101 "the only administrator can't be removed" 65 "only administrator" check remove ada keep-home
as 1101 "the only administrator keeps the role" 65 "only administrator" check role ada standard
as 1101 "making an administrator one again is no change to refuse" 0 "" check role ada admin
as 1100 "no second automatic login with two people" 65 "" check autologin on
as 1100 "a taken name, as another person asks" 65 "already has an account" check add sam standard
as 1100 "a service account's name" 65 "the system uses" check add svc standard

# Automatic login off: only the [initial_session] part goes.
before=$(grep -v -e '^\[initial_session\]' -e 'karchy/session' -e '"ada"' /etc/greetd/config.toml | cat -s)
as 1100 "automatic login off" 0 "" autologin off
if [[ $(</etc/greetd/config.toml) == "$before" ]]; then ok "the config lost its [initial_session] and nothing else"
else bad "the config after off: $(</etc/greetd/config.toml)"; fi
[[ $(PKEXEC_UID=1100 "$helper" status | jq -r .autologin.on) == false ]] && ok "status: automatic login is off" || bad "status still says on"
as 1100 "automatic login off again changes nothing" 0 "" autologin off
[[ $(</etc/greetd/config.toml) == "$before" ]] && ok "the config is the same after a second off" || bad "a second off changed the config"

# A second administrator: either can go, neither by their own hand.
accounts "$ada" "$sam" "$pat"
groups "wheel:x:998:ada,pat"
as 1102 "with two administrators one removes the other" 0 "" check remove ada delete-home
as 1102 "...or takes the role" 0 "" check role ada standard
as 1102 "...but not their own" 65 "your own role" check role pat standard
as 1102 "...and not themselves" 65 "signed in with" check remove pat keep-home

# One person: the only account stays, and automatic login is theirs to set
# where the disk is encrypted.
accounts "$ada"
groups "wheel:x:998:ada"
as 1101 "the only account can't be removed" 65 "only account" check remove ada keep-home
status=$(PKEXEC_UID=1100 "$helper" status)
if [[ $(jq -r .encrypted <<<"$status") == true ]]; then
  as 1100 "automatic login on" 0 "" autologin on
  status=$(PKEXEC_UID=1100 "$helper" status)
  if jq -e '.autologin.on and .autologin.user == "ada"' <<<"$status" >/dev/null &&
    [[ $(grep -c '^\[initial_session\]' /etc/greetd/config.toml) == 1 ]] &&
    grep -qxF 'command = "/usr/lib/karchy/session"' /etc/greetd/config.toml &&
    [[ $(grep -c '^\[default_session\]' /etc/greetd/config.toml) == 1 ]]
  then ok "the config logs ada in, and keeps its login screen"; else bad "the config after on: $(</etc/greetd/config.toml)"; fi
  as 1100 "automatic login on again" 0 "" autologin on
  [[ $(grep -c '^\[initial_session\]' /etc/greetd/config.toml) == 1 ]] && ok "one [initial_session] after a second on" || bad "a second on added another part"
  as 1100 "and off" 0 "" autologin off
  [[ $(</etc/greetd/config.toml) == "$before" ]] && ok "off again gives the same config" || bad "the config after on and off: $(</etc/greetd/config.toml)"
else
  as 1100 "no automatic login without disk encryption" 65 "isn't encrypted" check autologin on
  jq -e '.autologin.cannotTurnOn | test("encrypted")' <<<"$status" >/dev/null && ok "status says why" || bad "status: $status"
  echo "skip automatic login on (this machine's disk is not encrypted)"
fi

# A config that isn't root's own file, or has no login screen, is left alone.
config "${initial[@]}"
sed -i '/default_session/d' /etc/greetd/config.toml
sum=$(sha256sum </etc/greetd/config.toml)
as 1100 "a config without a login screen is not written" 1 "no login screen" autologin off
mv /etc/greetd/config.toml /etc/greetd/real.toml && ln -s real.toml /etc/greetd/config.toml
as 1100 "a config that is a link is not written" 1 "not a regular file" autologin off
[[ $(sha256sum </etc/greetd/real.toml) == "$sum" ]] && ok "both were left as they were" || bad "a refused config was changed"
exit "$fails"
CASES
  unshare -rm bash -c "$inside" _ "$sandbox" "$sandbox/cases" "$(realpath "$helper")" || fails=1
fi

((fails == 0)) && echo "users-settings: all as expected"
exit "$fails"
