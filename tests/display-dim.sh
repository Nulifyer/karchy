#!/bin/bash
# The dimming of the built-in screen before it turns off (Settings › Power,
# "Dim it first"): `karchy-brightness-display dim N` and `undim`, and
# everything that can come between the two. The idle service only says when
# to dim and undim (its order is tests/idle-times.js); what is put back, and
# whether it still is this dimming's to put back, is decided here.
# Usage: tests/display-dim.sh
#
# The real karchy-brightness-display, karchy-hw-display and karchy-power-source
# run against a made-up backlight (a folder with `brightness` and
# `max_brightness`) through a stand-in brightnessctl; hyprctl records what it
# is asked. Nothing on the machine is touched.
# shellcheck disable=SC2016 # the quoted scripts are for the stand-ins
set -u
root=$(cd "$(dirname "$0")/.." && pwd)
command -v jq >/dev/null || { echo "display-dim: jq is needed"; exit 2; }

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"/{bin,run,home,sys/fake_bl}
stub() { cat >"$work/bin/$1" && chmod 755 "$work/bin/$1"; }

# get, max, -m and set (raw or percent) on the made-up backlight. A file
# named `fail` beside it makes every write fail, as a driver that says no.
stub brightnessctl <<'STUB'
#!/bin/bash
machine=0 device=""
while (( $# > 0 )); do
  case $1 in
    -q) shift ;;
    -m) machine=1; shift ;;
    -d) device=$2; shift 2 ;;
    *) break ;;
  esac
done
dir=$KARCHY_BACKLIGHT_PATH/$device
[[ -n $device && -r $dir/brightness ]] || exit 1
current=$(<"$dir/brightness") max=$(<"$dir/max_brightness")
if (( machine )); then
  echo "$device,backlight,$current,$(( (current * 100 + max / 2) / max ))%,$max"
  exit 0
fi
case ${1:-} in
  get) echo "$current" ;;
  max) echo "$max" ;;
  set)
    [[ ! -e $dir/fail ]] || exit 1
    value=$2
    if [[ $value == *% ]]; then value=$(( (${value%\%} * max + 50) / 100 )); fi
    [[ $value =~ ^[0-9]+$ ]] || exit 1
    (( value <= max )) || value=$max
    echo "$value" >"$dir/brightness"
    echo "set $value" >>"$KARCHY_TEST_LOG" ;;
  *) exit 1 ;;
esac
STUB
stub hyprctl <<'STUB'
#!/bin/bash
echo "hyprctl $*" >>"$KARCHY_TEST_LOG"
[[ $1 == monitors ]] && echo '[{"disabled": false, "dpmsStatus": false}]'
exit 0
STUB
stub karchy-hyprland-monitor-focused <<'STUB'
#!/bin/bash
echo eDP-1
STUB
stub karchy-osd <<'STUB'
#!/bin/bash
exit 0
STUB
stub karchy-shell <<'STUB'
#!/bin/bash
exit 0
STUB
stub karchy-powerprofiles-set <<'STUB'
#!/bin/bash
exit 0
STUB

export HOME=$work/home KARCHY_PATH=$root XDG_RUNTIME_DIR=$work/run KARCHY_BACKLIGHT_PATH=$work/sys KARCHY_TEST_LOG=$work/log
export PATH=$work/bin:$root/bin:/usr/bin
unset XDG_CONFIG_HOME XDG_STATE_HOME

bl=$work/sys/fake_bl
note=$work/run/karchy-brightness-display-dim
fails=0
ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }
is() { if [[ $2 == "$3" ]]; then ok "$1"; else bad "$1: got [$2], want [$3]"; fi; }
# A screen with 1000 levels at `level`, no dimming noted, an empty log.
screen() { echo "${2:-1000}" >"$bl/max_brightness"; echo "$1" >"$bl/brightness"; rm -f "$note" "$bl/fail" "$work/log"; }
level() { cat "$bl/brightness"; }
noted() { [[ -s $note ]] && echo noted || echo none; }
state() { echo "$(level) $(noted)"; }
log() { cat "$work/log" 2>/dev/null | tr '\n' ';'; }
display() { karchy-brightness-display "$@"; }
brightness_for() { mkdir -p "$HOME/.config/karchy"; echo "{\"version\": 1, \"power\": {\"brightness\": {\"battery\": $1}}}" >"$HOME/.config/karchy/shell.json"; }

# ------------------------------------------------------------ dim, then undim
screen 637
display dim 10
is "dim: down to 10% of the range, and noted" "$(state)" "100 noted"
display undim
is "undim: exactly the level it had" "$(state)" "637 none"
is "…in two writes" "$(log)" "set 100;set 637;"
display undim
is "undim with nothing dimmed: nothing happens" "$(state) $(log)" "637 none set 100;set 637;"

for start in 100 99 40 1 0; do
  screen "$start"
  display dim 10
  is "a screen at $start of 1000 is at or under 10%: not touched, nothing noted" "$(state) [$(log)]" "$start none []"
done
screen 101
display dim 10
is "one step above the dim level is dimmed" "$(state)" "100 noted"

