#!/bin/bash
# Settings › Power's command and what applies its choices when the charger
# goes in or out: karchy-settings-power, karchy-powerprofiles-set,
# karchy-power-source and the root helper system/power/power-settings.
# Usage: tests/settings-power.sh
#        tests/settings-power.sh --machine <dir> laptop|desktop <command>...
#
# Runs as an ordinary user and changes nothing on the machine: everything
# happens in a user namespace where this user plays root, with a made-up
# home, /etc/systemd, /etc/UPower and /run, the checkout's root helper in
# /usr/lib/karchy, karchy-laptop's drop-ins where the package puts them, and
# made-up programs over the ones that need a real battery, daemon or screen:
#   busctl            UPower (a battery or none, on battery or not, its
#                     charge), logind's lid properties, the running profile
#   powerprofilesctl  the profiles this machine has; `set` is recorded
#   brightnessctl     `set` is recorded
#   karchy-hw-display, karchy-hw-laptop, karchy-hibernation-available
#                     what the test says this machine has
#   hyprctl, karchy-shell, systemctl
#                     answer and do nothing
#   pkexec            runs the helper as it is (this user is root here)
# jq and systemd-analyze are the real ones, so the drop-ins are read as
# systemd reads them.
#
# --machine runs a command on such a made-up machine kept in <dir> (made as a
# laptop, plugged in at 80%, or as a desktop, when the folder is new), so the
# commands and the Settings page can be tried on a computer without a
# battery:
#   tests/settings-power.sh --machine /tmp/m laptop karchy-settings-power status
#   touch /tmp/m/t/on-battery; echo 12 >/tmp/m/t/percent     # unplug it, drain it
# What the machine is and what was done to it are the files in <dir>/t (see
# the busctl stand-in below) and <dir>/t/log.
# shellcheck disable=SC2016 # the quoted scripts are for the inner shells
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
for needed in jq unshare systemd-analyze; do
  command -v "$needed" >/dev/null || { echo "settings-power: $needed is needed"; exit 2; }
done

