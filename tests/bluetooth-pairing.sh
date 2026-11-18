#!/bin/bash

# Exercises bin/karchy-bluetooth-pair against a fake bluetoothctl, since a
# device that asks for a passkey cannot be had in a VM. The fake prints what
# bluetoothctl 5.88 prints when its output is a pipe (recorded from a real
# session between two emulated controllers: colored prompts, lines redrawn
# over the prompt with \r, agent questions with no line break) and plays one
# pairing per scenario.
#
# Usage: tests/bluetooth-pairing.sh

set -u

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

address=AA:BB:CC:DD:EE:FF
failures=0

mkdir "$work/bin"
cat >"$work/bin/bluetoothctl" <<'FAKE'
#!/bin/bash

# With arguments this is the one-shot form karchy-bluetooth-device uses to
# read the adapter state.
if (($# > 0)); then
  [[ $1 == show ]] && echo "	Powered: yes"
  exit 0
fi

address=$FAKE_ADDRESS
PROMPT=$'\033[0;94m[bluetoothctl]> \033[0m'

# A line as it arrives over the waiting prompt, and the prompt drawn again.
line() {
  printf '\r%79s\r%s\n%s' '' "$1" "$PROMPT"
}

# A changed property, with its colored tag.
changed() {
  printf '\r%79s\r[\033[0;93mCHG\033[0m] %s\n%s' '' "$1" "$PROMPT"
}

# An agent question: it replaces the prompt and ends with no line break.
question() {
  printf '\r\033[1;39m\033[1;39m[agent] %s \033[0m\033[0m' "$1"
}

# A passkey to type on the device, with the digits typed so far dimmed.
passkey() {
  printf '\r%79s\r\033[0;91m[agent]\033[0m Passkey: \033[1;30m%s\033[1;37m%s\n\033[0m%s' '' "${1:0:$2}" "${1:$2}" "$PROMPT"
}

# The next line typed at the prompt, echoed as readline echoes it.
typed() {
  IFS= read -r input || exit 0
  printf '%s\n' "$input" >>"$FAKE_LOG"
  printf '%s\n%s' "$input" "$PROMPT"
}

expect() {
  typed
  [[ $input == "$1" ]] || { line "Invalid command in menu main: $input"; exit 1; }
}

start() {
  printf 'Waiting to connect to bluetoothd...\r%s' "$PROMPT"
  line "Agent registered"
  expect "pair $address"
  line "Attempting to pair with $address"
  changed "Device $address Connected: yes"
}

paired() {
  changed "Device $address Bonded: yes"
  changed "Device $address Paired: yes"
  line "Pairing successful"
}

connect() {
  expect "trust $address"
  changed "Device $address Trusted: yes"
  line "Changing $address trust succeeded"
  expect "connect $address"
  line "Attempting to connect to $address"
  line "${1:-Connection successful}"
}

case $FAKE_SCENARIO in
  just-works)
    start
    paired
    connect
    ;;
  confirm)
    start
    line "Request confirmation"
    question "Confirm passkey 123456 (yes/no):"
    # A property changing while the question waits redraws it.
    changed "Device $address RSSI: 0xffffffc4 (-60)"
    question "Confirm passkey 123456 (yes/no):"
    typed
    if [[ $input == yes ]]; then
      paired
      connect
    else
      line "Failed to pair: org.bluez.Error.AuthenticationCanceled"
    fi
    ;;
  confirm-device-refuses)
    start
    line "Request confirmation"
    question "Confirm passkey 123456 (yes/no):"
    typed
    line "Failed to pair: org.bluez.Error.AuthenticationFailed"
    ;;
  passkey)
    start
    passkey 123456 0
    passkey 123456 2
    passkey 123456 6
    paired
    connect
    ;;
  passkey-waits)
    start
    passkey 123456 0
    sleep 30
    ;;
  pin-shown)
    start
    line "[agent] PIN code: 4821"
    paired
    connect
    ;;
  enter-pin)
    start
    line "Request PIN code"
    question "Enter PIN code:"
    typed
    if [[ $input == 0000 ]]; then
      paired
      connect
    else
      line "Failed to pair: org.bluez.Error.AuthenticationFailed"
    fi
    ;;
  enter-passkey)
    start
    line "Request passkey"
    question "Enter passkey (number in 0-999999):"
    typed
    if [[ $input == 654321 ]]; then
      paired
      connect
    else
      line "Failed to pair: org.bluez.Error.AuthenticationFailed"
    fi
    ;;
  authorize)
    start
    line "Request authorization"
    question "Accept pairing (yes/no):"
    expect yes
    paired
    # The device opens a service while the connection is being made.
    expect "trust $address"
    expect "connect $address"
    line "Attempting to connect to $address"
    line "Authorize service"
    question "Authorize service 0000110b-0000-1000-8000-00805f9b34fb (yes/no):"
    expect yes
    line "Connection successful"
    ;;
  already-paired)
    # What 5.88 does with a device it has paired: it connects instead.
    printf 'Waiting to connect to bluetoothd...\r%s' "$PROMPT"
    line "Agent registered"
    expect "pair $address"
    line "Device $address is already paired, connecting instead, remove it first to pair it again"
    line "Attempting to connect to $address"
    expect "trust $address"
    line "Changing $address trust succeeded"
    line "Connection successful"
    ;;
  already-exists)
    start
    line "Failed to pair: org.bluez.Error.AlreadyExists"
    connect
    ;;
  pair-fails-connect-works)
    start
    line "Failed to pair: org.bluez.Error.AuthenticationFailed"
    connect
    ;;
  unreachable)
    start
    line "Failed to pair: org.bluez.Error.ConnectionAttemptFailed"
    connect "Failed to connect: org.bluez.Error.Failed br-connection-page-timeout"
    ;;
  connect-fails)
    start
    paired
    connect "Failed to connect: org.bluez.Error.Failed br-connection-profile-unavailable"
    expect "connect $address"
    line "Failed to connect: org.bluez.Error.Failed br-connection-profile-unavailable"
    expect "info $address"
    line "Device $address (public)"
    line "	Connected: no"
    ;;
  connect-retry)
    start
    paired
    connect "Failed to connect: org.bluez.Error.Failed br-connection-canceled"
    expect "connect $address"
    line "Attempting to connect to $address"
    line "Connection successful"
    ;;
  connect-never-reports)
    start
    paired
    expect "trust $address"
    expect "connect $address"
    line "Attempting to connect to $address"
    expect "info $address"
    line "Device $address (public)"
    line "	Paired: yes"
    line "	Connected: ${FAKE_CONNECTED:-yes}"
    line "	BREDR.Connected: yes"
    ;;
  unknown-device)
    printf 'Waiting to connect to bluetoothd...\r%s' "$PROMPT"
    line "Agent registered"
    expect "pair $address"
    line "Device $address not available"
    ;;
  no-bluetoothd)
    printf 'Waiting to connect to bluetoothd...'
    sleep 30
    ;;
  silent)
    start
    sleep 30
    ;;
