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
  # Vulkan for the GPUs present, and Intel's video decode; Mesa's OpenGL and
  # AMD's video decode already come with the desktop. NVIDIA's come with its
  # driver packages above.
  local vendors
  vendors=$(for dev in /sys/bus/pci/devices/*; do
    [[ $(cat "$dev/class" 2>/dev/null) == 0x03* ]] && cat "$dev/vendor"
  done 2>/dev/null | sort -u) || true
  grep -qx 0x1002 <<<"$vendors" && packages+=(vulkan-radeon)
  grep -qx 0x8086 <<<"$vendors" && packages+=(vulkan-intel intel-media-driver)
  # Virtual dependencies have several providers, and pacman picks the first
  # (jack2, which conflicts with pipewire-jack; Afrikaans OCR data). Install
  # karchy's choices first, as dependencies, so the meta-packages find them.
  # -Syu, never -Sy alone: a refresh without the upgrade is a partial upgrade.
  with_mirrors in_target_pacman -Syu --needed --noconfirm --asdeps pipewire-jack qt6-multimedia-ffmpeg tesseract-data-eng
  with_mirrors in_target_pacman -S --needed --noconfirm "${packages[@]}"
  # The apps karchy ships, installed as the user's own (explicitly), so each
  # can be removed in Quick install (D-71). The list is the installed
  # catalog's default entries; the ones karchy needs are dependencies above.
  # An app that is more than one package is installed as its karchy-app-<id>
  # package, which depends on them (D-150); the
  # rule is written the same in bin/karchy-quick-install and
  # system/packages/app-packages (tests/app-packages-rule.sh).
  local -a apps
  local TARGET='if (.packages | length) > 1 or .setup.gpu32 == true then "karchy-app-" + .id else .packages[0] end'
  mapfile -t apps < <(jq -r ".apps[] | select(.default and (.required | not)) | $TARGET" \
    "$KARCHY_MNT/usr/share/karchy/default/karchy/quick-install.json")
  ((${#apps[@]})) || die "The list of apps karchy ships couldn't be read from the installed karchy package."
  with_mirrors in_target_pacman -S --needed --noconfirm "${apps[@]}"
  # The signing key as a package keeps it current (rotation, revocation).
  if in_target pacman -Si karchy-keyring >/dev/null 2>&1; then
    with_mirrors in_target_pacman -S --needed --noconfirm karchy-keyring
  fi
}

# Uncomment pacman.conf's stock [multilib] section; the next pacman -Sy syncs it.
setup_enable_multilib() {
  local conf="$KARCHY_MNT/etc/pacman.conf"
  sed -i '/^#\[multilib\]$/,/^#Include/ s/^#//' "$conf"
  grep -q '^\[multilib\]' "$conf"
}

setup_system_files() {
  # greetd (D-13, D-130). On an encrypted disk: automatic login for the
  # installed user after the disk password, and karchy's login screen after
  # logging out. Without encryption: that screen at every boot. Either way a
  # login at that screen goes through karchy's PAM service, which opens the
  # keyring with the login password or leaves it to its key (D-131, D-142).
  if install_encrypted; then
    sed "s/@USER@/$KARCHY_USER/" "$KARCHY_SRC/system/greetd/config.toml" >"$KARCHY_MNT/etc/greetd/config.toml"
  else
    install -m 0644 "$KARCHY_SRC/system/greetd/config-login.toml" "$KARCHY_MNT/etc/greetd/config.toml"
    # ...and a changed login password changes the keyring's with it. passwd's
    # PAM file is a backup file of shadow, so pacman keeps the line. (On an
    # encrypted install Settings › Users adds it when automatic login goes.)
    grep -q pam_oo7 "$KARCHY_MNT/etc/pam.d/passwd" ||
      echo "password	optional	pam_oo7.so" >>"$KARCHY_MNT/etc/pam.d/passwd"
  fi

  # Resolve .local names (printers, NAS) through avahi before resolved (D-28).
  if ! grep -q mdns_minimal "$KARCHY_MNT/etc/nsswitch.conf"; then
    sed -i 's/^\(hosts:.*\)resolve/\1mdns_minimal [NOTFOUND=return] resolve/' "$KARCHY_MNT/etc/nsswitch.conf"
  fi

  # Ten wrong passwords before a lockout instead of three, matching the lock
  # screen, which counts into the same tally: three lock-screen typos would
  # otherwise lock sudo and password prompts for 10 minutes. The file belongs
  # to pam (a backup file), so pacman keeps this edit.
  sed -i 's/^#\?[[:space:]]*deny[[:space:]]*=.*/deny = 10/' "$KARCHY_MNT/etc/security/faillock.conf"
  # ...and the same 2-minute lockout as the lock screen, instead of 10.
  sed -i 's/^#\?[[:space:]]*unlock_time[[:space:]]*=.*/unlock_time = 120/' "$KARCHY_MNT/etc/security/faillock.conf"

  # The text greeter (agreety, behind karchy's login screen) prints /etc/issue but
  # doesn't expand \S{PRETTY_NAME}, so it showed "Arch Linux{PRETTY_NAME}".
  # A backup file of filesystem, so pacman keeps the edit.
  printf 'karchy \\r (\\l)\n\n' >"$KARCHY_MNT/etc/issue"

  # smartd's warnings go to the desktop instead of to mail nobody reads:
  # karchy's helper records each one and the session shows it as a
  # notification (system/disk-health). DEVICESCAN keeps its default, every
  # check on every ATA, SCSI and NVMe disk. A backup file of smartmontools, so
  # pacman keeps the edit.
  sed -i 's|^DEVICESCAN$|DEVICESCAN -m <nomailer> -M exec /usr/lib/karchy/disk-health|' "$KARCHY_MNT/etc/smartd.conf"
  grep -q '^DEVICESCAN .*-M exec /usr/lib/karchy/disk-health$' "$KARCHY_MNT/etc/smartd.conf" ||
    log "smartd's warnings are not connected to the desktop: /etc/smartd.conf has no plain DEVICESCAN line to change"

  # ufw denies incoming by default; enabling it here starts it at boot (D-15).
  sed -i 's/^ENABLED=no/ENABLED=yes/' "$KARCHY_MNT/etc/ufw/ufw.conf"
  # ufw would set strict reverse-path filtering, which breaks NetworkManager's
  # per-device connectivity checks (karchy-network-dns waits on them) with
  # Wi-Fi and Ethernet up together. systemd's loose default stays. A backup
  # file of ufw, so pacman keeps the edit.
  sed -i 's|^\(net/ipv4/conf/[a-z]*/rp_filter=\)|#\1|' "$KARCHY_MNT/etc/ufw/sysctl.conf"
}

