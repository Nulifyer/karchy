# The disk-password screen is Plymouth's, in karchy's theme (D-122). The
# packages bring Plymouth, the theme and the initramfs hook; this adds what
# the installer wrote for earlier machines: the theme as Plymouth's default
# and "splash" on the kernel line, then builds the boot images once with
# both. Every user of the machine runs it; only the first changes anything.
limine=/etc/default/limine
plymouthd=/etc/plymouth/plymouthd.conf
changed=0

command -v plymouth-set-default-theme >/dev/null || { echo "plymouth is not installed"; exit 1; }
[[ -f $limine ]] || { echo "$limine not found: not a karchy boot setup, nothing to do"; exit 0; }

# A theme someone chose stays.
if ! grep -qs '^Theme=' "$plymouthd"; then
  sudo plymouth-set-default-theme karchy
  changed=1
fi

# splash shows the theme; systemd.tty.term.console=dumb keeps systemd from
# waiting for the console's answer about its size while Plymouth has the
# screen (install/base.sh). Only karchy's own line is changed: a default
# kernel line written with = that has neither word yet.
line=$(grep -m1 '^KERNEL_CMDLINE\[default\]="' "$limine" || true)
if [[ -n $line && ! " ${line#*=\"} " =~ [\ \"]splash[\ \"] ]]; then
  add="splash"
  [[ $line == *systemd.tty.term.console=* ]] || add+=" systemd.tty.term.console=dumb"
  if [[ $line == *'="quiet '* ]]; then
    sudo sed -i "0,/^KERNEL_CMDLINE\[default\]=\"quiet /s//KERNEL_CMDLINE[default]=\"quiet $add /" "$limine"
  else
    sudo sed -i "0,/^KERNEL_CMDLINE\[default\]=\"/s//KERNEL_CMDLINE[default]=\"$add /" "$limine"
  fi
  changed=1
elif [[ -z $line ]]; then
  echo "No KERNEL_CMDLINE[default]=\"...\" line in $limine: add splash to your kernel line to see the splash"
fi

grep -q '^HOOKS=.* plymouth ' /etc/mkinitcpio.conf.d/karchy.conf ||
  echo "/etc/mkinitcpio.conf.d/karchy.conf has no plymouth hook (see karchy.conf.pacnew): the text prompt stays"

((changed)) || exit 0
say="Building the boot images again with karchy's boot splash; this takes about a minute."
echo "$say"
# Shown in the update as it runs (karchy-migrate's fd 3), so it doesn't look stuck.
echo "$say" 2>/dev/null >&3 || true
sudo limine-mkinitcpio

# limine-mkinitcpio carries on past a kernel it could not build and still
# exits 0. Done means the boot menu has an entry with splash; otherwise the
# next update tries again.
esp=$(sed -n 's/^ESP_PATH=["'\'']\?\([^"'\'']*\).*/\1/p' "$limine" | tail -n 1)
sudo grep -Eq '^[[:space:]]*cmdline:.* splash( |$)' "${esp:-/boot}/limine.conf" ||
  { echo "The boot menu has no entry with splash after the rebuild"; exit 1; }
