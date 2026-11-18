# shellcheck shell=bash
# Base system: repositories, pacstrap and system configuration in the target.
# Sourced by install/karchy-install.

KARCHY_OMARCHY_KEY="40DFB630FF42BCFFB047046CF0134EE680CAC571"
KARCHY_CACHYOS_KEY="882DCFE48E2051D48E2562ABF3B607488DB35A47"
# karchy's own packages (D-51): one repository per release channel (D-61),
# at $KARCHY_REPO_SERVER/repo-<channel>. A VM test points this at a local
# build: tools/vm repo serves packaging/build's out/ folder to the guest.
KARCHY_REPO_SERVER=${KARCHY_REPO_SERVER:-https://github.com/Nulifyer/karchy/releases/download}
KARCHY_REPO_SIGLEVEL=${KARCHY_REPO_SIGLEVEL:-Required}

# CachyOS builds its packages again for newer CPUs (user 2026-11-16, revising
# D-45): x86-64-v3, x86-64-v4, and Zen 4/5. Its tuned repositories go before
# its generic one, picked the way CachyOS's own installer picks them. An
# unattended config can set KARCHY_CACHYOS_LEVEL=generic to skip them.
cachyos_level() {
  if [[ -n ${KARCHY_CACHYOS_LEVEL:-} ]]; then
    echo "$KARCHY_CACHYOS_LEVEL"
    return
  fi
  local isa family
  isa=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null)
  if grep -q 'x86-64-v4 (supported, searched)' <<<"$isa"; then
    # Zen 4 and Zen 5 are AMD family 0x19 with AVX-512 (v4 says it has it)
    # and family 0x1a.
    family=$(awk -F': ' '/^cpu family/ { print $2; exit }' /proc/cpuinfo)
    if grep -q '^vendor_id.*AuthenticAMD' /proc/cpuinfo && [[ $family == 25 || $family == 26 ]]; then
      echo znver4
    else
      echo v4
    fi
  elif grep -q 'x86-64-v3 (supported, searched)' <<<"$isa"; then
    echo v3
  else
    echo generic
  fi
}

# The pacman.conf lines for a level: repositories and the architectures their
# packages carry (stock pacman needs those listed; CachyOS's also reads them).
cachyos_tuned_repos() {
  local level="$1" suffix mirrorlist arches
  case "$level" in
    v3) suffix=v3 mirrorlist=cachyos-v3-mirrorlist arches="x86_64 x86_64_v3" ;;
    v4) suffix=v4 mirrorlist=cachyos-v4-mirrorlist arches="x86_64 x86_64_v3 x86_64_v4" ;;
    znver4) suffix=znver4 mirrorlist=cachyos-v4-mirrorlist arches="x86_64 x86_64_v3 x86_64_v4" ;;
    *) return 0 ;;
  esac
  printf '# karchy: CachyOS packages built for this CPU (%s), before the generic ones.
' "$level"
  printf '[cachyos-%s]
Include = /etc/pacman.d/%s

' "$suffix" "$mirrorlist"
  printf '[cachyos-core-%s]
Include = /etc/pacman.d/%s

' "$suffix" "$mirrorlist"
  printf '[cachyos-extra-%s]
Include = /etc/pacman.d/%s

' "$suffix" "$mirrorlist"
  printf '#ARCHITECTURES=%s
' "$arches"
}

