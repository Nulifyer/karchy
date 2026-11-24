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
#                     charge, and what it will do at the critical battery
#                     level: by default no answer, so the files are read),
#                     logind's lid properties, the running profile
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
  "$sandbox"/{etc-systemd,etc-upower/UPower.conf.d,lib-logind,lib-sleep} "$sandbox"/lib.up/systemd/{logind,sleep}.conf.d
install -m755 "$root/system/power/power-settings" "$sandbox/lib.up/karchy/power-settings"
install -Dm644 "$root/system/laptop/logind.conf" "$sandbox/laptop/logind.conf"
install -Dm644 "$root/system/laptop/sleep.conf" "$sandbox/laptop/sleep.conf"
install -Dm644 "$root/system/laptop/upower.conf" "$sandbox/laptop/upower.conf"
# UPower's own main file, as the upower package ships it (the keys karchy
# cares about): a drop-in overrides only keys this file has.
if [[ ! -e $sandbox/etc-upower/UPower.conf ]]; then
  printf '%s\n' '[UPower]' 'UsePercentageForPolicy=true' 'PercentageLow=20.0' 'PercentageCritical=5.0' \
    'PercentageAction=2.0' 'AllowRiskyCriticalPowerAction=false' 'CriticalPowerAction=Auto' >"$sandbox/etc-upower/UPower.conf"
fi
if (( new )) && [[ $kind == laptop ]]; then
  touch "$sandbox"/t/{battery,backlight,hibernation}
  echo 80 >"$sandbox/t/percent"
  printf '%s\n' power-saver balanced performance >"$sandbox/t/profiles"
  install -m644 "$sandbox/laptop/logind.conf" "$sandbox/lib-logind/30-karchy-laptop.conf"
  install -m644 "$sandbox/laptop/sleep.conf" "$sandbox/lib-sleep/30-karchy-laptop.conf"
  install -m644 "$sandbox/laptop/upower.conf" "$sandbox/etc-upower/UPower.conf.d/50-karchy-laptop.conf"
fi

stub() { cat >"$sandbox/bin.up/$1" && chmod 755 "$sandbox/bin.up/$1"; }

# What the machine is, as files in /run/t: `battery` (present), `on-battery`,
# `percent`, `profile` (running). logind's lid properties are what its
# configuration says, as after the reload the helper asks for.
stub busctl <<'STUB'
#!/bin/bash
t=/run/t
# What the running UPower says it will do, when the test has it say so.
if [[ $1 == call && "$*" == *GetCriticalAction ]]; then
  [[ -s $t/critical-action ]] || exit 1
  echo "s \"$(cat $t/critical-action)\""
  exit 0
fi
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
# The screensaver's launcher gets as far as asking for the terminal, which
# says there is none it can use; reaching that is recorded.
stub xdg-terminal-exec <<'STUB'
#!/bin/bash
echo "screensaver would start" >>/run/t/log
echo none
STUB
stub karchy-notification-send <<'STUB'
#!/bin/bash
exit 0
STUB
stub karchy-hyprland-monitor-focused <<'STUB'
#!/bin/bash
echo eDP-1
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
  export XDG_RUNTIME_DIR=/run/t
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
install -m644 "$LAPTOP/upower.conf" /etc/UPower/UPower.conf.d/50-karchy-laptop.conf

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
is "karchy-power-source wants a source" "$(karchy-power-source 2>&1; echo $?)" "Usage: karchy-power-source <ac|battery> | session
1"

# The session's start: the source the last run applied is kept, and only a
# different one is applied (a charger pulled or plugged in while the computer
# was off). Here the last run was on battery.
source_file=$HOME/.local/state/karchy/power-source
is "each run keeps its source" "$(<"$source_file")" battery
power set brightness.ac 70 >/dev/null
clear_log
karchy-power-source session
is "start on the same source: nothing set, the screen as it is" "$(log)" ""
rm $t/on-battery
clear_log
karchy-power-source session
is "start plugged in after a shutdown on battery: the AC profile and brightness" "$(log)" "profile performance;brightness -d fake_bl set 70%;"
is "…and plugged in is kept" "$(<"$source_file")" ac
clear_log
karchy-power-source session
is "…once: the next start changes nothing" "$(log)" ""
touch $t/on-battery
rm "$source_file"
clear_log
karchy-power-source session
is "nothing kept yet (the first session): nothing set, the source kept" "$(log) $(<"$source_file")" " battery"
power set brightness.ac keep >/dev/null