esac

typed
FAKE
chmod +x "$work/bin/bluetoothctl"

export PATH="$work/bin:$root/bin:$PATH"
export FAKE_ADDRESS=$address
export FAKE_LOG="$work/typed"

pass() {
  printf 'ok    %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n      %s\n' "$1" "$2"
  failures=$((failures + 1))
}

# check <name> <scenario> <exit status> <script>
#
# The script is the conversation, one item per line: a line the helper must
# print next, or "> text" to type as the answer once the lines before it have
# been printed.
check() {
  local name=$1 scenario=$2 want_status=$3 script=$4
  local step got status extra

  : >"$FAKE_LOG"
  coproc HELPER { FAKE_SCENARIO=$scenario exec "${helper[@]}" 2>&1; }
  local out=${HELPER[0]} in=${HELPER[1]} pid=$HELPER_PID

  while IFS= read -r step; do
    [[ -n $step ]] || continue
    if [[ $step == "> "* ]]; then
      printf '%s\n' "${step#> }" >&"$in"
      continue
    fi
    if ! IFS= read -r -t 15 -u "$out" got; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      fail "$name" "expected \"$step\", got nothing"
      return
    fi
    if [[ $got != "$step" ]]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      fail "$name" "expected \"$step\", got \"$got\""
      return
    fi
  done <<<"$script"

  extra=""
  IFS= read -r -t 15 -u "$out" extra
  wait "$pid"
  status=$?

  if [[ -n $extra ]]; then
    fail "$name" "unexpected line after the script: \"$extra\""
  elif ((status != want_status)); then
    fail "$name" "exit status $status, expected $want_status"
  else
    pass "$name"
  fi
}

# What the fake bluetoothctl was sent, commands joined by "|". The closing
# quit is left out: the helper may be gone before the fake has read it.
typed_log() {
  grep -vx quit "$FAKE_LOG" | tr '\n' '|'
}

helper=(karchy-bluetooth-pair "$address")
session="pair $address|trust $address|connect $address|"

check "a device with no code pairs without a question" just-works 0 "
paired
connected"
[[ $(typed_log) == "$session" ]] || fail "a device with no code: commands sent" "$(typed_log)"