# Trust the [omarchy] and [cachyos] signing keys in the live environment and
# add the repositories: [cachyos] before Arch's (D-45), [omarchy] and [karchy]
# after (D-03, D-51).
# pacstrap copies this keyring into the target.
base_repos_live() {
  # Both public keys ship with the installer (packaging/keyring), so a key
  # server being down can't stop the install; it is only the fallback.
  # --lsign-key trusts exactly the fingerprints above, whatever the file holds.
  local keyfile key
  for keyfile in omarchy:"$KARCHY_OMARCHY_KEY":hkps://keys.openpgp.org cachyos:"$KARCHY_CACHYOS_KEY":hkps://keyserver.ubuntu.com; do
    key=${keyfile#*:}
    key=${key%%:*}
    if [[ -f $KARCHY_SRC/packaging/keyring/${keyfile%%:*}.gpg ]]; then
      pacman-key --add "$KARCHY_SRC/packaging/keyring/${keyfile%%:*}.gpg"
    else
      pacman-key --recv-keys "$key" --keyserver "${keyfile#*:*:}"
    fi
    pacman-key --lsign-key "$key"
  done
  # karchy's own signing key comes with the installer (D-61), no keyserver.
  local keyring="$KARCHY_SRC/packaging/keyring" fpr
  if [[ -f $keyring/karchy.gpg ]]; then
    pacman-key --add "$keyring/karchy.gpg"
    while IFS=: read -r fpr _; do
      [[ -n $fpr ]] && pacman-key --lsign-key "$fpr"
    done <"$keyring/karchy-trusted"
  fi

  # The keys and the mirror list above and below only start things off: once
  # the repositories answer, the projects' own packages replace them (further
  # down), as on an installed machine.
  #
  # Bootstrap mirrors: CachyOS's own list, shipped with the installer
  # (install/cachyos-mirrorlist). All of its mirrors, because a mirror can
  # list a package in its database before it holds the file, and pacman then
  # tries the next server.
  # The servers of the mirror list $1, with $arch spelled out as the
  # directory $2.
  cachyos_mirrors() {
    local line
    while IFS= read -r line; do
      [[ $line == "Server = "* ]] && printf '%s\n' "${line//\$arch/$2}"
    done <"$1"
  }
  # The tuned repos' lists, with the architecture spelled out: the packaged
  # lists use $arch_v3/$arch_v4, which only CachyOS's pacman expands.
  cachyos_tuned_mirrors() {
    case "$(cachyos_level)" in
      v3) cachyos_mirrors "$1" x86_64_v3 >/etc/pacman.d/cachyos-v3-mirrorlist ;;
      v4 | znver4) cachyos_mirrors "$1" x86_64_v4 >/etc/pacman.d/cachyos-v4-mirrorlist ;;
    esac
  }
  if [[ ! -f /etc/pacman.d/cachyos-mirrorlist ]]; then
    # shellcheck disable=SC2016  # pacman expands $arch and $repo
    cachyos_mirrors "$KARCHY_SRC/install/cachyos-mirrorlist" '$arch' >/etc/pacman.d/cachyos-mirrorlist
  fi
  cachyos_tuned_mirrors /etc/pacman.d/cachyos-mirrorlist
  base_add_repos /etc/pacman.conf
  pacman -Sy
  # Arch's keyring first, so an install medium built months ago knows the
  # packagers who signed today's packages. Then CachyOS's and Omarchy's
  # keyrings and CachyOS's mirror list, which takes the bootstrap list's
  # place; the tuned repos' lists are written again from it.
  pacman -S --noconfirm --needed archlinux-keyring
  pacman -S --noconfirm --needed --overwrite etc/pacman.d/cachyos-mirrorlist \
    cachyos-keyring omarchy-keyring cachyos-mirrorlist
  cachyos_tuned_mirrors /etc/pacman.d/cachyos-mirrorlist
  # karchy-disk-fstab (data disks) reads lsblk's JSON with jq.
  pacman -S --noconfirm --needed jq
}

base_packages() {
  local -a packages
  mapfile -t packages < <(grep -vE '^\s*(#|$)' "$KARCHY_SRC/install/packages/base.txt")
  case "$(cpu_vendor)" in
    AuthenticAMD) packages+=(amd-ucode) ;;
    GenuineIntel) packages+=(intel-ucode) ;;
  esac
  printf '%s\n' "${packages[@]}"
}

base_pacstrap() {
  local -a packages
  mapfile -t packages < <(base_packages)
  pacstrap "$KARCHY_MNT" --noconfirm "${packages[@]}"
}

base_fstab() {
  # Mount subvolumes by path only: a subvolid= pin breaks snapshot rollbacks.
  genfstab -U "$KARCHY_MNT" | sed -E 's/,?subvolid=[0-9]+//' >"$KARCHY_MNT/etc/fstab"
}

base_repos_target() {
  base_add_repos "$KARCHY_MNT/etc/pacman.conf"
  base_noextract "$KARCHY_MNT/etc/pacman.conf"
}

# Two Thunar files that don't work on karchy, never installed (user
# 2026-11-15): the "Set as wallpaper" plugin, which sets Xfce's desktop
# (karchy's own Set as Wallpaper sets the theme's background), and Send To ›
# Mail Recipient, which needs a mail app karchy doesn't set up. Thunar has no
# setting to hide either. Runs before the desktop packages are installed;
# pacman keeps the line through updates, since pacman.conf is a backup file.
KARCHY_NOEXTRACT=(
  usr/lib/thunarx-3/thunar-wallpaper-plugin.so
  usr/share/Thunar/sendto/thunar-sendto-email.desktop
)
base_noextract() {
  local conf="$1" line="NoExtract   = ${KARCHY_NOEXTRACT[*]}"
  grep -qF "$line" "$conf" && return
  # Fill in the stock empty line, or add one under [options] (pacman adds up
  # repeated NoExtract lines).
  if grep -qE '^#NoExtract *=$' "$conf"; then
    awk -v line="$line" '/^#NoExtract *=$/ && !done { print line; done = 1; next } { print }' \
      "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
  else
    awk -v line="$line" '{ print } /^\[options\]$/ && !done { print line; done = 1 }' \
      "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
  fi
  grep -qF "$line" "$conf"
}