# Dimming before the screen turns off, for each source: karchy's is 30
# seconds before on battery and never plugged in.
is "dim: 30 seconds before on battery, never plugged in" "$(value dim.battery)/$(value dim.ac)" 30/0
power set dim.battery 60 >/dev/null
is "dim.battery 60: written for the battery only" "$(shell_json '[.idle.battery.dim, .idle.ac.dim]') $(value dim.battery)/$(value dim.ac)" "[60,null] 60/0"
power set dim.ac 30 >/dev/null
is "dim.ac 30: written for plugged in, and recorded" "$(shell_json .idle.ac.dim) $(field '[.saved["dim.battery"], .saved["dim.ac"]]')" "30 [60,30]"
power set dim.ac never >/dev/null
is "dim.ac never: karchy's again, out of shell.json and the record" "$(shell_json .idle.ac.dim) $(value dim.ac) $(field '.saved | has("dim.ac")')" "null 0 false"
for wrong in 4 601 0 x 30s ""; do refused "dim '$wrong' is refused" "Usage" set dim.ac "$wrong"; done
power set dim.battery 30 >/dev/null
is "dim.battery back at karchy's: out of shell.json and the record" "$(shell_json '.idle | has("battery")')$(field '.saved | has("dim.battery")')" falsefalse
jq '.idle.dim = 10' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
is "idle.dim edited by hand: battery, plugged in keeps karchy's never" "$(value dim.battery)/$(value dim.ac)" "10/0"
power set dim.ac 120 >/dev/null
is "one source set apart from a shared time by hand" "$(value dim.battery)/$(value dim.ac)" 10/120
jq 'del(.idle.dim)' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"

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
# No screensaver on a low battery; as ever above the level and plugged in.
echo 15 >$t/percent; clear_log
karchy-launch-screensaver >/dev/null 2>&1; is "low battery: the screensaver does not start" "$? [$(log)]" "1 []"
karchy-launch-screensaver force >/dev/null 2>&1; is "…unless forced" "$(log)" "screensaver would start;"
echo 16 >$t/percent; clear_log
karchy-launch-screensaver >/dev/null 2>&1; is "on battery above the warning level: it starts" "$(log)" "screensaver would start;"
rm $t/on-battery; echo 5 >$t/percent; clear_log
karchy-launch-screensaver >/dev/null 2>&1; is "plugged in, however low: it starts" "$(log)" "screensaver would start;"
touch $t/on-battery
power set battery.saver off >/dev/null; clear_log
karchy-launch-screensaver >/dev/null 2>&1; is "low battery with Power saver turned off: still no screensaver" "$? [$(log)]" "1 []"
power set battery.saver on >/dev/null
mkdir -p "$HOME/.local/state/karchy/toggles"; touch "$HOME/.local/state/karchy/toggles/screensaver-off"
echo 80 >$t/percent; clear_log
karchy-launch-screensaver >/dev/null 2>&1; is "the screensaver-off toggle still stops it at any charge" "$? [$(log)]" "1 []"
rm "$HOME/.local/state/karchy/toggles/screensaver-off"
echo 10 >$t/percent
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

# The critical battery: UPower's level and action, through the root helper.
upower_file=/etc/UPower/UPower.conf.d/60-karchy-settings.conf
upower_lines() { grep -v '^#' $upower_file 2>/dev/null | tr '\n' ' '; }
is "karchy-laptop's drop-in over UPower's own 2%: 3% and hibernate, no choice, nothing foreign" \
  "$(value criticalBattery.level) $(value criticalBattery.action) $(field '[(.saved | has("criticalBattery.level") or has("criticalBattery.action")), .foreign]')" '3 hibernate [false,[]]'