screen 600
display dim 10; display dim 10; display dim 30
is "dim again while dimmed: nothing more" "$(state) $(log)" "100 noted set 100;"
display undim
is "…and the first level is what comes back" "$(state)" "600 none"

screen 5 7
display dim 10
is "few levels (7): never to 0" "$(state)" "1 noted"
display undim
is "…and back" "$(state)" "5 none"
screen 1 7
display dim 10
is "few levels, already at the lowest: not touched" "$(state)" "1 none"

# ------------------------------------------------- the brightness keys
screen 600
display dim 10
display +5%
is "brightness up while dimmed: a step from the level it had, not from the dim one" "$(state)" "650 none"
display undim
is "…and the wake that follows changes nothing" "$(state)" "650 none"
screen 600
display dim 10
display 5%-
is "brightness down while dimmed: a step down from the level it had" "$(state)" "550 none"
screen 600
display dim 10
display --no-osd --monitor eDP-1 40%
is "the monitor panel's slider while dimmed: its level, the dimming forgotten" "$(state)" "400 none"
# The same in the other order: the wake's undim first, then the key.
screen 600
display dim 10
display undim; display +5%
is "undim, then the key: the same level either way" "$(state)" "650 none"

# ------------------------------------------- a level set by something else
screen 600
display dim 10
brightnessctl -q -d fake_bl set 300
display undim
is "a level set by hand since is left alone, the note dropped" "$(state)" "300 none"
screen 600
display dim 10
brightnessctl -q -d fake_bl set 40
display undim
is "…also a darker one" "$(state)" "40 none"

# ----------------------------------- the charger, with and without a brightness
screen 600
brightness_for 40
display dim 10
karchy-power-source battery
is "charger pulled while dimmed, battery brightness 40%: that brightness" "$(state)" "400 none"
display undim
is "…and the wake that follows keeps it" "$(state)" "400 none"
screen 600
brightness_for 10
display dim 10
karchy-power-source battery
display undim
is "the source's brightness equal to the dim level is kept, not taken for the dimming" "$(state)" "100 none"
screen 600
brightness_for 0
display dim 10
karchy-power-source battery
is "charger pulled while dimmed, no brightness set: back to its level, never left dim" "$(state)" "600 none"
screen 600
brightness_for 40
karchy-power-source battery
display dim 10
display undim
is "dimmed after the charger: back to the source's brightness" "$(state)" "400 none"
rm -f "$HOME/.config/karchy/shell.json"

# ------------------------------------------------- screen off, wake, sleep
screen 600
display dim 10
display off
is "screen off while dimmed: the level is back, the note gone" "$(state)" "600 none"
is "…in this order: dim, the screen off, the level back" "$(log)" 'set 100;hyprctl dispatch hl.dsp.dpms({ action = "disable" });set 600;'
screen 600
display dim 10
display on
is "wake while dimmed: the level back before the screen is lit" "$(state) $(log | sed 's/hyprctl monitors -j;//')" \
  '600 none set 100;set 600;hyprctl dispatch hl.dsp.dpms({ action = "enable" });'

# ----------------------------------------------------- a write that fails
screen 600
display dim 10
touch "$bl/fail"
display undim; code=$?
is "undim that can't write: says so and keeps the note" "$code $(state)" "1 100 noted"
rm "$bl/fail"
display on
is "…so the next wake puts the level back" "$(state)" "600 none"
screen 600
touch "$bl/fail"
display dim 10
is "dim that can't write: no note left behind" "$(state)" "600 none"

# ------------------------------------------------- no built-in screen, usage
screen 600
mv "$bl" "$work/sys.away"
display dim 10; code=$?
is "no backlight: dim does nothing and succeeds" "$code $(noted)" "0 none"
display undim; code=$?
is "no backlight: undim does nothing and succeeds" "$code" 0
mv "$work/sys.away" "$bl"
for wrong in "" 0 100 x 5% "10 20"; do
  # shellcheck disable=SC2086 # several arguments on purpose
  display dim $wrong 2>/dev/null; code=$?
  is "dim '$wrong' is refused" "$code $(state)" "1 600 none"
done

# ------------------------------------------------- at the same moment
# dim and undim started together, as when somebody comes back the instant
# the screen dims: whichever wins, one more undim (the idle service always
# sends it after the dim has ended) leaves the level it had.
screen 600
wrong=0
for _ in $(seq 40); do
  display dim 10 & display undim & wait
  display undim
  [[ $(state) == "600 none" ]] || wrong=$((wrong + 1))
done
is "dim and undim at once, 40 times: never left dim" "$wrong" 0
# A key press and the wake's undim together: one step from the level it had.
wrong=0
for _ in $(seq 40); do
  screen 600
  display dim 10
  display undim & display +5% & wait
  [[ $(state) == "650 none" ]] || wrong=$((wrong + 1))
done
is "a brightness key and the wake at once, 40 times: 65% every time" "$wrong" 0

(( fails == 0 )) && echo "display-dim: all as expected"
exit "$fails"