machine="" kind=""
if [[ ${1:-} == --machine ]]; then
  [[ $# -ge 4 && ( $3 == laptop || $3 == desktop ) ]] || { sed -n '5,6s/^# *//p' "$0" >&2; exit 2; }
  mkdir -p "$2" || exit 2
  machine=$(realpath "$2") kind=$3
  shift 3
fi

if [[ -n $machine ]]; then
  sandbox=$machine
else
  sandbox=$(mktemp -d)
  trap 'chmod -R u+rwx "$sandbox" 2>/dev/null; rm -rf "$sandbox"' EXIT
fi
new=0
[[ -d $sandbox/t ]] || new=1
# The drop-in folders are made in the overlay's upper layer: this user can't
# make them inside the real, root-owned /usr/lib/systemd.
mkdir -p "$sandbox"/{etc.up,etc.work,bin.up,bin.work,lib.up/karchy,lib.work,home,t} \
  "$sandbox"/{etc-systemd,etc-upower,lib-logind,lib-sleep} "$sandbox"/lib.up/systemd/{logind,sleep}.conf.d
install -m755 "$root/system/power/power-settings" "$sandbox/lib.up/karchy/power-settings"
install -Dm644 "$root/system/laptop/logind.conf" "$sandbox/laptop/logind.conf"
install -Dm644 "$root/system/laptop/sleep.conf" "$sandbox/laptop/sleep.conf"
if (( new )) && [[ $kind == laptop ]]; then
  touch "$sandbox"/t/{battery,backlight,hibernation}
  echo 80 >"$sandbox/t/percent"
  printf '%s\n' power-saver balanced performance >"$sandbox/t/profiles"
  install -m644 "$sandbox/laptop/logind.conf" "$sandbox/lib-logind/30-karchy-laptop.conf"
  install -m644 "$sandbox/laptop/sleep.conf" "$sandbox/lib-sleep/30-karchy-laptop.conf"
  install -m644 "$root/system/laptop/upower.conf" "$sandbox/etc-upower/UPower.conf"
fi

stub() { cat >"$sandbox/bin.up/$1" && chmod 755 "$sandbox/bin.up/$1"; }

# What the machine is, as files in /run/t: `battery` (present), `on-battery`,
# `percent`, `profile` (running). logind's lid properties are what its
# configuration says, as after the reload the helper asks for.
stub busctl <<'STUB'
#!/bin/bash
t=/run/t
[[ $1 == get-property ]] || exit 1
lid() { systemd-analyze cat-config systemd/logind.conf 2>/dev/null | sed -n "s/^$1=//p" | tail -n 1; }
case "$2 $4" in
  "org.freedesktop.UPower org.freedesktop.UPower")
    [[ -e $t/on-battery ]] && echo "b true" || echo "b false" ;;
  "org.freedesktop.UPower org.freedesktop.UPower.Device")
    shift 4
    for property in "$@"; do
      case $property in
        Type) [[ -e $t/battery ]] && echo "u 2" || echo "u 0" ;;
        PowerSupply | IsPresent) [[ -e $t/battery ]] && echo "b true" || echo "b false" ;;
        Percentage) echo "d $(cat $t/percent 2>/dev/null || echo 0)" ;;
      esac
    done ;;
  "org.freedesktop.login1 org.freedesktop.login1.Manager")
    case $5 in
      HandleLidSwitch) value=$(lid HandleLidSwitch); echo "s \"${value:-suspend}\"" ;;
      HandleLidSwitchExternalPower)
        value=$(lid HandleLidSwitchExternalPower)
        echo "s \"${value:-$(lid HandleLidSwitch)}\"" ;;
      HandleLidSwitchDocked) value=$(lid HandleLidSwitchDocked); echo "s \"${value:-ignore}\"" ;;
    esac ;;
  "net.hadess.PowerProfiles net.hadess.PowerProfiles")
    [[ -e $t/profiles ]] || exit 1
    echo "s \"$(cat $t/profile 2>/dev/null || echo balanced)\"" ;;
  *) exit 1 ;;
esac
STUB
stub powerprofilesctl <<'STUB'
#!/bin/bash
t=/run/t
[[ -e $t/profiles ]] || exit 1
case $1 in
  list)
    for name in $(tac $t/profiles); do
      [[ $name == "$(cat $t/profile 2>/dev/null || echo balanced)" ]] && mark="*" || mark=" "
      printf '%s %s:\n    Driver:     fake\n\n' "$mark" "$name"
    done ;;
  set) echo "$2" >$t/profile; echo "profile $2" >>$t/log ;;
esac
STUB
stub brightnessctl <<'STUB'
#!/bin/bash
echo "brightness $*" >>/run/t/log
STUB
stub karchy-hw-display <<'STUB'
#!/bin/bash
[[ -e /run/t/backlight ]] && echo fake_bl
STUB
stub karchy-hw-laptop <<'STUB'
#!/bin/bash
[[ -e /run/t/battery ]]
STUB
stub karchy-hibernation-available <<'STUB'
#!/bin/bash
[[ -e /run/t/hibernation ]]
STUB
stub hyprctl <<'STUB'
#!/bin/bash
[[ $1 == binds ]] && echo '[{"key": "XF86PowerOff", "modmask": 0, "description": "Power menu"}]'
exit 0
STUB
stub karchy-shell <<'STUB'
#!/bin/bash
exit 0
STUB
stub systemctl <<'STUB'
#!/bin/bash
echo "systemctl $*" >>/run/t/log
STUB
stub pkexec <<'STUB'
#!/bin/bash
exec "$@"
STUB

