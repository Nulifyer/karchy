#!/bin/bash
# The network, before the installer asks anything else: karchy's packages are
# downloaded, so nothing can start without it. Sourced by install/karchy-install
# and by the karchy ISO's start script (karchy-iso-start), after lib.sh and ui.sh.
#
#   net_wait            online, or with a way to get there: 0 once archlinux.org
#                       answers, 1 when the person chose the shell instead
#   net_keyring_ready   the live system's pacman keyring is initialized
#
# A cable, or a phone sharing its connection over USB, connects by itself. A
# laptop without one gets a list of the Wi-Fi networks in range and a
# password question. The live system joins Wi-Fi with iwd, so the list comes
# from the kernel's scan results (`iw scan dump`) and the join goes through
# iwctl; install/base.sh carries the joined network into the installed system.

# The check the installer's preflight makes.
net_online() {
  curl -fs --max-time 5 -o /dev/null https://archlinux.org 2>/dev/null
}

# A cable is plugged in (or a phone is sharing its connection over USB).
net_wired_link() {
  local dev
  for dev in /sys/class/net/*; do
    [[ ${dev##*/} != lo && ! -d $dev/wireless && $(<"$dev/carrier") == 1 ]] 2>/dev/null && return 0
  done
  return 1
}

# The first Wi-Fi device's name (wlan0), or 1 when there is none.
net_wifi_device() {
  local dev
  for dev in /sys/class/net/*; do
    [[ -d $dev/wireless ]] || continue
    printf '%s\n' "${dev##*/}"
    return 0
  done
  return 1
}

# The networks in range, strongest first, each name once, as
# "<signal dBm><TAB><kind><TAB><name>". kind: open; psk (a password, WPA2 or
# WPA3); 8021x (a work or school sign-in); wep. Networks that hide their name,
# and names with bytes iw can only print as \x.., are left out. Reads `iw dev
# <device> scan dump` from stdin when given "-", for the tests.
net_wifi_networks() {
  if [[ $1 == - ]]; then cat; else iw dev "$1" scan dump 2>/dev/null; fi | awk '
    function flush() {
      if (seen && ssid != "" && ssid !~ /\\x/) {
        kind = ent ? "8021x" : rsn ? "psk" : priv ? "wep" : "open"
        printf "%d\t%s\t%s\n", sig, kind, ssid
      }
      seen = 1; ssid = ""; sig = -100; rsn = 0; ent = 0; priv = 0
    }
    /^BSS / { flush(); next }
    /^\tsignal: / { sig = $2 + 0; next }
    /^\tSSID: / { ssid = substr($0, 8); next }
    /^\t(RSN|WPA):/ { rsn = 1; next }
    /Authentication suites:/ { if ($0 ~ /802\.1X/ && $0 !~ /PSK|SAE/) ent = 1; next }
    /^\tcapability: / { if ($0 ~ /Privacy/) priv = 1; next }
    END { flush() }
  ' | sort -t$'\t' -k1,1nr | awk -F'\t' '!had[$3]++'
}

# A signal in dBm as a word; the console font has no bars to draw.
net_signal_word() {
  if (($1 >= -55)); then echo "strong"
  elif (($1 >= -67)); then echo "good"
  elif (($1 >= -78)); then echo "fair"
  else echo "weak"
  fi
}

net_kind_note() {
  case $1 in
    open) echo "   open, no password" ;;
    8021x) echo "   work or school sign-in" ;;
    wep) echo "   old WEP security" ;;
  esac
}

# After a join: the address and the clock take a few seconds.
net_settle() {
  local i
  for ((i = 0; i < 15; i++)); do
    net_online && return 0
    sleep 2
  done
  return 1
}

