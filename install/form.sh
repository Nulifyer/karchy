# shellcheck shell=bash disable=SC2034  # sets KARCHY_* variables used by the other install files
# The installer form: collects every answer up front, then the install runs
# unattended. Sourced by install/karchy-install. Writes KARCHY_* variables.

# Esc or Ctrl-C at a question that asks for an answer ends the installer
# before anything changes; at a yes/no question Esc means No (gum can't tell
# them apart), and Ctrl-C ends it. The final "Erase and install" defaults to No.
form_cancel() {
  ui_line
  ui_line "Install cancelled. Nothing was changed; run karchy-install to start again."
  exit 1
}

# What went wrong with an answer, above the question when it is asked again.
form_retry() {
  ui_line "$1" "$UI_RED"
}

# A yes/no question: 0 yes, 1 no. gum exits 130 on Ctrl-C, which cancels.
form_yes_no() {
  local code=0
  gum confirm "$@" || code=$?
  ((code == 130)) && form_cancel
  return "$code"
}

# Pick one line from stdin with gum filter, again until something matches.
# Runs in a subshell, so a cancel returns 1 and the caller cancels.
form_pick() {
  local header="$1" value="$2" list choice
  list=$(cat)
  while true; do
    choice=$(gum filter --header "$header" --value "$value" <<<"$list") || return 1
    [[ -n $choice ]] && { printf '%s' "$choice"; return; }
    form_retry "Pick one from the list (type to narrow it down)."
  done
}

form_require_gum() {
  type -P gum >/dev/null && return
  log "installing gum for the installer form"
  pacman -Sy --noconfirm --needed gum >>"$KARCHY_INSTALL_LOG" 2>&1 || die "could not install gum"
}

