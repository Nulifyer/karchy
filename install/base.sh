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
  # tries the next server. Last of all, CachyOS's origin, which the mirrors
  # copy from and which is never behind: its list leaves cdn.cachyos.org and
  # mirror.cachyos.org out to spare them, and an install only reaches them
  # when the mirrors before them failed (with_mirrors moves those to the end).
  # The servers of the mirror list $1, with $arch spelled out as the
  # directory $2.
  cachyos_mirrors() {
    local line origin
    while IFS= read -r line; do
      [[ $line == "Server = "* ]] && printf '%s\n' "${line//\$arch/$2}"
    done <"$1"
    for origin in cdn.cachyos.org mirror.cachyos.org; do
      # shellcheck disable=SC2016  # pacman expands $repo
      grep -q "^Server = https://$origin/" "$1" || printf 'Server = https://%s/repo/%s/$repo\n' "$origin" "$2"
    done
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
  with_mirrors pacman -Sy
  # Arch's keyring first, so an install medium built months ago knows the
  # packagers who signed today's packages. Then CachyOS's and Omarchy's
  # keyrings and CachyOS's mirror list, which takes the bootstrap list's
  # place; the tuned repos' lists are written again from it.
  with_mirrors pacman -S --noconfirm --needed archlinux-keyring
  with_mirrors pacman -S --noconfirm --needed --overwrite etc/pacman.d/cachyos-mirrorlist \
    cachyos-keyring omarchy-keyring cachyos-mirrorlist
  # The packaged list, with the origin last again (the live system's copy
  # only; the installed system keeps the package's file as it is).
  # shellcheck disable=SC2016  # pacman expands $arch and $repo
  cachyos_mirrors /etc/pacman.d/cachyos-mirrorlist '$arch' >/etc/pacman.d/cachyos-mirrorlist.karchy
  mv /etc/pacman.d/cachyos-mirrorlist.karchy /etc/pacman.d/cachyos-mirrorlist
  cachyos_tuned_mirrors /etc/pacman.d/cachyos-mirrorlist
  # karchy-disk-fstab (data disks) reads lsblk's JSON with jq.
  with_mirrors pacman -S --noconfirm --needed jq
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

# mkinitcpio's own pacman hook is switched off for this one transaction.
# limine-mkinitcpio-hook replaces it with a hook of the same name in
# /etc/pacman.d/hooks, which builds each kernel's files where Limine reads
# them (/boot/<machine-id>/<kernel>/). pacman takes that folder from the
# system it runs on, never from the target (--hookdir is not relative to
# --root), so pacstrap doesn't see the replacement and mkinitcpio's hook
# would run: it writes a preset for each kernel and puts /boot/vmlinuz-<kernel>
# and /boot/initramfs-<kernel>.img on the ESP, about 85 MB that nothing boots
# and no later update refreshes or removes. Limine's files are built by
# limine-update (base_bootloader), and from then on by the replacement hook.
base_pacstrap() {
  local -a packages
  local hooks
  mapfile -t packages < <(base_packages)
  hooks=$(mktemp -d)
  ln -s /dev/null "$hooks/90-mkinitcpio-install.hook"
  # No snapshots: snapper's config is made later (base_snapper), and the
  # install takes none (in_target_pacman says why). Without this, snap-pac's
  # hook still ran ps, which fails under pacstrap's PID namespace.
  SNAP_PAC_SKIP=y with_mirrors pacstrap "$KARCHY_MNT" --noconfirm --hookdir="$hooks" "${packages[@]}"
  rm -rf "$hooks"
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
    # karchy's monospace font on the console (karchy-settings ships it), in
    # the size that suits this machine's screen; sd-vconsole loads it before
    # the disk-password prompt.
    echo "FONT=$(console_font)"
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
  # The login keyring (D-57, D-131, D-142). It opens with the login password
  # wherever karchy's login screen asks for one (PAM,
  # system/pam.d/karchy-login), and no key is made there: a key would open
  # the keyring for anyone who can read it, which on a plain disk is anyone
  # who has the disk. An install without disk encryption is such a place
  # from the start, and this file says so to whatever would make a key
  # (users-settings below, karchy-keyring-key@.service) and to
  # karchy-keyring-key. It comes before the account. An encrypted install
  # starts with automatic login and a key; Settings › Users writes the file
  # when that is turned off.
  if ! install_encrypted; then
    install -d -m 0755 "$KARCHY_MNT/etc/karchy"
    echo "# karchy: the login keyring opens with the login password (D-131, D-142); no key is kept in /etc/credstore." \
      >"$KARCHY_MNT/etc/karchy/keyring-login-password"
  fi
  # The account, by the owner of what an account is (system/users, from
  # karchy-settings, pacstrapped with the base): an administrator with fish
  # as the shell, a home nobody else opens and, on an encrypted disk (where
  # the computer logs them in by itself), the keyring's key, before any
  # snapshot is taken. Settings › Users makes
  # later accounts the same way. The password goes in on stdin.
  printf '%s\n' "$KARCHY_PASSWORD" | in_target /usr/lib/karchy/users-settings add "$KARCHY_USER" admin
  in_target passwd --lock root
  # The sudo policy comes from karchy-settings too.
  in_target visudo -cf /etc/sudoers.d/karchy
  # A key saved with karchy-keyring-key export (KARCHY_KEYRING_KEY_FILE in an
  # unattended config) takes the new key's place, so a restored home's
  # keyring opens.
  if install_encrypted && [[ -n ${KARCHY_KEYRING_KEY_FILE:-} ]]; then
    local uid key
    uid=$(in_target id -u "$KARCHY_USER")
    key=$(head -n 1 "$KARCHY_KEYRING_KEY_FILE" | tr -d '[:space:]')
    [[ $key =~ ^[A-Za-z0-9+/]{43}=$ ]] || die "$KARCHY_KEYRING_KEY_FILE doesn't hold a keyring key (karchy-keyring-key export writes one)"
    install -d -m 0700 "$KARCHY_MNT/etc/credstore"
    printf '%s' "$key" | install -m 0600 /dev/stdin "$KARCHY_MNT/etc/credstore/karchy.keyring.$uid"
  fi
}

# Internal data disks already in the machine get mounts at /mnt/<label> (D-24),
# by the same rules the login check uses for disks added later. The disks
# just encrypted (disk_data_encrypt) are among them: they are open, and the
# target's crypttab names them.
base_data_disks() {
  local uid gid device fstype mount line
  uid=$(in_target id -u "$KARCHY_USER")
  gid=$(in_target id -g "$KARCHY_USER")
  while IFS=$'\t' read -r device _ fstype _ mount; do
    line=$(KARCHY_FSTAB="$KARCHY_MNT/etc/fstab" KARCHY_CRYPTTAB="$KARCHY_MNT/etc/crypttab" \
      "$KARCHY_SRC/bin/karchy-disk-fstab" line "$device" "$uid" "$gid")
    mkdir -p "$KARCHY_MNT$mount"
    echo "$line" >>"$KARCHY_MNT/etc/fstab"
    log "data disk $device mounts at $mount"
    # A btrfs data disk gets the same monthly scrub as the system disk. (For
    # NTFS, ntfsfix, the only way to clear a dirty flag Windows left, comes
    # with the desktop: ntfsprogs in karchy-desktop.)
    if [[ $fstype == btrfs ]]; then
      in_target systemctl enable "btrfs-scrub@$(systemd-escape -p "$mount").timer"
    fi
  done < <(KARCHY_FSTAB="$KARCHY_MNT/etc/fstab" KARCHY_CRYPTTAB="$KARCHY_MNT/etc/crypttab" \
    "$KARCHY_SRC/bin/karchy-disk-fstab" list)
}

# Non-secret install answers, for setup steps that run later. System files
# (mkinitcpio, /tmp, the snapper template) come from karchy-settings.
base_install_conf() {
  install -d -m 0755 "$KARCHY_MNT/etc/karchy"
  {
    printf 'KARCHY_USER=%q\n' "$KARCHY_USER"
    printf 'KARCHY_BEES=%q\n' "$KARCHY_BEES"
    printf 'KARCHY_ENCRYPT=%q\n' "$KARCHY_ENCRYPT"
    printf 'KARCHY_SECUREBOOT=%q\n' "$KARCHY_SECUREBOOT"
    printf 'KARCHY_CHANNEL=%q\n' "$KARCHY_CHANNEL"
    printf 'KARCHY_INSTALLED=%q\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  } >"$KARCHY_MNT/etc/karchy/install.conf"
}

# Limine (D-12), zswap on (D-10). An encrypted disk is unlocked in the
# initramfs by systemd (rd.luks.uuid + sd-encrypt); a plain one (D-130) has no
# rd.luks.* words, so sd-encrypt has nothing to do and Plymouth asks nothing:
# the splash shows its tiles until the login screen or the desktop.
base_bootloader() {
  local cmdline resume_uuid resume_offset
  # Hibernation resumes from the swap file: the btrfs filesystem's UUID and the
  # file's offset inside it, read by the systemd initramfs (D-32).
  resume_uuid=$(findmnt -no UUID "$KARCHY_MNT")
  resume_offset=$(btrfs inspect-internal map-swapfile -r "$KARCHY_MNT/swap/swapfile")
  # A quiet boot behind the splash (D-122): without these, kernel and unit
  # messages scroll over the text password prompt of a boot without Plymouth.
  # quiet hides unit status, loglevel=3 kernel messages below "critical"
  # (quiet alone still prints kernel errors, which firmware and drivers
  # produce on a healthy boot), and systemd.show_status=auto brings status
  # back when a unit fails or a job has waited 25 s (a missing disk), so a
  # boot that hangs says what it waits for. splash has Plymouth show karchy's
  # theme and ask for the disk password in it. systemd.tty.term.console=dumb
  # keeps systemd from asking the console for its size when it starts: with
  # Plymouth holding the screen the answer sometimes never comes and the boot
  # waits for a key press (Omarchy saw about 1 boot in 10). Every entry gets
  # this line: the LTS kernel and the snapshots (limine-snapper-sync copies
  # it).
  cmdline="quiet splash loglevel=3 systemd.show_status=auto systemd.tty.term.console=dumb"
  cmdline+=" rw rootflags=subvol=/@"
  if install_encrypted; then
    cmdline+=" rd.luks.uuid=$KARCHY_LUKS_UUID rd.luks.options=discard root=$KARCHY_ROOT_DEV"
  else
    cmdline+=" root=UUID=$resume_uuid"
  fi
  cmdline+=" zswap.enabled=1 zswap.compressor=zstd"
  cmdline+=" resume=UUID=$resume_uuid resume_offset=$resume_offset"
  cat >"$KARCHY_MNT/etc/default/limine" <<EOF
ESP_PATH="/boot"
KERNEL_CMDLINE[default]="$cmdline"
BOOT_ORDER="*, *lts, Snapshots"
ENABLE_LIMINE_FALLBACK=yes
TARGET_OS_NAME="karchy"
EOF
  # TARGET_OS_NAME: the menu's top entry reads "karchy", not os-release's
  # "Arch Linux" (limine-snapper-sync finds the entry by its machine ID).
  # ENABLE_LIMINE_FALLBACK: limine-update keeps the firmware's fallback copy
  # of Limine (EFI/BOOT/BOOTX64.EFI) current. Setting up Secure Boot
  # (karchy-secureboot setup, at the end of the install or later) takes the
  # line out again: karchy's own hook then keeps that copy identical to the
  # signed binary.
  # karchy's Plymouth theme, before limine-update builds the first images
  # (the plymouth hook copies the default theme into them).
  in_target plymouth-set-default-theme karchy
  in_target limine-install --fallback
  in_target limine-update
  # karchy's name, colours and font for the menu, above the entries that
  # limine-update just wrote. Decoration: the menu works without it.
  in_target /usr/lib/karchy/limine-brand || echo "limine-brand failed: the boot menu keeps Limine's own look"
  # These are the only kernel files on the ESP (see base_pacstrap), and
  # limine-update carries on when one kernel's build fails: stop here rather
  # than at a first boot with nothing to start.
  local machine_id pkgbase kernel
  machine_id=$(<"$KARCHY_MNT/etc/machine-id")
  for pkgbase in "$KARCHY_MNT"/usr/lib/modules/*/pkgbase; do
    kernel=$(<"$pkgbase")
    [[ -s $KARCHY_MNT/boot/$machine_id/$kernel/vmlinuz && -s $KARCHY_MNT/boot/$machine_id/$kernel/initramfs ]] ||
      die "Limine has no kernel or initramfs for $kernel in /boot/$machine_id/$kernel"
    grep -qF "/$machine_id/$kernel/vmlinuz" "$KARCHY_MNT/boot/limine.conf" ||
      die "limine.conf has no entry for $kernel"
  done
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

# Wi-Fi from the install media. The live system connects with iwd (iwctl, on
# the Arch ISO and the karchy ISO alike); the installed system uses
# NetworkManager, which knows nothing of it, so the first boot would be
# offline on a machine without a cable. iwd keeps one file per network it has
# connected to, named after the network and its security: <name>.psk (WPA2 and
# WPA3 personal), <name>.open, <name>.8021x (enterprise). A live system only
# knows the networks joined in this session, so each becomes a NetworkManager
# profile, root-only like the ones NetworkManager writes. A machine on a
# cable has no such files and nothing happens.
KARCHY_IWD_DIR=${KARCHY_IWD_DIR:-/var/lib/iwd}

base_wifi() {
  local file
  [[ -d $KARCHY_IWD_DIR ]] || return 0
  for file in "$KARCHY_IWD_DIR"/*.*; do
    [[ -f $file ]] || continue
    # A network that can't be carried over is not worth stopping the install.
    wifi_profile "$file" || log "Wi-Fi network in ${file##*/} was not carried over; connect again after the first boot"
  done
  return 0
}

# Write the NetworkManager profile for one iwd network file. The passphrase
# goes from one file to the other and never to the log.
wifi_profile() {
  local file="$1" base type name hex="" ssid="" id i
  local dir="$KARCHY_MNT/etc/NetworkManager/system-connections" dest
  base=${file##*/}
  type=${base##*.}
  name=${base%.*}
  case "$type" in
    psk | open) ;;
    8021x)
      log "Wi-Fi network in $base uses enterprise sign-in (802.1X), which isn't carried over; connect again after the first boot"
      return 0
      ;;
    *)
      echo "skipping $base: not a network type karchy carries over"
      return 0
      ;;
  esac

  # iwd names the file after the network when the name is only letters,
  # digits, spaces, _ and -; otherwise the name is "=" and its bytes in hex.
  if [[ $name == =* ]]; then
    hex=${name#=}
  else
    hex=$(printf '%s' "$name" | od -An -v -tx1 | tr -d ' \n')
  fi
  [[ ${hex,,} =~ ^([0-9a-f]{2}){1,32}$ ]] || return 1
  hex=${hex,,}

  # The network name as bytes ("104;111;109;101;"), the keyfile form that
  # needs no escaping whatever the name holds.
  local bytes="" escaped=""
  for ((i = 0; i < ${#hex}; i += 2)); do
    bytes+="$((16#${hex:i:2}));"
    escaped+="\\x${hex:i:2}"
  done

  # The profile's name: the network's name when it is plain text, else the hex.
  id="Wi-Fi $hex"
  if [[ ! $hex =~ ^(..)*00 ]]; then
    ssid=$(printf '%b' "$escaped")
    if [[ $ssid != *[[:cntrl:]]* ]] && printf '%s' "$ssid" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1; then
      id=$ssid
    fi
  fi

  # The iwd file: the passphrase (or only the key derived from it), and the
  # two settings NetworkManager also has.
  local line group="" key value passphrase="" psk="" hidden="" autoconnect="" secret=""
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%$'\r'}
    if [[ $line =~ ^\[(.+)\]$ ]]; then
      group=${BASH_REMATCH[1]}
      continue
    fi
    [[ $line == *=* && $line != \#* ]] || continue
    key=${line%%=*}
    key=${key//[[:blank:]]/}
    value=${line#*=}
    value=${value#"${value%%[![:blank:]]*}"}
    case "$group/$key" in
      Security/Passphrase) passphrase=$value ;;
      Security/PreSharedKey) psk=$value ;;
      Settings/Hidden) hidden=$value ;;
      Settings/AutoConnect) autoconnect=$value ;;
    esac
  done <"$file"

  if [[ $type == psk ]]; then
    if [[ -n $passphrase ]]; then
      wifi_iwd_unescape "$passphrase" || return 1
      secret=$REPLY
      ((${#secret} >= 8 && ${#secret} <= 63)) || return 1
    elif [[ $psk =~ ^[0-9a-fA-F]{64}$ ]]; then
      # Only the derived key was stored: enough for WPA2, not for WPA3.
      secret=$psk
    else
      return 1
    fi
    wifi_keyfile_escape "$secret"
    secret=$REPLY
  fi

  wifi_keyfile_escape "$id"
  local id_value=$REPLY

  # The file's name: the network's when it is safe as one, else the hex.
  dest=$id
  [[ $dest =~ ^[A-Za-z0-9_-][A-Za-z0-9\ _.-]*$ ]] || dest="wifi-$hex"
  [[ ! -e $dir/$dest.nmconnection ]] || dest+="-$type"
  dest="$dir/$dest.nmconnection"

  install -d -m 0700 "$dir"
  {
    printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\n' "$id_value" "$(</proc/sys/kernel/random/uuid)"
    [[ ${autoconnect,,} != false ]] || printf 'autoconnect=false\n'
    printf '\n[wifi]\nmode=infrastructure\nssid=%s\n' "$bytes"
    [[ ${hidden,,} != true ]] || printf 'hidden=true\n'
    if [[ $type == psk ]]; then
      printf '\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n' "$secret"
    fi
    printf '\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n'
  } | install -m 0600 /dev/stdin "$dest"
  log "Wi-Fi network \"$id\" is carried into the installed system"
}

# iwd's value escapes (\s \t \n \r \\), undone into REPLY.
wifi_iwd_unescape() {
  local in="$1" out="" i
  for ((i = 0; i < ${#in}; i++)); do
    if [[ ${in:i:1} == "\\" ]]; then
      i=$((i + 1))
      case "${in:i:1}" in
        s) out+=" " ;;
        t) out+=$'\t' ;;
        n) out+=$'\n' ;;
        r) out+=$'\r' ;;
        "\\") out+="\\" ;;
        *) return 1 ;;
      esac
    else
      out+=${in:i:1}
    fi
  done
  REPLY=$out
}

# A value as a NetworkManager keyfile holds it, into REPLY: backslashes
# doubled, and every space written as \s so none is lost at either end.
wifi_keyfile_escape() {
  local in="$1" out="" i
  for ((i = 0; i < ${#in}; i++)); do
    case "${in:i:1}" in
      "\\") out+="\\\\" ;;
      " ") out+="\\s" ;;
      $'\t') out+="\\t" ;;
      $'\n') out+="\\n" ;;
      $'\r') out+="\\r" ;;
      *) out+=${in:i:1} ;;
    esac
  done
  REPLY=$out
}

# Secure Boot (D-31), chosen in the form when the firmware is in Setup Mode.
# The installer's last step, and enrolling is its last action: until the keys
# are enrolled the firmware stays in Setup Mode, so a failure anywhere before
# leaves a machine that still boots (and boots the install ISO to retry).
# karchy-secureboot (in karchy, installed with the desktop) owns the steps and
# explains them; `karchy secureboot setup` does the same on an installed
# system later. In short: sbctl's keys are enrolled with Microsoft's (GPU
# option ROMs, dual boot); Limine is signed and checks each kernel and
# initramfs by the hash in limine.conf, whose own hash is enrolled into the
# signed binary.
base_secureboot() {
  [[ $KARCHY_SECUREBOOT == "yes" ]] || return 0
  in_target karchy-secureboot setup
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