# Insert [cachyos] just before Arch's [core]; append [omarchy] and [karchy].
# Also tune pacman's options: 10 parallel downloads (Arch ships 5), color,
# the detailed package table and the candy progress bar.
base_add_repos() {
  local conf="$1"
  sed -i -E \
    -e 's/^#?Color$/Color\nILoveCandy/' \
    -e 's/^#?VerbosePkgLists$/VerbosePkgLists/' \
    -e 's/^#?ParallelDownloads *=.*/ParallelDownloads = 10/' "$conf"
  # Applied once: a second run would add a second ILoveCandy.
  awk '!(/^ILoveCandy$/ && seen++)' "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
  if ! grep -q '^\[cachyos\]' "$conf"; then
    local tuned arches
    tuned=$(cachyos_tuned_repos "$(cachyos_level)")
    arches=$(sed -n 's/^#ARCHITECTURES=//p' <<<"$tuned")
    { grep -v '^#ARCHITECTURES=' <<<"$tuned"; cat "$KARCHY_SRC/system/pacman/repo-cachyos.conf"; } >"$conf.cachyos"
    awk -v block="$conf.cachyos" '
      /^\[core\]/ && !done { while ((getline line < block) > 0) print line; done = 1 }
      { print }
    ' "$conf" >"$conf.karchy" && mv "$conf.karchy" "$conf"
    rm -f "$conf.cachyos"
    if [[ -n $arches ]]; then
      sed -i -E "s/^#?Architecture *=.*/Architecture = $arches/" "$conf"
    fi
  fi
  if ! grep -q '^\[omarchy\]' "$conf"; then
    cat "$KARCHY_SRC/system/pacman/repo-omarchy.conf" >>"$conf"
  fi
  # The channel's server lives in its own file, which karchy-channel rewrites.
  local server_file
  server_file="$(dirname "$conf")/pacman.d/karchy-server"
  printf '# karchy release channel (D-61). Change it with: karchy channel set <stable|rc|nightly>\n# channel=%s\nServer = %s/repo-%s\n' \
    "$KARCHY_CHANNEL" "$KARCHY_REPO_SERVER" "$KARCHY_CHANNEL" >"$server_file"
  if ! grep -q '^\[karchy\]' "$conf"; then
    printf '\n# karchy (D-51): karchy'"'"'s own packages, built from Nulifyer/karchy.\n[karchy]\nSigLevel = %s\nInclude = /etc/pacman.d/karchy-server\n' \
      "$KARCHY_REPO_SIGLEVEL" >>"$conf"
  fi
  grep -q '^\[cachyos\]' "$conf" && grep -q '^\[omarchy\]' "$conf" && grep -q '^\[karchy\]' "$conf"
}

base_locale() {
  sed -i 's/^#\(en_US.UTF-8 UTF-8\)/\1/' "$KARCHY_MNT/etc/locale.gen"
  in_target locale-gen
  echo "LANG=en_US.UTF-8" >"$KARCHY_MNT/etc/locale.conf"
  # The desktop reads XKBLAYOUT from the same file (default/hypr/keyboard.lua),
  # so write the layout that matches the console keymap, from the table
  # localectl uses; otherwise the disk password typed at boot in one layout
  # fails at the lock screen in US.
  local xlayout="" xvariant=""
  read -r xlayout xvariant < <(awk -v k="$KARCHY_KEYMAP" '$1 == k { print $2, $4; exit }' \
    "$KARCHY_MNT/usr/share/systemd/kbd-model-map" 2>/dev/null) || true
  {
    echo "KEYMAP=$KARCHY_KEYMAP"
    if [[ -n $xlayout ]]; then
      echo "XKBLAYOUT=$xlayout"
      [[ $xvariant == - || -z $xvariant ]] || echo "XKBVARIANT=$xvariant"
    fi
  } >"$KARCHY_MNT/etc/vconsole.conf"
  in_target ln -sf "/usr/share/zoneinfo/$KARCHY_TIMEZONE" /etc/localtime
  in_target hwclock --systohc
  echo "$KARCHY_HOSTNAME" >"$KARCHY_MNT/etc/hostname"
  printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 %s\n' "$KARCHY_HOSTNAME" >"$KARCHY_MNT/etc/hosts"
}