setup_services() {
  # karchy-localsend-firewall closes LocalSend's port at boot, before
  # NetworkManager reopens it on a trusted network (D-33).
  # avahi isn't enabled: karchy-network-privacy starts it on trusted networks.
  # linux-modules-cleanup (kernel-modules-hook): after a kernel update the
  # running kernel's modules are kept so devices plugged in before the restart
  # still work; this removes the kept copy at the next boot.
  in_target systemctl enable greetd.service bluetooth.service karchy-network-privacy.service ufw.service \
    smartd.service paccache.timer systemd-oomd.service karchy-mirrors.timer fwupd-refresh.timer \
    karchy-localsend-firewall.service linux-modules-cleanup.service
  # foot runs as a server so footclient windows open instantly; karchy's own
  # session units lock before suspend and recover a disabled internal monitor;
  # oo7 is the login keyring (D-57).
  in_target systemctl --global enable foot-server.socket karchy-sleep-lock.service \
    karchy-recover-internal-monitor.service oo7-daemon.service karchy-update-check.timer
  if [[ -f $KARCHY_MNT/usr/lib/systemd/system/power-profiles-daemon.service ]]; then
    in_target systemctl enable power-profiles-daemon.service
  fi
  # The 580 legacy driver keeps video memory across sleep only through its
  # own services. From 595 the open driver does it in the kernel and NVIDIA
  # says to leave them off (they force a VT switch around every suspend).
  if in_target pacman -Q nvidia-580xx-utils >/dev/null 2>&1; then
    in_target systemctl enable nvidia-suspend.service nvidia-resume.service
  fi
}

# The user's starting configs came from /etc/skel (karchy-settings) when the
# account was created. What is made rather than copied (the migration marks,
# the agent skills, the default theme applied without a running session)
# comes from the installed karchy's own program, which Settings › Users
# runs for accounts added later.
setup_user() {
  as_user /usr/lib/karchy/user-setup ${KARCHY_THEME:+"$KARCHY_THEME"}
}

# bees (D-86), on unless declined in the form: deduplicates the system's btrfs
# filesystem in the background. karchy-settings ships the service, its limits
# and its options (system/bees), and depends on karchy-bees, karchy's fork
# (D-85), so the installer only enables it and updates can change the rest.
# karchy-laptop holds it to AC power on laptops.
setup_bees() {
  [[ $KARCHY_BEES == "yes" ]] || return 0
  in_target systemctl enable karchy-bees.service
}