inside='
  sandbox=$1; shift
  mount -t overlay overlay -o "lowerdir=/etc,upperdir=$sandbox/etc.up,workdir=$sandbox/etc.work" /etc &&
    mount -t overlay overlay -o "lowerdir=/usr/bin,upperdir=$sandbox/bin.up,workdir=$sandbox/bin.work" /usr/bin &&
    mount -t overlay overlay -o "lowerdir=/usr/lib,upperdir=$sandbox/lib.up,workdir=$sandbox/lib.work" /usr/lib &&
    mount -t tmpfs tmpfs /run || exit 90
  mkdir -p /run/t /etc/systemd /etc/UPower
  for made in etc-systemd:/etc/systemd etc-upower:/etc/UPower t:/run/t \
    lib-logind:/usr/lib/systemd/logind.conf.d lib-sleep:/usr/lib/systemd/sleep.conf.d; do
    mount --bind "$sandbox/${made%%:*}" "${made#*:}" || exit 90
  done
  checkout=$1; shift
  export HOME=$sandbox/home KARCHY_PATH=$checkout LAPTOP=$sandbox/laptop PATH=$sandbox/bin.up:$checkout/bin:/usr/bin
  unset XDG_CONFIG_HOME XDG_STATE_HOME KARCHY_POWERPROFILES_STATE_DIR
  exec "$@"'
if ! unshare -rm bash -c "$inside" _ "$sandbox" "$root" true 2>/dev/null; then
  echo "skip settings-power (no user namespace with an overlay here)"
  # A check that didn't run must not pass where nobody reads the output.
  [[ -z ${CI:-} ]] || exit 1
  exit 0
fi

if [[ -n $machine ]]; then
  exec unshare -rm bash -c "$inside" _ "$sandbox" "$root" "$@"
fi

cat >"$sandbox/cases" <<'CASES'
set -u
t=/run/t
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }
# is <name> <got> <want>
is() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
power() { karchy-settings-power "$@" 2>$t/err; }
value() { power status | jq -r --arg k "$1" '.values[$k] // "none"'; }
field() { power status | jq -c "$1"; }
log() { cat $t/log 2>/dev/null | tr '\n' ';'; }
clear_log() { rm -f $t/log; }
shell_json() { jq -c "$1" "$HOME/.config/karchy/shell.json" 2>/dev/null || echo missing; }
refused() { # <name> <words stderr must hold> <arguments...>
  local name=$1 words=$2 code=0
  shift 2
  power "$@" >/dev/null || code=$?
  if ((code != 0)) && grep -q -- "$words" $t/err; then ok "$name"; else bad "$name: exit $code, stderr [$(cat $t/err)]"; fi
}
sleep_file=/etc/systemd/sleep.conf.d/60-karchy-settings.conf
profiles_dir=$HOME/.local/state/karchy/powerprofiles

# ------------------------------------------------- a desktop: no battery
is "desktop: no battery, no profiles, no backlight" \
  "$(field '[.battery, .lid, .hibernation, .backlight, .profiles, .source]')" '[false,false,false,false,[],"ac"]'
is "desktop: no profile settings to show" "$(value profile.ac)" none
is "desktop: brightness is left alone" "$(value brightness.ac)" 0
is "desktop: nothing saved" "$(field .saved)" '{}'
refused "desktop: a power mode can't be set" "no power modes" set profile.ac balanced

# ------------------------------------------------- a laptop, plugged in
touch $t/battery $t/backlight $t/hibernation
echo 80 >$t/percent
printf '%s\n' power-saver balanced performance >$t/profiles
install -m644 "$LAPTOP/logind.conf" /usr/lib/systemd/logind.conf.d/30-karchy-laptop.conf
install -m644 "$LAPTOP/sleep.conf" /usr/lib/systemd/sleep.conf.d/30-karchy-laptop.conf

is "laptop: what it has" "$(field '[.battery, .lid, .hibernation, .backlight, .profiles]')" \
  '[true,true,true,true,["power-saver","balanced","performance"]]'
is "laptop: Balanced on both sources until one is picked" "$(value profile.battery)/$(value profile.ac)" balanced/balanced
is "laptop: hibernates after 2 hours" "$(value hibernateAfter)" 120
is "laptop: stays asleep while plugged in (karchy-laptop's drop-in)" "$(value hibernate.ac)" never
is "laptop: nothing saved, nothing foreign" "$(field '[.saved, .foreign]')" '[{},[]]'