form_disk() {
  # Never offer the USB stick the installer booted from.
  local boot_disk="" boot_part
  boot_part=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
  if [[ -n $boot_part ]]; then
    boot_disk=$(lsblk -npo PKNAME "$boot_part" 2>/dev/null | head -n 1)
  fi
  local -a rows
  mapfile -t rows < <(lsblk -dpno NAME,SIZE,MODEL,TYPE |
    awk -v skip="$boot_disk" '$NF == "disk" && $1 != skip { $NF = ""; print }')
  ((${#rows[@]})) || die "no installable disks found"
  local choice
  choice=$(gum choose --header "Install karchy on which disk? It will be erased." "${rows[@]}") || form_cancel
  KARCHY_DISK=$(awk '{ print $1 }' <<<"$choice")

  # What is on it now, so the wrong disk is caught here.
  local line typed
  ui_line "On $KARCHY_DISK now:"
  while IFS= read -r line; do
    ui_line "$line" "$UI_DIM"
  done < <(lsblk -o NAME,SIZE,FSTYPE,LABEL "$KARCHY_DISK")
  ui_line
  while true; do
    typed=$(gum input --header "Type $KARCHY_DISK to choose it. Nothing is erased yet." --placeholder "$KARCHY_DISK") || form_cancel
    [[ $typed == "$KARCHY_DISK" ]] && break
    form_retry "That isn't $KARCHY_DISK. Type it exactly, or press Esc to stop."
  done
  form_screen
}

# One question for disk encryption and login together (D-130), so the plain
# answer is the safe one: Encrypted is selected already. Without encryption
# the computer still asks for the password at every boot: no install starts
# without one (user, 2026-11-19).
FORM_PROTECT_ENCRYPTED="Encrypted: the disk password at boot also logs you in"
FORM_PROTECT_LOGIN="Not encrypted: a login screen asks for your password at boot"

form_protection() {
  local choice
  while true; do
    choice=$(gum choose --header "Disk encryption" --selected "$FORM_PROTECT_ENCRYPTED" \
      "$FORM_PROTECT_ENCRYPTED" "$FORM_PROTECT_LOGIN") || form_cancel
    if [[ $choice == "$FORM_PROTECT_ENCRYPTED" ]]; then
      KARCHY_ENCRYPT=encrypted
      return
    fi
    ui_line "Without encryption, anyone who has this computer or its disk can read" "$UI_RED"
    ui_line "your files. The login screen only keeps people out of the desktop." "$UI_RED"
    ui_line
    if form_yes_no --default=false --affirmative "Don't encrypt" --negative "Choose again" \
      "Install without disk encryption?"; then
      KARCHY_ENCRYPT=login
      return
    fi
    form_screen
  done
}

# How a choice reads in the answers and in the summary.
form_protection_label() {
  case "$KARCHY_ENCRYPT" in
    encrypted) echo "encrypted; the disk password also logs you in" ;;
    login) echo "not encrypted; login screen at boot" ;;
  esac
}

# The other internal disks of this computer: every disk that is not
# removable, not the one karchy goes on and not the install media.
form_other_disks_list() {
  local boot_disk="" boot_part
  boot_part=$(findmnt -no SOURCE /run/archiso/bootmnt 2>/dev/null || true)
  [[ -z $boot_part ]] || boot_disk=$(lsblk -npo PKNAME "$boot_part" 2>/dev/null | head -n 1)
  lsblk -dpnro NAME,TYPE,RM,HOTPLUG,RO |
    awk -v skip="$boot_disk" -v target="$KARCHY_DISK" \
      '$2 == "disk" && $3 == 0 && $4 == 0 && $5 == 0 && $1 != skip && $1 != target && $1 !~ /^\/dev\/(zram|loop|ram)/ { print $1 }'
}

# "Samsung SSD 870 1.8T", or the size alone for a disk without a model name.
form_disk_name() {
  local size model
  size=$(lsblk -dno SIZE "$1" 2>/dev/null | tr -d ' ') || true
  model=$(lsblk -dno MODEL "$1" 2>/dev/null | sed 's/[[:space:]]*$//') || true
  echo "${model:+$model }$size"
}

# Offer to erase and encrypt each other internal disk (D-132). Keeping it is
# the selected answer: it is then mounted with its files as they are (D-24).
# Asked only with an encrypted system disk, which is where the key that opens
# these disks at boot is kept.
form_other_disks() {
  local -a disks
  local disk name line typed keep erase choice
  KARCHY_ENCRYPT_DISKS=""
  FORM_OTHER_DISKS=""
  mapfile -t disks < <(form_other_disks_list)
  ((${#disks[@]})) || return 0
  if ! install_encrypted; then
    FORM_OTHER_DISKS="kept as they are (encrypting them needs an encrypted system disk)"
    return 0
  fi
  for disk in "${disks[@]}"; do
    name=$(form_disk_name "$disk")
    ui_line "Another internal disk: $disk ($name)"
    while IFS= read -r line; do
      ui_line "$line" "$UI_DIM"
    done < <(lsblk -o NAME,SIZE,FSTYPE,LABEL "$disk")
    ui_line
    keep="Keep it as it is: its files stay, and it is mounted under /mnt"
    erase="Erase and encrypt it: erases everything on $disk ($name)"
    choice=$(gum choose --header "What should happen to $disk?" --selected "$keep" "$keep" "$erase") || form_cancel
    if [[ $choice == "$erase" ]]; then
      ui_line "It will open at boot with the system disk, with the same password." "$UI_DIM"
      while true; do
        typed=$(gum input --header "Type $disk to erase and encrypt it, or nothing to keep it. Nothing is erased yet." --placeholder "$disk") || form_cancel
        [[ -z $typed || $typed == "$disk" ]] && break
        form_retry "That isn't $disk. Type it exactly, or leave it empty to keep the disk."
      done
      [[ -z $typed ]] || KARCHY_ENCRYPT_DISKS+="${KARCHY_ENCRYPT_DISKS:+ }$disk"
    fi
    FORM_OTHER_DISKS="kept as they are"
    [[ -z $KARCHY_ENCRYPT_DISKS ]] || FORM_OTHER_DISKS="erase and encrypt $KARCHY_ENCRYPT_DISKS"
    form_screen
  done
}

form_password() {
  local first second header="Password (logs you in, and is asked for by sudo)"
  ! install_encrypted || header="Password (unlocks the disk and logs you in)"
  while true; do
    first=$(gum input --password --header "$header") || form_cancel
    second=$(gum input --password --header "Confirm password") || form_cancel
    if [[ -z $first ]]; then
      form_retry "The password can't be empty."
    elif [[ $first != "$second" ]]; then
      form_retry "The passwords don't match."
    else
      break
    fi
  done
  KARCHY_PASSWORD="$first"
}

# The form's screen: the header and the answers given so far. Drawn again
# after each answer, so a question never scrolls the earlier ones away and a
# retry message doesn't outlive its question.
form_screen() {
  ui_header "Install karchy" 14
  [[ $KARCHY_UI == tui ]] || return 0
  ui_line "Esc stops the installer. Nothing is erased until you confirm at the end." "$UI_DIM"
  ui_line
  [[ -z ${KARCHY_KEYMAP:-} ]] || ui_field "Keyboard" "$KARCHY_KEYMAP"
  [[ -z ${KARCHY_DISK:-} ]] || ui_field "Disk" "$KARCHY_DISK"
  [[ -z ${KARCHY_ENCRYPT:-} ]] || ui_field "Protection" "$(form_protection_label)"
  [[ -z ${FORM_OTHER_DISKS:-} ]] || ui_field "Other disks" "$FORM_OTHER_DISKS"
  [[ -z ${KARCHY_USER:-} ]] || ui_field "User" "$KARCHY_USER"
  [[ -z ${KARCHY_PASSWORD:-} ]] || ui_field "Password" "set"
  [[ -z ${KARCHY_HOSTNAME:-} ]] || ui_field "Computer" "$KARCHY_HOSTNAME"
  [[ -z ${KARCHY_TIMEZONE:-} ]] || ui_field "Timezone" "$KARCHY_TIMEZONE"
  [[ -z ${KARCHY_CHANNEL:-} ]] || ui_field "Updates" "$KARCHY_CHANNEL channel"
  [[ -z ${KARCHY_KEYMAP:-} ]] || ui_line
}

form_run() {
  form_require_gum
  # An unattended config's variables don't belong in a form's first screen.
  unset KARCHY_KEYMAP KARCHY_DISK KARCHY_USER KARCHY_PASSWORD KARCHY_HOSTNAME KARCHY_TIMEZONE KARCHY_CHANNEL
  unset KARCHY_ENCRYPT KARCHY_ENCRYPT_DISKS FORM_OTHER_DISKS
  form_screen

  # The layout first: every answer after it, the disk's name and the password
  # that unlocks the disk at boot, is typed with it.
  KARCHY_KEYMAP=$(localectl list-keymaps | form_pick "Keyboard layout" "us") || form_cancel
  loadkeys "$KARCHY_KEYMAP" 2>/dev/null || true
  form_screen
  form_disk
  form_protection
  form_screen
  form_other_disks
  form_screen

  while true; do
    KARCHY_USER=$(gum input --header "Username" --placeholder "lowercase letters, digits, - or _") || form_cancel
    if ! [[ $KARCHY_USER =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
      form_retry "Use lowercase letters, digits, - or _, starting with a letter."
    elif form_reserved_user "$KARCHY_USER"; then
      form_retry "$KARCHY_USER is a name the system uses itself. Pick another."
    else
      break
    fi
  done
  form_screen

  form_password
  form_screen
  KARCHY_FULL_NAME=$(gum input --header "Full name (for git, optional)") || form_cancel
  while true; do
    KARCHY_EMAIL=$(gum input --header "Email (for git, optional)" --value "${KARCHY_EMAIL:-}") || form_cancel
    [[ -z $KARCHY_EMAIL || $KARCHY_EMAIL =~ ^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$ ]] && break
    form_retry "That doesn't look like an email address (name@example.com). Leave it empty to skip."
  done

  # The default shows as a placeholder, which typing replaces; a prefilled
  # value would be added to ("karchykarchy"). Only a name that was typed and
  # refused comes back in the field, to be corrected.
  KARCHY_HOSTNAME=""
  while true; do
    KARCHY_HOSTNAME=$(gum input --header "Computer name (Enter keeps karchy)" --placeholder "karchy" \
      --value "$KARCHY_HOSTNAME") || form_cancel
    KARCHY_HOSTNAME=${KARCHY_HOSTNAME:-karchy}
    [[ $KARCHY_HOSTNAME =~ ^[A-Za-z0-9][A-Za-z0-9-]{0,62}$ ]] && break
    form_retry "Use letters, digits and -."
  done
  form_screen

  KARCHY_TIMEZONE=$(timedatectl list-timezones | form_pick "Timezone" "") || form_cancel
  form_screen

  # Only channels with a release: before karchy's first release, stable has
  # none, and installing from it would fail after the disk is erased.
  local -a channels=()
  local channel header="Release channel for karchy's own updates (Settings can change it later)"
  for channel in stable rc nightly; do
    channel_published "$channel" && channels+=("$channel")
  done
  ((${#channels[@]} > 0)) || die "karchy's package repositories at $KARCHY_REPO_SERVER can't be reached; nothing was changed. Check the network and run karchy-install again."
  KARCHY_CHANNEL=$(gum choose --header "$header" --selected "${channels[0]}" "${channels[@]}") || form_cancel
  form_screen

  KARCHY_SECUREBOOT=no
  if firmware_setup_mode; then
    # gum draws its question on one line and cuts it at the screen's edge,
    # so the explanation goes above it, each line within 80 columns.
    ui_line "The firmware is in Setup Mode, so karchy can enroll its own keys" "$UI_DIM"
    ui_line "(with Microsoft's, for GPU firmware and dual boot)." "$UI_DIM"
    if form_yes_no --default=true "Set up Secure Boot?"; then
      KARCHY_SECUREBOOT=yes
    fi
  fi

  KARCHY_BEES=yes
  ui_line "bees finds identical data and stores it once: it saves space with" "$UI_DIM"
  ui_line "worktrees, caches and copied VM disks." "$UI_DIM"
  if ! form_yes_no --default=true "Deduplicate the disk in the background?"; then
    KARCHY_BEES=no
  fi
}

# Names the installed system creates for itself (root, service users, groups),
# which useradd would refuse only after the disk is erased. The live system
# has most of them; the rest come from karchy's packages.
form_reserved_user() {
  local name="$1"
  getent passwd "$name" >/dev/null || getent group "$name" >/dev/null && return 0
  case "$name" in
    root | bin | daemon | mail | ftp | http | nobody | dbus | git | avahi | polkitd | greeter | rtkit | \
      colord | geoclue | usbmux | uuidd | tss | alpm | cups | wheel | adm | sys | users | input | video | \
      audio | storage | optical | lp | kvm | render | docker | libvirt | systemd-* | nm-openvpn | flatpak) return 0 ;;
  esac
  return 1
}

# The last question, after the summary: nothing is written before it.
# Whether a release channel has a published repository (its database).
channel_published() {
  curl -fsL --max-time 20 -o /dev/null "$KARCHY_REPO_SERVER/repo-$1/karchy.db"
}

form_confirm() {
  local what="$KARCHY_DISK"
  [[ -z $KARCHY_ENCRYPT_DISKS ]] || what+=" and ${KARCHY_ENCRYPT_DISKS// / and }"
  form_yes_no --default=false --affirmative "Erase and install" --negative "Stop" \
    "Erase $what and install karchy?" || form_cancel
}

# Load answers from a file instead of asking (unattended installs and tests).
# The file sets the same KARCHY_* variables; it must be readable only by root.
form_load() {
  local file="$1"
  [[ -f $file ]] || die "config file not found: $file"
  # shellcheck source=/dev/null
  source "$file"
  local var
  for var in KARCHY_DISK KARCHY_USER KARCHY_PASSWORD KARCHY_HOSTNAME KARCHY_TIMEZONE; do
    [[ -n ${!var:-} ]] || die "$file does not set $var"
  done
  [[ -b $KARCHY_DISK ]] || die "$file names $KARCHY_DISK as the disk, which is not a disk on this computer (lsblk lists them); nothing was changed."
  KARCHY_KEYMAP=${KARCHY_KEYMAP:-us}
  KARCHY_BEES=${KARCHY_BEES:-yes}
  # The form's question about disk encryption (D-130): encrypted (the
  # default) or login (no encryption, a login screen at boot). There is no
  # install that starts without a password.
  KARCHY_ENCRYPT=${KARCHY_ENCRYPT:-encrypted}
  [[ $KARCHY_ENCRYPT =~ ^(encrypted|login)$ ]] ||
    die "KARCHY_ENCRYPT is \"$KARCHY_ENCRYPT\"; it must be encrypted (the default) or login (no disk encryption, a login screen at boot). karchy has no install that starts without a password; nothing was changed."
  # Other internal disks to erase and encrypt (D-132), separated by spaces.
  KARCHY_ENCRYPT_DISKS=${KARCHY_ENCRYPT_DISKS:-}
  local disk
  for disk in $KARCHY_ENCRYPT_DISKS; do
    install_encrypted || die "KARCHY_ENCRYPT_DISKS needs KARCHY_ENCRYPT=encrypted: the key that opens those disks at boot is kept on the encrypted system disk; nothing was changed."
    [[ -b $disk && $(lsblk -dno TYPE "$disk" 2>/dev/null) == disk ]] || die "$file names $disk in KARCHY_ENCRYPT_DISKS, which is not a disk on this computer (lsblk lists them); nothing was changed."
    [[ $disk != "$KARCHY_DISK" ]] || die "$file names $disk both as the system disk and in KARCHY_ENCRYPT_DISKS; nothing was changed."
  done
  [[ -z ${KARCHY_KEYRING_KEY_FILE:-} || $KARCHY_ENCRYPT != login ]] ||
    die "KARCHY_KEYRING_KEY_FILE can't be used with KARCHY_ENCRYPT=login: there the keyring opens with the login password, not with a key; nothing was changed."
  # dev: a local packaging/build, for VM tests only.
  KARCHY_CHANNEL=${KARCHY_CHANNEL:-stable}
  [[ $KARCHY_CHANNEL =~ ^(stable|rc|nightly|dev)$ ]] || die "KARCHY_CHANNEL must be stable, rc or nightly"
  channel_published "$KARCHY_CHANNEL" ||
    die "The $KARCHY_CHANNEL channel has no release at $KARCHY_REPO_SERVER/repo-$KARCHY_CHANNEL (or it can't be reached); nothing was changed. Set KARCHY_CHANNEL to a channel with a release."
  # auto: set up Secure Boot when the firmware is in Setup Mode.
  KARCHY_SECUREBOOT=${KARCHY_SECUREBOOT:-auto}
  if [[ $KARCHY_SECUREBOOT == "auto" ]]; then
    KARCHY_SECUREBOOT=no
    firmware_setup_mode && KARCHY_SECUREBOOT=yes
  elif [[ $KARCHY_SECUREBOOT == "yes" ]] && ! firmware_setup_mode; then
    die "KARCHY_SECUREBOOT=yes, but the firmware is not in Setup Mode: clear its Secure Boot keys first, or use auto"
  fi
  KARCHY_FULL_NAME=${KARCHY_FULL_NAME:-}
  KARCHY_EMAIL=${KARCHY_EMAIL:-}
}