clear_log
power set criticalBattery.level 4 >/dev/null
is "criticalBattery.level 4: the three levels, descending, in UPower's drop-in" "$(upower_lines)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=15.0 PercentageCritical=5.0 PercentageAction=4.0 "
is "criticalBattery.level 4: in effect, recorded, not foreign" "$(field '[.values["criticalBattery.level"], .saved["criticalBattery.level"], .foreign]')" '[4,4,[]]'
is "…and UPower is started again to read it" "$(log)" "systemctl try-restart upower.service;"
clear_log
power set criticalBattery.level 4 >/dev/null
is "the same choice again: nothing written, UPower left running" "$(log)" ""
refused "criticalBattery.level at the last warning (5%) is refused" "before the last battery warning (5%)" set criticalBattery.level 5
refused "criticalBattery.level above it is refused" "before the last battery warning (5%)" set criticalBattery.level 7
is "…and nothing changed" "$(upower_lines)$(value criticalBattery.level)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=15.0 PercentageCritical=5.0 PercentageAction=4.0 4"
refused "the old name empty.level is no setting" "Usage" set empty.level 4
refused "nor empty.action" "Usage" set empty.action poweroff
is "status names neither" "$(field '.values | has("empty.level") or has("empty.action")')" false
for wrong in 1 21 0 x 3.5 "" 03; do refused "criticalBattery.level '$wrong' is refused" "Usage" set criticalBattery.level "$wrong"; done
refused "a second warning at the critical battery level is refused" "critical battery level (4%)" set battery.critical 4
refused "…and under it" "critical battery level (4%)" set battery.critical 3
power set battery.critical 10 >/dev/null
power set criticalBattery.level 7 >/dev/null
is "criticalBattery.level 7 under a warning at 10%: UPower's critical level moves above it" "$(upower_lines)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=15.0 PercentageCritical=8.0 PercentageAction=7.0 "
refused "the second warning can't then go to 7%" "critical battery level (7%)" set battery.critical 7
refused "…nor 5%" "critical battery level (7%)" set battery.critical 5
# The second warning turned off by hand: the first is the last.
jq '.battery.critical = 0' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
refused "second warning off: the first can't go to the critical battery level" "critical battery level (7%)" set battery.low 7
power set criticalBattery.level 10 >/dev/null
is "second warning off: the critical battery level may go up to under the first (15%)" "$(value criticalBattery.level)" 10
refused "…but not to it" "before the last battery warning (15%)" set criticalBattery.level 15
jq '.battery.low = 0' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
power set criticalBattery.level 20 >/dev/null
is "both warnings off: nothing to come before, up to the helper's 20%" "$(upower_lines)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=22.0 PercentageCritical=21.0 PercentageAction=20.0 "
jq 'del(.battery.low, .battery.critical)' "$HOME/.config/karchy/shell.json" >$t/edit && cp $t/edit "$HOME/.config/karchy/shell.json"
is "the warnings put back by hand at 15% and 5% under a level of 20%: shown as it is" "$(value criticalBattery.level)/$(value battery.critical)" 20/5
power set criticalBattery.level 3 >/dev/null
is "criticalBattery.level back at karchy's 3%: no drop-in, no record" "$([[ -e $upower_file ]] && echo there)$(field '.saved | has("criticalBattery.level")')" false

clear_log
power set criticalBattery.action poweroff >/dev/null
is "criticalBattery.action poweroff: written, in effect, recorded" "$(upower_lines)$(field '[.values["criticalBattery.action"], .saved["criticalBattery.action"], .foreign]')" \
  '[UPower] CriticalPowerAction=PowerOff ["poweroff","poweroff",[]]'