base_user() {
  in_target useradd --create-home --groups wheel --shell /usr/bin/fish "$KARCHY_USER"
  printf '%s:%s\n' "$KARCHY_USER" "$KARCHY_PASSWORD" | in_target chpasswd
  in_target passwd --lock root
  # The sudo policy comes from karchy-settings, pacstrapped with the base.
  in_target visudo -cf /etc/sudoers.d/karchy
  # The login keyring's key (D-57), before any snapshot is taken. A key saved
  # with karchy-keyring-key export (KARCHY_KEYRING_KEY_FILE in an unattended
  # config) is used instead of a new one, so a restored home's keyring opens.
  local uid key=""
  uid=$(in_target id -u "$KARCHY_USER")
  if [[ -n ${KARCHY_KEYRING_KEY_FILE:-} ]]; then
    key=$(head -n 1 "$KARCHY_KEYRING_KEY_FILE" | tr -d '[:space:]')
    [[ $key =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "$KARCHY_KEYRING_KEY_FILE doesn't hold a keyring key (karchy-keyring-key export writes one)"
    install -d -m 0700 "$KARCHY_MNT/etc/credstore"
    printf '%s' "$key" | install -m 0600 /dev/stdin "$KARCHY_MNT/etc/credstore/karchy.keyring.$uid"
  fi
  in_target /usr/lib/karchy/keyring-key "$uid"
}

# Internal data disks already in the machine get mounts at /mnt/<label> (D-24),
# by the same rules the login check uses for disks added later.
base_data_disks() {
  local uid gid device fstype mount line
  uid=$(in_target id -u "$KARCHY_USER")
  gid=$(in_target id -g "$KARCHY_USER")
  while IFS=$'\t' read -r device _ fstype _ mount; do
    line=$(KARCHY_FSTAB="$KARCHY_MNT/etc/fstab" "$KARCHY_SRC/bin/karchy-disk-fstab" line "$device" "$uid" "$gid")
    mkdir -p "$KARCHY_MNT$mount"
    echo "$line" >>"$KARCHY_MNT/etc/fstab"
    log "data disk $device mounts at $mount"
    # A btrfs data disk gets the same monthly scrub as the system disk; NTFS
    # gets ntfsfix, the only way to clear a dirty flag Windows left.
    case "$fstype" in
      btrfs) in_target systemctl enable "btrfs-scrub@$(systemd-escape -p "$mount").timer" ;;
      ntfs) in_target pacman -S --needed --noconfirm ntfsprogs ;;
    esac
  done < <(KARCHY_FSTAB="$KARCHY_MNT/etc/fstab" "$KARCHY_SRC/bin/karchy-disk-fstab" list)
}

# Non-secret install answers, for setup steps that run later. System files
# (mkinitcpio, /tmp, the snapper template) come from karchy-settings.
base_install_conf() {
  install -d -m 0755 "$KARCHY_MNT/etc/karchy"
  {
    printf 'KARCHY_USER=%q\n' "$KARCHY_USER"
    printf 'KARCHY_BEES=%q\n' "$KARCHY_BEES"
    printf 'KARCHY_SECUREBOOT=%q\n' "$KARCHY_SECUREBOOT"
    printf 'KARCHY_CHANNEL=%q\n' "$KARCHY_CHANNEL"
    printf 'KARCHY_INSTALLED=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$KARCHY_MNT/etc/karchy/install.conf"
}

# Limine with systemd-based unlock (D-12): rd.luks.uuid + sd-encrypt, zswap on (D-10).
base_bootloader() {
  local cmdline resume_uuid resume_offset
  # Hibernation resumes from the swap file: the btrfs filesystem's UUID and the
  # file's offset inside it, read by the systemd initramfs (D-32).
  resume_uuid=$(findmnt -no UUID "$KARCHY_MNT")
  resume_offset=$(btrfs inspect-internal map-swapfile -r "$KARCHY_MNT/swap/swapfile")
  # A quiet console (D-12: no Plymouth, the disk password is asked in text):
  # without these, kernel and unit messages scroll over the password prompt.
  # quiet hides unit status, loglevel=3 kernel messages below "critical"
  # (quiet alone still prints kernel errors, which firmware and drivers
  # produce on a healthy boot), and systemd.show_status=auto brings status
  # back when a unit fails or a job has waited 25 s (a missing disk), so a
  # boot that hangs says what it waits for. Every entry gets this line: the
  # LTS kernel and the snapshots (limine-snapper-sync copies it).
  cmdline="quiet loglevel=3 systemd.show_status=auto"
  cmdline+=" rw rootflags=subvol=/@ rd.luks.uuid=$KARCHY_LUKS_UUID rd.luks.options=discard"
  cmdline+=" root=/dev/mapper/$KARCHY_ROOT_MAPPER zswap.enabled=1 zswap.compressor=zstd"
  cmdline+=" resume=UUID=$resume_uuid resume_offset=$resume_offset"
  cat >"$KARCHY_MNT/etc/default/limine" <<EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]="$cmdline"
BOOT_ORDER="*, *lts, Snapshots"
EOF
  # The firmware's fallback copy of Limine (EFI/BOOT/BOOTX64.EFI) is kept
  # current by limine-update, except under Secure Boot, where karchy's own
  # hook keeps it identical to the signed binary instead.
  [[ $KARCHY_SECUREBOOT == "yes" ]] || echo 'ENABLE_LIMINE_FALLBACK=yes' >>"$KARCHY_MNT/etc/default/limine"
  in_target limine-install --fallback
  in_target limine-update
}