# The other source's profile is remembered and waits for that source.
power set profile.battery power-saver >/dev/null
is "profile.battery set on AC: remembered" "$(cat "$profiles_dir/battery")" power-saver
is "profile.battery set on AC: the running profile is left alone" "$(log)" ""
is "profile.battery: reported, and counted as a choice" "$(field '[.values["profile.battery"], .saved]')" \
  '["power-saver",{"profile.battery":"power-saver"}]'
is "profile.battery: not written to power.json" "$(ls "$HOME/.config/karchy" 2>/dev/null | tr '\n' ' ')" ""
power set profile.ac performance >/dev/null
is "profile.ac set on AC: switched at once" "$(log)" "profile performance;"
is "the running profile is reported" "$(field .profile)" '"performance"'
refused "a profile that isn't one" "Usage" set profile.ac turbo
printf '%s\n' power-saver balanced >$t/profiles
refused "a profile this machine lacks" "no performance mode" set profile.battery performance
is "a remembered profile the machine lost reads as Balanced" "$(value profile.ac)" balanced
printf '%s\n' power-saver balanced performance >$t/profiles

# Screen brightness for each source.
clear_log
power set brightness.battery 40 >/dev/null
is "brightness.battery set on AC: written to shell.json" "$(shell_json .power.brightness)" '{"battery":40}'
is "brightness.battery set on AC: the screen is left alone" "$(log)" ""
is "brightness.battery: in effect and recorded" "$(field '[.values["brightness.battery"], .saved["brightness.battery"]]')" '[40,40]'
power set brightness.ac 80 >/dev/null
is "brightness.ac set on AC: the screen follows at once" "$(log)" "brightness -d fake_bl set 80%;"
power set brightness.ac keep >/dev/null
is "brightness.ac keep: taken out of shell.json and the record" \
  "$(shell_json .power.brightness)$(field '.saved | has("brightness.ac")')" '{"battery":40}false'
for wrong in 0 101 4x -5 ""; do refused "brightness '$wrong' is refused" "Usage" set brightness.ac "$wrong"; done
jq '.power.brightness.battery = 55' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
is "a brightness edited by hand in shell.json is what is shown" "$(value brightness.battery)" 55
power set lock.ac 600 >/dev/null
is "…and it is the user's now: the record forgets it" "$(field '.saved | has("brightness.battery")')" false
power set brightness.battery 40 >/dev/null
power set lock.ac 300 >/dev/null

# The charger goes out, and in again.
clear_log
touch $t/on-battery
karchy-power-source battery
is "unplugged: the battery's profile and brightness" "$(log)" "profile power-saver;brightness -d fake_bl set 40%;"
is "status names the source in use" "$(field .source)" '"battery"'
clear_log
rm $t/on-battery
karchy-power-source ac
is "plugged in: the AC profile, and the screen left as it is" "$(log)" "profile performance;"
rm $t/backlight
clear_log
touch $t/on-battery
karchy-power-source battery
is "no backlight: only the profile" "$(log)" "profile power-saver;"
touch $t/backlight
is "karchy-power-source wants a source" "$(karchy-power-source 2>&1; echo $?)" "Usage: karchy-power-source <ac|battery>
1"