# The Wi-Fi list: pick a network, give its password, join. 0 when online
# through it, 1 to go back to the choices.
net_wifi_connect() {
  local dev=$1 list sig kind name pass choice i note="" hidden wrong
  local names=() kinds=() rows=()
  rfkill unblock wlan 2>/dev/null || true
  systemctl start iwd.service 2>/dev/null || true
  while true; do
    ui_header "Wi-Fi"
    ui_line "Looking for networks..." "$UI_DIM"
    # A scan of every band takes a few seconds, and iwd refuses a second
    # one while its own is running: ask again until one was taken, and wait
    # longer while the list is still empty.
    list=""
    for ((i = 0; i < 20; i++)); do
      ((i % 5)) || iwctl station "$dev" scan >/dev/null 2>&1 || true
      sleep 1
      list=$(net_wifi_networks "$dev")
      [[ -n $list ]] && ((i >= 3)) && break
    done
    names=() kinds=() rows=()
    while IFS=$'\t' read -r sig kind name; do
      [[ -n $name ]] || continue
      names+=("$name")
      kinds+=("$kind")
      rows+=("$(printf '%-32s  %-6s%s' "$name" "$(net_signal_word "$sig")" "$(net_kind_note "$kind")")")
    done <<<"$list"

    ui_header "Wi-Fi"
    [[ -z $note ]] || { ui_line "$note" "$UI_RED"; ui_line; }
    note=""
    if ((${#rows[@]})); then
      ui_line "Pick your network."
    else
      ui_line "No network found. Move closer to the router, or look again." "$UI_RED"
    fi
    ui_line
    choice=$(printf '%s\n' "${rows[@]}" "Look again" "A network that hides its name" "Back" | grep -v '^$' | gum choose) || return 1
    hidden=0
    case $choice in
      "Look again") continue ;;
      "Back") return 1 ;;
      "A network that hides its name")
        name=$(gum input --placeholder "" --header "The network's name") || continue
        [[ -n $name ]] || continue
        kind=psk hidden=1
        ;;
      *)
        name="" kind=""
        for ((i = 0; i < ${#rows[@]}; i++)); do
          [[ ${rows[i]} == "$choice" ]] && { name=${names[i]} kind=${kinds[i]}; break; }
        done
        [[ -n $name ]] || continue
        ;;
    esac

    case $kind in
      8021x | wep)
        note="\"$name\" needs a sign-in the installer can't do. Use another network, a cable, or a phone sharing its connection."
        continue
        ;;
      open)
        ui_header "Wi-Fi"
        ui_line "Joining $name..." "$UI_DIM"
        timeout 45 iwctl station "$dev" connect "$name" >/dev/null 2>&1 ||
          { note="Couldn't join \"$name\"."; continue; }
        ;;
      psk)
        # A wrong password asks again, empty, as a login prompt does; Esc
        # goes back to the list.
        wrong=0
        while true; do
          ui_header "Wi-Fi"
          if ((wrong)); then
            ui_line "Couldn't join \"$name\". Check the password and try again." "$UI_RED"
            ui_line
          fi
          pass=$(gum input --password --placeholder "" --header "Password for $name") || { name=""; break; }
          [[ -n $pass ]] || continue
          ui_header "Wi-Fi"
          ui_line "Joining $name..." "$UI_DIM"
          if ((hidden)); then
            timeout 45 iwctl --passphrase "$pass" station "$dev" connect-hidden "$name" >/dev/null 2>&1 && break
          else
            timeout 45 iwctl --passphrase "$pass" station "$dev" connect "$name" >/dev/null 2>&1 && break
          fi
          wrong=1
        done
        [[ -n $name ]] || continue
        ;;
    esac

    ui_line "Joined $name. Checking the connection..." "$UI_DIM"
    net_settle && return 0
    note="Joined \"$name\", but the internet can't be reached through it. It may need a sign-in page; use another network, a cable, or a phone."
  done
}

# Online, or the choices that get there.
net_wait() {
  local i tries=15 dev choice
  net_online && return 0
  ui_line "Waiting for the network..." "$UI_DIM"
  # A cable connects within seconds of its link coming up. Without one there
  # is nothing to wait for but a slow start of the network services.
  net_wired_link || tries=3
  for ((i = 0; i < tries; i++)); do
    net_online && return 0
    sleep 2
  done
  type -P gum >/dev/null || return 1
  while ! net_online; do
    ui_header "karchy installer"
    ui_line "No network connection." "$UI_RED$UI_BOLD"
    ui_line
    ui_line "The installer downloads karchy's packages. Join a Wi-Fi network, or plug"
    ui_line "in a cable or a phone that shares its connection over USB."
    ui_line
    if dev=$(net_wifi_device); then
      choice=$(gum choose "Connect to Wi-Fi" "Try again" "Open a shell") || return 1
    else
      ui_line "No Wi-Fi device was found in this computer." "$UI_DIM"
      ui_line
      choice=$(gum choose "Try again" "Open a shell") || return 1
    fi
    case $choice in
      "Connect to Wi-Fi") net_wifi_connect "$dev" || true ;;
      "Try again") ;;
      *) return 1 ;;
    esac
  done
}

# The live system's pacman keyring, which the installer adds keys to. On the
# Arch and karchy ISOs pacman-init.service makes it, ordered after the clock
# is set from the network (time-sync.target): so it can't be waited for
# before there is a network, and with a network whose time servers don't
# answer it would never start. After a minute it is started with the clock
# as it is.
net_keyring_ready() {
  systemctl cat pacman-init.service >/dev/null 2>&1 || return 0
  systemctl is-active --quiet pacman-init.service && return 0
  ui_line "Preparing the package keys..." "$UI_DIM"
  timeout 60 systemctl start pacman-init.service 2>/dev/null && return 0
  log "the clock was not set from the network within a minute; making the package keyring with the clock as it is"
  # The waiting start job goes first, or the new one would wait with it.
  systemctl stop pacman-init.service 2>/dev/null || true
  systemctl start etc-pacman.d-gnupg.mount 2>/dev/null || true
  systemctl start --job-mode=ignore-dependencies pacman-init.service
}