base_snapper() {
  in_target snapper --no-dbus -c root create-config --template karchy /
  # Snapshots from a full upgrade (karchy update) and from kernel or boot
  # changes are marked important, so the 5 plain ones that app installs
  # make don't push the pre-update snapshot out (D-09, user 2026-11-16).
  # snap-pac.ini is snap-pac's backup file, so pacman keeps this.
  cat >"$KARCHY_MNT/etc/snap-pac.ini" <<'SNAPPAC'
[root]
important_commands = ["pacman -Syu", "pacman -Syu --noconfirm"]
important_packages = ["linux-cachyos", "linux-cachyos-lts", "limine", "systemd", "mkinitcpio", "karchy", "karchy-settings"]
SNAPPAC
}

base_services() {
  in_target systemctl enable NetworkManager.service systemd-resolved.service systemd-timesyncd.service \
    fstrim.timer snapper-cleanup.timer limine-snapper-sync.service btrfs-scrub@-.timer
}

# Secure Boot (D-31), chosen in the form when the firmware is in Setup Mode.
# The installer's last step, and enrolling is its last action: until the keys
# are enrolled the firmware stays in Setup Mode, so a failure anywhere before
# leaves a machine that still boots (and boots the install ISO to retry).
# karchy-secureboot (karchy) does the enrolling.
# sbctl's keys are enrolled with Microsoft's (GPU option ROMs, dual boot).
# Kernels are not signed: Limine checks each file's BLAKE2 hash from
# limine.conf, and the config's own hash is enrolled into the signed Limine
# binary. limine's hooks re-enroll and re-sign after every kernel, initramfs
# or snapshot change; karchy-settings' 95-karchy-limine-fallback hook keeps the
# firmware's fallback copy identical to the enrolled, signed binary.
base_secureboot() {
  [[ $KARCHY_SECUREBOOT == "yes" ]] || return 0
  in_target pacman -S --needed --noconfirm sbctl
  in_target sbctl create-keys
  printf 'ENABLE_VERIFICATION=yes\nENABLE_ENROLL_LIMINE_CONFIG=yes\n' >>"$KARCHY_MNT/etc/default/limine"
  # Signs with the new keys; karchy's hook fails it unless both binaries carry
  # limine.conf's hash and are signed.
  in_target limine-update
  local efi
  for efi in /boot/EFI/limine/limine_x64.efi /boot/EFI/BOOT/BOOTX64.EFI; do
    in_target sbctl verify "$efi" | grep -q 'is signed' || die "$efi is not signed"
  done
  in_target karchy-secureboot enroll
}

base_git_identity() {
  [[ -n $KARCHY_FULL_NAME || -n $KARCHY_EMAIL ]] || return 0
  [[ -n $KARCHY_FULL_NAME ]] && as_user git config --global user.name "$KARCHY_FULL_NAME"
  [[ -n $KARCHY_EMAIL ]] && as_user git config --global user.email "$KARCHY_EMAIL"
  return 0
}

# arch-chroot bind-mounts resolv.conf while it runs, so link it last, from outside.
base_resolved_link() {
  ln -sf /run/systemd/resolve/stub-resolv.conf "$KARCHY_MNT/etc/resolv.conf"
}
