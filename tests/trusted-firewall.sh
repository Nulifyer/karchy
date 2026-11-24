#!/bin/bash
# karchy-localsend-firewall (D-33, D-68, D-166), the root helper that opens
# apps' ports on trusted networks only, run unchanged as root in a user
# namespace (bwrap) with stand-ins at the paths it uses: ufw keeping a rule
# list, systemctl, karchy-trusted-networks answering from a file, and the
# apps' files to say what is installed.
#  - LocalSend's port opens on the devices of trusted connections only
#  - KDE Connect's, Jellyfin's and Plex's ports open only while the app is
#    installed, and close when it is removed
#  - an untrusted device beside a trusted one gets nothing; a device name
#    that isn't a plain name is never passed to ufw
#  - at boot (NetworkManager not running) every port closes
#  - a second run changes nothing; arguments and the environment change
#    nothing; `status` reports each app
# Usage: tests/trusted-firewall.sh [repo root] [-v]   (-v prints ufw's calls)
# Needs bwrap with overlay support (0.10 or later).
set -uo pipefail
root=$(realpath "${1:-.}")
verbose=${2:-}

if [[ ${KARCHY_FW_TEST_INSIDE:-} != 1 ]]; then
  command -v bwrap >/dev/null || { echo "skip: bwrap is not installed"; exit 0; }
  exec env KARCHY_FW_TEST_INSIDE=1 bwrap --dev-bind / / --unshare-user --uid 0 --gid 0 \
    --overlay-src /usr/bin --tmp-overlay /usr/bin \
    --overlay-src /usr/lib/systemd/system --tmp-overlay /usr/lib/systemd/system \
    --tmpfs /etc/ufw --tmpfs /run --tmpfs /tmp \
    bash "$root/tests/trusted-firewall.sh" "$root" "$verbose"
fi

pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

t=/run/test
mkdir -p "$t"
echo ENABLED=yes >/etc/ufw/ufw.conf
# The overlay can't write over a file the host's root owns, only replace it.
rm -f /usr/bin/ufw /usr/bin/systemctl /usr/bin/karchy-trusted-networks /usr/bin/kdeconnectd \
  /usr/lib/systemd/system/jellyfin.service /usr/lib/systemd/system/plexmediaserver.service
: >"$t/rules"
: >"$t/calls"

# ufw: a rule list in the format `ufw status` prints, two lines (IPv4 and v6)
# per rule, and a log of every call.
cat >/usr/bin/ufw <<'EOF'
#!/bin/bash
t=/run/test
echo "ufw $*" >>"$t/calls"
if [[ $1 == status ]]; then
  printf 'Status: active\n\nTo                         Action      From\n--                         ------      ----\n'
  cat "$t/rules"
  exit 0
fi
delete=false
[[ $1 == delete ]] && { delete=true; shift; }
[[ $1 == allow ]] || exit 1
shift
if [[ $1 != in ]]; then # the old all-interfaces form: allow <port>
  $delete && sed -i "/^$1\(\/[a-z]*\)\? \((v6) \)\?\+ALLOW/d" "$t/rules"
  exit 0
fi
device=$3 port=$7 proto="" comment=""
shift 7
while (($#)); do
  case $1 in
    proto) proto=/$2; shift 2 ;;
    comment) comment=$2; shift 2 ;;
    *) exit 1 ;;
  esac
done
if $delete; then
  grep -vE "^$port$proto( \(v6\))? on $device " "$t/rules" >"$t/rules.new"
  mv "$t/rules.new" "$t/rules"
else
  printf '%-26s ALLOW IN    %-26s # %s\n' "$port$proto on $device" Anywhere "$comment" \
    "$port$proto (v6) on $device" "Anywhere (v6)" "$comment" >>"$t/rules"
fi
EOF
cat >/usr/bin/systemctl <<'EOF'
#!/bin/bash
[[ $* == "is-active --quiet NetworkManager.service" ]] && { [[ -f /run/test/nm-up ]]; exit; }
[[ $* == "is-active ufw.service" ]] && { echo active; exit 0; }
exit 3
EOF
cat >/usr/bin/karchy-trusted-networks <<'EOF'
#!/bin/bash
[[ $* == "status --json" ]] && cat /run/test/active.json
EOF
chmod +x /usr/bin/ufw /usr/bin/systemctl /usr/bin/karchy-trusted-networks