# Power saver at the first battery warning: karchy's default, off a choice.
power set profile.battery performance >/dev/null
is "battery.saver is on until turned off, and no choice" "$(value battery.saver)$(field '.saved | has("battery.saver")')" onfalse
echo 10 >$t/percent
clear_log
karchy-powerprofiles-set battery
is "by default: Power saver on a low battery" "$(log)" "profile power-saver;"
is "…and the battery's own profile is still remembered" "$(cat "$profiles_dir/battery")" performance
clear_log
power set battery.saver off >/dev/null
is "battery.saver off: written, recorded" "$(shell_json .battery.saver)$(field '.saved["battery.saver"]')" 'false"off"'
is "battery.saver off while low on battery: the battery's profile at once" "$(log)" "profile performance;"
clear_log
karchy-powerprofiles-set battery
is "saver off: a low battery keeps its profile" "$(log)" "profile performance;"
# A choice from when off was the default: on, recorded and written.
jq '.settings["battery.saver"] = "on"' "$HOME/.config/karchy/power.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/power.json"
jq '.battery.saver = true' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
is "an old record of \"on\" is the default now, so no choice" "$(value battery.saver)$(field '.saved | has("battery.saver")')" onfalse
clear_log
power set battery.saver on >/dev/null
is "battery.saver on: the default, so nothing kept" "$(shell_json '.battery | has("saver")')$(field '.saved | has("battery.saver")')" falsefalse
is "battery.saver on while low on battery: Power saver at once" "$(log)" "profile power-saver;"
for name in karchy-battery-running-low; do
  for level in 16:1 15:0 15.4:0 15.6:1; do
    echo "${level%:*}" >$t/percent
    "$name"; is "the battery is low at ${level%:*}%: ${level#*:}" "$?" "${level#*:}"
  done
done
rm $t/on-battery; echo 5 >$t/percent
karchy-battery-running-low; is "plugged in: never low" "$?" 1
touch $t/on-battery; rm $t/battery
karchy-battery-running-low; is "no battery that powers the machine: never low" "$?" 1
touch $t/battery
for level in 16:performance 15:power-saver 3:power-saver; do
  echo "${level%:*}" >$t/percent
  clear_log
  karchy-powerprofiles-set battery
  is "saver on, ${level%:*}% (warning at 15%)" "$(log)" "profile ${level#*:};"
done
echo 15.4 >$t/percent
clear_log; karchy-powerprofiles-set autodetect
is "the charge is rounded as the shell rounds it (15.4% is 15%)" "$(log)" "profile power-saver;"
clear_log; karchy-powerprofiles-set battery balanced
is "a profile picked by hand while low wins, and is remembered" "$(log)$(cat "$profiles_dir/battery")" "profile balanced;balanced"
power set profile.battery performance >/dev/null
power set battery.low 25 >/dev/null
echo 22 >$t/percent
clear_log; karchy-powerprofiles-set battery
is "the level follows battery.low" "$(log)" "profile power-saver;"
power set battery.low 15 >/dev/null
# The low warning turned off by hand: the critical one is the first.
jq '.battery.low = 0' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
echo 10 >$t/percent; clear_log; karchy-powerprofiles-set battery
is "low warning off: 10% keeps the profile" "$(log)" "profile performance;"
echo 5 >$t/percent; clear_log; karchy-powerprofiles-set battery
is "low warning off: Power saver at the critical level" "$(log)" "profile power-saver;"
jq 'del(.battery.low)' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
echo 10 >$t/percent
printf '%s\n' balanced performance >$t/profiles
clear_log; karchy-powerprofiles-set battery
is "no Power saver on this machine: the profile stays" "$(log)" "profile performance;"
printf '%s\n' power-saver balanced performance >$t/profiles
rm $t/on-battery
clear_log; karchy-powerprofiles-set ac
is "plugged in: never Power saver for the charge" "$(log)" "profile performance;"
touch $t/on-battery
jq '.battery.low = 0 | .battery.critical = 0' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
echo 1 >$t/percent
karchy-battery-running-low; is "both warnings off: never low" "$?" 1
jq 'del(.battery.low, .battery.critical)' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
echo 10 >$t/percent
refused "battery.saver takes on or off" "Usage" set battery.saver maybe
rm $t/on-battery
echo 80 >$t/percent

