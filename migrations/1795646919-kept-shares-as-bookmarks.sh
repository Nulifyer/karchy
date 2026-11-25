# Network shares kept in Settings › Storage are bookmarks in the file
# manager's side pane, not devices (D-190). As devices (x-gvfs-show, D-188)
# the file manager mounted them itself as the user, which failed on the
# root-only credentials ("access denied") while waking the automount, so
# the second click worked. This takes x-gvfs-show off the kept shares' lines
# (the first user to run it) and gives each user a bookmark for each one.
fstab=/etc/fstab
marker='# karchy-kept-mount'

grep -qF "$marker" "$fstab" || { echo "no kept share"; exit 0; }

if grep -F "$marker" "$fstab" | grep -q 'x-gvfs-show'; then
  sudo sed -i -E "/${marker}\$/s/,x-gvfs-show([,[:space:]])/\1/" "$fstab"
  if grep -F "$marker" "$fstab" | grep -q 'x-gvfs-show'; then
    echo "$fstab still lists a kept share as a device"
    exit 1
  fi
  sudo systemctl daemon-reload
fi

karchy-mount-keep --bookmarks
