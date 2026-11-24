# Plymouth draws the boot splash at scale 1 (D-173). On a screen Plymouth
# takes for high-resolution it otherwise sets a scale of 2: karchy's script
# then sees half the height, picks its small pictures, and Plymouth enlarges
# them twice, blurred. The theme sizes itself (D-122), so scale 1 is always
# right. This adds DeviceScale=1 to plymouthd.conf, unless the file already
# sets a DeviceScale of somebody's own, and builds the boot images once so
# the initramfs gets the file (the shutdown splash reads it from /etc). Every
# user of the machine runs it; only the first changes anything.
limine=/etc/default/limine
plymouthd=/etc/plymouth/plymouthd.conf

command -v plymouth-set-default-theme >/dev/null || { echo "plymouth is not installed"; exit 1; }
[[ -f $limine ]] || { echo "$limine not found: not a karchy boot setup, nothing to do"; exit 0; }

if ! grep -Eqs '^[[:space:]]*DeviceScale[[:space:]]*=' "$plymouthd"; then
  if grep -qs '^\[Daemon\]' "$plymouthd"; then
    sudo sed -i '0,/^\[Daemon\]/s//[Daemon]\nDeviceScale=1/' "$plymouthd"
  else
    printf '[Daemon]\nDeviceScale=1\n' | sudo tee -a "$plymouthd" >/dev/null
  fi
fi

# The plymouth hook copies the file into each image when it is built, so an
# image older than the file doesn't have it yet. The images are the ones
# limine-mkinitcpio writes for this machine (not the copies the snapshot
# entries keep in limine_history).
esp=$(sed -n 's/^ESP_PATH=["'\'']\?\([^"'\'']*\).*/\1/p' "$limine" | tail -n 1)
images=${esp:-/boot}/$(</etc/machine-id)
older() { sudo find "$images" -mindepth 2 -maxdepth 2 -type f -name initramfs ! -newer "$plymouthd"; }

[[ -n $(older) ]] || exit 0
sudo limine-mkinitcpio

# limine-mkinitcpio carries on past a kernel it could not build and still
# exits 0: done means no image is older than the file; otherwise the next
# update tries again.
stale=$(older)
[[ -z $stale ]] || { echo "Not rebuilt: $stale"; exit 1; }