# Hibernation while plugged in, through the root helper.
clear_log
power set hibernate.ac same >/dev/null
is "hibernate.ac same: the drop-in says so" "$(grep -v '^#' $sleep_file | tr '\n' ' ')" "[Sleep] HibernateOnACPower=yes "
is "hibernate.ac same: in effect, recorded, not foreign" "$(field '[.values["hibernate.ac"], .saved["hibernate.ac"], .foreign]')" '["same","same",[]]'
power set hibernateAfter 60 >/dev/null
is "with a delay: both lines" "$(grep -v '^#' $sleep_file | tr '\n' ' ')" "[Sleep] HibernateDelaySec=60min HibernateOnACPower=yes "
printf '[Sleep]\nHibernateOnACPower=no\n' >/etc/systemd/sleep.conf.d/90-mine.conf
is "a later drop-in decides: shown as it is, and named foreign" "$(field '[.values["hibernate.ac"], .foreign]')" '["never",["hibernate.ac"]]'
rm /etc/systemd/sleep.conf.d/90-mine.conf
power set hibernate.ac never >/dev/null
is "hibernate.ac never is karchy's default: only the delay is left" "$(grep -v '^#' $sleep_file | tr '\n' ' ')" "[Sleep] HibernateDelaySec=60min "
power set hibernateAfter 120 >/dev/null
is "back at the defaults: no drop-in, nothing recorded for it" "$([[ -e $sleep_file ]] && echo there)$(field '.saved | has("hibernateAfter") or has("hibernate.ac")')" false
refused "hibernate.ac takes never or same" "Usage" set hibernate.ac yes
helper=/usr/lib/karchy/power-settings
for wrong in "hibernate-on-ac=maybe" "hibernate-on-ac=" "hibernate-on-ac=yes hibernate-on-ac=no" "hibernate-on-ac=yes;id" \
  "lid-ac=sleep lid-battery=sleep lid-docked=sleep hibernate-after=60 hibernate-on-ac=yes extra=1"; do
  # shellcheck disable=SC2086 # several arguments on purpose
  $helper $wrong >/dev/null 2>$t/err; code=$?
  is "the helper refuses [$wrong]" "$code:$(ls /etc/systemd/sleep.conf.d 2>/dev/null)" "64:"
done
$helper hibernate-on-ac=no lid-ac=ignore
is "the helper writes what it is told" "$(grep -hv '^#' $sleep_file /etc/systemd/logind.conf.d/60-karchy-settings.conf | tr '\n' ' ')" \
  "[Sleep] HibernateOnACPower=no [Login] HandleLidSwitchExternalPower=ignore "
$helper
is "the helper with nothing to say removes both files" "$(ls /etc/systemd/sleep.conf.d /etc/systemd/logind.conf.d 2>/dev/null | grep -c conf$)" 0

# The lid on each source, as before these settings were added.
power set lid.ac ignore >/dev/null
is "lid.ac ignore: plugged in only, and not foreign" "$(value lid.battery)/$(value lid.ac) $(field .foreign)" "sleep/ignore []"
power set lid.ac sleep >/dev/null
is "lid.ac back to sleep: no drop-in left" "$(ls /etc/systemd/logind.conf.d 2>/dev/null | wc -l)" 0

# Back to karchy's defaults.
power set hibernate.ac same >/dev/null
power set battery.saver off >/dev/null
power set lock.battery 120 >/dev/null
is "before the reset: six choices" "$(power status | jq -r '.saved | keys | join(" ")')" \
  "battery.saver brightness.battery hibernate.ac lock.battery profile.ac profile.battery"
clear_log
power reset >/dev/null
is "reset: nothing saved" "$(field .saved)" '{}'
is "reset: the profiles are forgotten and Balanced runs" "$(ls "$profiles_dir" | wc -l)$(log)" "0profile balanced;"
is "reset: shell.json holds none of it" "$(shell_json '[has("power"), has("battery"), has("idle")]')" '[false,false,false]'
is "reset: no drop-in, no record" "$([[ -e $sleep_file ]] && echo drop-in)$([[ -e $HOME/.config/karchy/power.json ]] && echo record)" ""
is "reset: the defaults again" "$(value profile.ac) $(value brightness.battery) $(value battery.saver) $(value hibernate.ac) $(value lock.battery)" \
  "balanced 0 on never 300"

exit "$fails"
CASES

fails=0
unshare -rm bash -c "$inside" _ "$sandbox" "$root" bash "$sandbox/cases" || fails=1
((fails == 0)) && echo "settings-power: all as expected"
exit "$fails"