is "…and UPower is started again" "$(log)" "systemctl try-restart upower.service;"
power set criticalBattery.level 4 >/dev/null
is "level and action together" "$(upower_lines)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=15.0 PercentageCritical=5.0 PercentageAction=4.0 CriticalPowerAction=PowerOff "
power set lid.ac ignore >/dev/null
is "another system choice leaves UPower's file as it is" "$(upower_lines)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=15.0 PercentageCritical=5.0 PercentageAction=4.0 CriticalPowerAction=PowerOff "
power set lid.ac sleep >/dev/null
power set criticalBattery.level 3 >/dev/null
power set criticalBattery.action hibernate >/dev/null
is "criticalBattery.action hibernate is karchy's default: no drop-in, no record" "$([[ -e $upower_file ]] && echo there)$(field '.saved | has("criticalBattery.action")')" false
for wrong in suspend ignore sleep shutdown ""; do refused "criticalBattery.action '$wrong' is refused" "Usage" set criticalBattery.action "$wrong"; done

# What the running UPower says wins over what the files say.
echo HybridSleep >$t/critical-action
is "UPower answers something else: shown as it is, and named foreign" "$(field '[.values["criticalBattery.action"], .foreign]')" '["hybridsleep",["criticalBattery.action"]]'
echo Hibernate >$t/critical-action
is "UPower answers Hibernate: as chosen" "$(field '[.values["criticalBattery.action"], .foreign]')" '["hibernate",[]]'
rm $t/critical-action

# UPower's own rules for its files.
printf '[UPower]\nPercentageAction=4.7\n' >/etc/UPower/UPower.conf.d/90-mine.conf
is "a later drop-in decides, its fraction dropped as UPower drops it" "$(field '[.values["criticalBattery.level"], .foreign]')" '[4,[]]'
power set criticalBattery.level 2 >/dev/null
is "…also over a choice made here, which is then named foreign" "$(field '[.values["criticalBattery.level"], .saved["criticalBattery.level"], .foreign]')" '[4,2,["criticalBattery.level"]]'
mv /etc/UPower/UPower.conf.d/90-mine.conf /etc/UPower/UPower.conf.d/mine.conf
is "a drop-in UPower doesn't read (no two digits and a dash) changes nothing" "$(value criticalBattery.level)$(field .foreign)" '2[]'
power set criticalBattery.level 3 >/dev/null
mv /etc/UPower/UPower.conf.d/mine.conf /etc/UPower/UPower.conf.d/90-mine.conf
printf '[UPower]\nPercentageCritical=3.0\n' >/etc/UPower/UPower.conf.d/90-mine.conf
is "levels that don't descend: UPower's own 2%" "$(value criticalBattery.level)" 2
printf '[UPower]\nTimeAktion=1\nPercentageAction = 2.0 \n' >/etc/UPower/UPower.conf.d/90-mine.conf
is "spaces around the equals sign are read" "$(value criticalBattery.level)" 2
printf '[Other]\nPercentageAction=1.0\n' >/etc/UPower/UPower.conf.d/90-mine.conf
is "another group is not UPower's" "$(value criticalBattery.level)" 3
rm /etc/UPower/UPower.conf.d/90-mine.conf

# A machine that can't hibernate: UPower shuts it down, and that is the choice.
rm $t/hibernation
is "no hibernation: shuts down, by default" "$(field '[.values["criticalBattery.action"], (.saved | has("criticalBattery.action")), .foreign]')" '["poweroff",false,[]]'
refused "no hibernation: hibernate can't be chosen" "can't hibernate" set criticalBattery.action hibernate
power set criticalBattery.action poweroff >/dev/null
is "no hibernation: \"shut down\" is what it does already, so nothing is written" "$([[ -e $upower_file ]] && echo there)$(field '.saved | has("criticalBattery.action")')" false
$helper battery-action=hibernate >/dev/null 2>$t/err; code=$?
is "the helper refuses hibernate there too" "$code:$(ls /etc/UPower/UPower.conf.d | tr '\n' ' ')" "1:50-karchy-laptop.conf "
touch $t/hibernation

