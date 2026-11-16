# shellcheck shell=bash
# Desktop setup: karchy's packages, then what only this machine and user can
# decide. Everything shared comes from the packages (D-54). Sourced by
# install/karchy-install; runs against the target.

setup_packages() {
  local -a packages=(karchy-desktop)
  # Laptops get power profiles (D-32, detected tier).
  if compgen -G "/sys/class/power_supply/BAT*" >/dev/null; then
    packages+=(karchy-laptop)
  fi
  # NVIDIA: the driver follows the GPU generation (detected tier).
  case "$(nvidia_generation)" in
    open) packages+=(karchy-nvidia) ;;
    580xx)
      # nvidia-580xx-utils depends on its 32-bit libraries, from [multilib].
      setup_enable_multilib
      packages+=(karchy-nvidia-580xx)
      ;;
    unsupported)
      log "This NVIDIA GPU (Kepler or older) isn't supported by NVIDIA's current drivers; the open-source nouveau driver runs it."
      ;;
  esac
  # Framework laptops: the vendor's tool for charge limits, firmware and
  # hardware state (`framework_tool`).
  if [[ $(cat /sys/class/dmi/id/sys_vendor 2>/dev/null) == Framework ]]; then
    packages+=(framework-system)
  fi
  if systemd-detect-virt --quiet --vm; then
    packages+=(karchy-vm)
  fi
  # Virtual dependencies have several providers, and pacman picks the first
  # (jack2, which conflicts with pipewire-jack; Afrikaans OCR data). Install
  # karchy's choices first, as dependencies, so the meta-packages find them.
  in_target pacman -Sy --needed --noconfirm --asdeps pipewire-jack qt6-multimedia-ffmpeg tesseract-data-eng
  in_target pacman -S --needed --noconfirm "${packages[@]}"
  # The apps karchy ships, installed as the user's own (explicitly), so each
  # can be removed in Quick install (D-71). The list is the installed
  # catalog's default entries; the ones karchy needs are dependencies above.
  local -a apps
  mapfile -t apps < <(jq -r '.apps[] | select(.default and (.required | not)) | .packages[]' \
    "$KARCHY_MNT/usr/share/karchy/default/karchy/quick-install.json")
  ((${#apps[@]})) || die "The list of apps karchy ships couldn't be read from the installed karchy package."
  in_target pacman -S --needed --noconfirm "${apps[@]}"
  # The signing key as a package keeps it current (rotation, revocation).
  if in_target pacman -Si karchy-keyring >/dev/null 2>&1; then
    in_target pacman -S --needed --noconfirm karchy-keyring
  fi
}

# Uncomment pacman.conf's stock [multilib] section; the next pacman -Sy syncs it.
setup_enable_multilib() {
  local conf="$KARCHY_MNT/etc/pacman.conf"
  sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' "$conf"
  grep -q '^\[multilib\]' "$conf"
}

setup_system_files() {
  # Auto-login for the installed user (D-08).
  sed "s/@USER@/$KARCHY_USER/" "$KARCHY_SRC/system/greetd/config.toml" >"$KARCHY_MNT/etc/greetd/config.toml"

  # Resolve .local names (printers, NAS) through avahi before resolved (D-28).
  if ! grep -q mdns_minimal "$KARCHY_MNT/etc/nsswitch.conf"; then
    sed -i 's/^\(hosts:.*\)resolve/\1mdns_minimal [NOTFOUND=return] resolve/' "$KARCHY_MNT/etc/nsswitch.conf"
  fi

  # Ten wrong passwords before a lockout instead of three, matching the lock
  # screen, which counts into the same tally: three lock-screen typos would
  # otherwise lock sudo and password prompts for 10 minutes. The file belongs
  # to pam (a backup file), so pacman keeps this edit.
  sed -i 's/^#\?[[:space:]]*deny[[:space:]]*=.*/deny = 10/' "$KARCHY_MNT/etc/security/faillock.conf"

  # ufw denies incoming by default; enabling it here starts it at boot (D-15).
  sed -i 's/^ENABLED=no/ENABLED=yes/' "$KARCHY_MNT/etc/ufw/ufw.conf"
}

setup_services() {
  # karchy-localsend-firewall closes LocalSend's port at boot, before
  # NetworkManager reopens it on a trusted network (D-33).
  in_target systemctl enable greetd.service bluetooth.service avahi-daemon.service ufw.service \
    smartd.service paccache.timer systemd-oomd.service karchy-mirrors.timer \
    karchy-localsend-firewall.service
  # foot runs as a server so footclient windows open instantly; karchy's own
  # session units lock before suspend and recover a disabled internal monitor;
  # oo7 is the login keyring (D-57).
  in_target systemctl --global enable foot-server.socket karchy-sleep-lock.service \
    karchy-recover-internal-monitor.service oo7-daemon.service karchy-update-check.timer
  if [[ -f $KARCHY_MNT/usr/lib/systemd/system/power-profiles-daemon.service ]]; then
    in_target systemctl enable power-profiles-daemon.service
  fi
  # NVIDIA keeps video memory across sleep only through its own services,
  # which come with either driver (nvidia-utils or nvidia-580xx-utils).
  if [[ -f $KARCHY_MNT/usr/lib/systemd/system/nvidia-suspend.service ]]; then
    in_target systemctl enable nvidia-suspend.service nvidia-resume.service nvidia-hibernate.service
  fi
}

# The user's starting configs came from /etc/skel (karchy-settings) when the
# account was created. Apply the default theme without a running session, as
# Omarchy does at install.
setup_user() {
  as_user env KARCHY_PATH=/usr/share/karchy KARCHY_SETUP_CONTEXT=install KARCHY_THEME_HEADLESS=1 \
    karchy-theme-set "${KARCHY_THEME:-nulifyer}"
  # shellcheck disable=SC2016  # expanded by the user's shell in the target
  as_user bash -c 'mkdir -p "$HOME/.config/btop/themes" && ln -snf "$HOME/.local/state/karchy/current/theme/btop.theme" "$HOME/.config/btop/themes/current.theme"'
}

# bees (D-39), chosen in the form: deduplicates the system's btrfs filesystem
# in the background through the upstream beesd@ unit (idle CPU and I/O
# priority). karchy-laptop holds it to AC power on laptops.
setup_bees() {
  [[ $KARCHY_BEES == "yes" ]] || return 0
  local uuid
  uuid=$(findmnt -no UUID "$KARCHY_MNT")
  in_target pacman -S --needed --noconfirm bees
  install -d -m 0755 "$KARCHY_MNT/etc/bees"
  printf '# bees for the system filesystem (D-39). DB_SIZE: hash table size in bytes.\nUUID=%s\nDB_SIZE=%s\n' \
    "$uuid" "$((256 * 1024 * 1024))" >"$KARCHY_MNT/etc/bees/$uuid.conf"
  in_target systemctl enable "beesd@$uuid.service"
}