check "a code to compare is asked once and yes pairs" confirm 0 "
confirm 123456
> yes
paired
connected"
[[ $(typed_log) == "pair $address|yes|trust $address|connect $address|" ]] ||
  fail "a code to compare: commands sent" "$(typed_log)"

check "no to the code ends the pairing as cancelled" confirm 1 "
confirm 123456
> no
failed canceled"

check "anything but yes or no is not an answer" confirm 0 "
confirm 123456
> maybe
> remove *
> yes
paired
connected"
[[ $(typed_log) != *remove* && $(typed_log) != *maybe* ]] || fail "an invalid answer reached bluetoothctl" "$(typed_log)"

check "the device refusing the code is reported" confirm-device-refuses 1 "
confirm 123456
> yes
failed rejected"

check "a passkey to type on the device is shown once" passkey 0 "
passkey 123456
paired
connected"

check "cancel gives up while the passkey is being typed" passkey-waits 1 "
passkey 123456
> cancel
failed canceled"

check "a PIN to type on the device is shown" pin-shown 0 "
pin 4821
paired
connected"

check "the device's own PIN is asked for and sent" enter-pin 0 "
enter-pin
> 0000
paired
connected"

check "a wrong PIN is reported" enter-pin 1 "
enter-pin
> 1234
failed rejected"

check "the number a device shows is asked for and sent" enter-passkey 0 "
enter-passkey
> 654321
paired
connected"

check "a passkey that is not a number is not sent" enter-passkey 0 "
enter-passkey
> six
> 654321
paired
connected"
[[ $(typed_log) != *six* ]] || fail "a non-numeric passkey reached bluetoothctl" "$(typed_log)"

check "authorization for the pairing started here is given" authorize 0 "
paired
connected"

check "a device BlueZ already has paired is connected" already-paired 0 "
paired
connected"

check "a pairing BlueZ says exists is connected" already-exists 0 "
paired
connected"

check "a device that fails to pair without a code is still connected" pair-fails-connect-works 0 "
connected"

check "a device out of range is reported" unreachable 1 "
failed unreachable"

check "a cancelled connection is tried once more" connect-retry 0 "
paired
connected"

check "paired but not connected is reported" connect-fails 1 "
paired
failed connect"

KARCHY_BLUETOOTH_PAIR_CONNECT_TIMEOUT=1 check "a connection that never reports is read from BlueZ" connect-never-reports 0 "
paired
connected"

FAKE_CONNECTED=no KARCHY_BLUETOOTH_PAIR_CONNECT_TIMEOUT=1 check "a connection that never happens is reported" connect-never-reports 1 "
paired
failed connect"

check "an address BlueZ has not seen is reported" unknown-device 1 "
failed unknown-device"

KARCHY_BLUETOOTH_PAIR_START_TIMEOUT=1 check "no bluetoothd is reported" no-bluetoothd 1 "
failed no-bluetooth"

KARCHY_BLUETOOTH_PAIR_TIMEOUT=1 check "a pairing that never ends times out" silent 1 "
failed timeout"

# With nobody to answer, a question ends the pairing instead of waiting.
: >"$FAKE_LOG"
output=$(FAKE_SCENARIO=confirm karchy-bluetooth-pair "$address" </dev/null 2>&1)
status=$?
if [[ $output == "failed no-answer" && $status == 1 ]]; then
  pass "a question with stdin closed ends the pairing"
else
  fail "a question with stdin closed ends the pairing" "status $status: $output"
fi

output=$(FAKE_SCENARIO=just-works karchy-bluetooth-pair "$address" </dev/null 2>&1)
status=$?
if [[ $output == $'paired\nconnected' && $status == 0 ]]; then
  pass "a device with no code pairs with stdin closed"
else
  fail "a device with no code pairs with stdin closed" "status $status: $output"
fi

# karchy-bluetooth-device pair is the command the panel runs.
helper=(karchy-bluetooth-device pair "$address")
check "karchy-bluetooth-device pair passes the question and the answer through" confirm 0 "
confirm 123456
> yes
paired
connected"

if karchy-bluetooth-pair not-an-address >/dev/null 2>&1; then
  fail "a malformed address is refused" "exit status 0"
else
  pass "a malformed address is refused"
fi

leftover=$(find "${XDG_RUNTIME_DIR:-/tmp}" -maxdepth 1 -name 'karchy-bluetooth-pair.*' 2>/dev/null | wc -l)
if ((leftover == 0)); then
  pass "no working directory is left behind"
else
  fail "no working directory is left behind" "$leftover left in ${XDG_RUNTIME_DIR:-/tmp}"
fi

echo
if ((failures > 0)); then
  echo "$failures failed"
  exit 1
fi
echo "all passed"