# The helper by itself.
for wrong in "battery-level=1" "battery-level=21" "battery-level=03" "battery-level=3.0" "battery-level=" "battery-level=5;id" \
  "battery-level=3 battery-level=4" "battery-action=suspend" "battery-action=ignore" "battery-action=Hibernate" \
  "battery-action=poweroff battery-action=poweroff" "battery-level=../x" \
  "lid-ac=sleep lid-battery=sleep lid-docked=sleep hibernate-after=60 hibernate-on-ac=yes battery-level=3 battery-action=poweroff extra=1"; do
  # shellcheck disable=SC2086 # several arguments on purpose
  $helper $wrong >/dev/null 2>$t/err; code=$?
  is "the helper refuses [$wrong]" "$code:$(ls /etc/UPower/UPower.conf.d | tr '\n' ' ')" "64:50-karchy-laptop.conf "
done
clear_log
$helper battery-level=2 battery-action=hibernate
is "the helper writes what it is told, in one file UPower will read" "$(ls /etc/UPower/UPower.conf.d | tr '\n' ' ')$(upower_lines)" \
  "50-karchy-laptop.conf 60-karchy-settings.conf [UPower] UsePercentageForPolicy=true PercentageLow=15.0 PercentageCritical=5.0 PercentageAction=2.0 CriticalPowerAction=Hibernate "
is "…owned as a config file should be, and UPower restarted once" "$(stat -c %a $upower_file) $(log)" "644 systemctl try-restart upower.service;"
$helper battery-level=14
is "the helper keeps the three levels descending at 14" "$(upower_lines)" \
  "[UPower] UsePercentageForPolicy=true PercentageLow=16.0 PercentageCritical=15.0 PercentageAction=14.0 "
clear_log
$helper
is "the helper with nothing to say removes its file and restarts UPower" "$(ls /etc/UPower/UPower.conf.d | tr '\n' ' ')$(log)" \
  "50-karchy-laptop.conf systemctl try-restart upower.service;"
clear_log
$helper lid-ac=ignore
is "a lid choice alone restarts nothing of UPower's" "$(log)" "systemctl kill --kill-whom=main --signal=HUP systemd-logind.service;"
$helper

# The lid on each source, as before these settings were added.
power set lid.ac ignore >/dev/null
is "lid.ac ignore: plugged in only, and not foreign" "$(value lid.battery)/$(value lid.ac) $(field .foreign)" "sleep/ignore []"
power set lid.ac sleep >/dev/null
is "lid.ac back to sleep: no drop-in left" "$(ls /etc/systemd/logind.conf.d 2>/dev/null | wc -l)" 0

# Back to karchy's defaults.
power set hibernate.ac same >/dev/null
power set battery.saver off >/dev/null
power set lock.battery 120 >/dev/null
power set criticalBattery.level 4 >/dev/null
power set criticalBattery.action poweroff >/dev/null
is "before the reset: nine choices" "$(power status | jq -r '.saved | keys | join(" ")')" \
  "battery.saver brightness.battery criticalBattery.action criticalBattery.level dim.ac hibernate.ac lock.battery profile.ac profile.battery"
clear_log
power reset >/dev/null
is "reset: nothing saved" "$(field .saved)" '{}'
is "reset: the profiles are forgotten and Balanced runs" "$(ls "$profiles_dir" | wc -l)$(log | grep -o 'profile [a-z-]*;')" "0profile balanced;"
is "reset: shell.json holds none of it" "$(shell_json '[has("power"), has("battery"), has("idle")]')" '[false,false,false]'
is "reset: no drop-in, no record" "$([[ -e $sleep_file || -e $upower_file ]] && echo drop-in)$([[ -e $HOME/.config/karchy/power.json ]] && echo record)" ""
is "reset: UPower is started again without the choices" "$(log | grep -c 'try-restart upower')$(value criticalBattery.level)$(value criticalBattery.action)" "13hibernate"
is "reset: the defaults again" "$(value profile.ac) $(value brightness.battery) $(value battery.saver) $(value hibernate.ac) $(value lock.battery) $(value dim.ac)" \
  "balanced 0 on never 300 0"

exit "$fails"
CASES

fails=0
unshare -rm bash -c "$inside" _ "$sandbox" "$root" bash "$sandbox/cases" || fails=1
((fails == 0)) && echo "settings-power: all as expected"
exit "$fails"