helper() { "$root/bin/karchy-localsend-firewall" "$@"; }
# The connections up now: "<device> <trusted>" pairs.
connections() {
  local out="" device trusted
  while (($#)); do
    device=$1 trusted=$2
    shift 2
    out+=$(jq -cn --arg d "$device" --argjson t "$trusted" '{device: $d, trusted: $t}')
  done
  jq -s '{active: .}' <<<"$out" >"$t/active.json"
}
# The rules as "<port> <device> <comment>", the v6 twin shown once.
rules() { grep -v '(v6)' "$t/rules" | awk '{ print $1, $3, $NF }' | sort | paste -sd';' -; }
step() {
  if [[ -n $verbose ]]; then
    echo "-- $1"
    grep -v '^ufw status$' "$t/calls" | sed 's/^/   /'
  fi
  : >"$t/calls"
}

touch "$t/nm-up"

connections
helper
check "nothing connected: nothing open" "$(rules)" ""
step "nothing connected"

connections wlan0 true
helper
check "trusted Wi-Fi: LocalSend only, the others aren't installed" "$(rules)" "53317 wlan0 karchy-localsend"
step "trusted wlan0"

: >/usr/lib/systemd/system/jellyfin.service
helper
check "Jellyfin installed: its HTTP port, TCP only" "$(rules)" \
  "53317 wlan0 karchy-localsend;8096/tcp wlan0 karchy-jellyfin"
check "and its IPv6 twin" "$(grep -c '^8096/tcp (v6) on wlan0 .*# karchy-jellyfin$' "$t/rules")" "1"
step "Jellyfin installed"

: >/usr/lib/systemd/system/plexmediaserver.service
: >/usr/bin/kdeconnectd
chmod +x /usr/bin/kdeconnectd
helper
check "Plex and KDE Connect installed" "$(rules)" \
  "1714:1764/tcp wlan0 karchy-kdeconnect;1714:1764/udp wlan0 karchy-kdeconnect;32400/tcp wlan0 karchy-plex;53317 wlan0 karchy-localsend;8096/tcp wlan0 karchy-jellyfin"
check "no other port of theirs" "$(grep -cE '^(8920|7359|1900|5353|8324|3241[0-4]|32469)' "$t/rules")" "0"
step "Plex and KDE Connect installed"

before=$(cat "$t/rules")
helper
check "a second run: the same rules" "$(cat "$t/rules")" "$before"
check "a second run: no change asked of ufw" "$(grep -vc '^ufw status$' "$t/calls")" "0"
step "second run"

helper 1234 "allow in on eth0 to any port 22" >/dev/null 2>&1
KARCHY_PATH=/nowhere APPS="evil 22 tcp -" helper >/dev/null 2>&1
check "arguments and the environment change nothing" "$(cat "$t/rules")" "$before"
step "arguments and environment"

connections wlan0 true eth1 false 'eth0;rm' true
helper
check "an untrusted device beside: nothing on it" "$(grep -c ' on eth1 ' "$t/rules")" "0"
check "a device name with punctuation never reaches ufw" "$(grep -c 'eth0;rm' "$t/calls")" "0"
check "the trusted device keeps its rules" "$(cat "$t/rules")" "$before"
step "untrusted eth1 beside"

connections wlan0 true eth0 true
helper
check "a second trusted device gets the same ports" "$(grep -v '(v6)' "$t/rules" | grep -c ' on eth0 ')" "5"
step "second trusted device eth0"

rm /usr/lib/systemd/system/jellyfin.service
helper
check "Jellyfin removed: its port closes, on both devices" "$(grep -c 'karchy-jellyfin' "$t/rules")" "0"
check "Plex's stays" "$(grep -v '(v6)' "$t/rules" | grep -c 'karchy-plex')" "2"
step "Jellyfin removed"

json=$(helper status 2>&1); [[ -n $verbose ]] && echo "$json"
check "status: every app, with whether it is installed" \
  "$(jq -c '[.apps[] | [.id, .ports, .installed]]' <<<"$json")" \
  '[["localsend","53317",true],["kdeconnect","1714:1764",true],["jellyfin","8096",false],["plex","32400",true]]'
check "status: where Plex is open" "$(jq -c '.apps[3].open_on' <<<"$json")" '["wlan0","eth0"]'

connections wlan0 false
helper
check "the network is no longer trusted: everything closes" "$(rules)" ""
step "untrusted"

connections wlan0 true
helper
rm "$t/nm-up"
helper
check "at boot, before NetworkManager: everything closes" "$(rules)" ""
step "boot"

echo "passed: $pass, failed: $failures"
(( failures == 0 ))
