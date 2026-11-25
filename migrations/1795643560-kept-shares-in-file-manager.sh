# Network shares kept in Settings › Storage are listed in the file manager
# (D-188). GIO lists an fstab entry under /mnt only with x-gvfs-show, which
# karchy-mount-keep now writes; this adds it to the shares kept before. Every
# user of the machine runs it; only the first changes anything.
fstab=/etc/fstab
marker='# karchy-kept-mount'

grep -F "$marker" "$fstab" | grep -vq 'x-gvfs-show' || { echo "no kept share without x-gvfs-show"; exit 0; }

# The fourth field (the options) of each kept share's line gains x-gvfs-show.
sudo sed -i -E "/${marker}\$/{/x-gvfs-show/!s/^([^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+cifs[[:space:]]+[^[:space:]]+)/\1,x-gvfs-show/}" "$fstab"
if grep -F "$marker" "$fstab" | grep -vq 'x-gvfs-show'; then
  echo "$fstab still has a kept share without x-gvfs-show"
  exit 1
fi
sudo systemctl daemon-reload
