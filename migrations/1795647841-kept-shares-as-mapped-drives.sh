# Network shares kept in Settings › Storage behave as mapped drives (D-191):
# listed under Devices as "<share> on <server>" with a network folder's icon,
# connected wherever their server answers and let go wherever it doesn't
# (/usr/lib/karchy/kept-shares, on every network change). Their lines lose
# the 10-minute idle unmount, which left the file manager to mount them
# itself as the user and fail on the root-only credentials. Every user of
# the machine runs it; only the first changes anything.
fstab=/etc/fstab
marker='# karchy-kept-mount'

grep -qF "$marker" "$fstab" || { echo "no kept share"; exit 0; }

new=$(python3 -I - "$fstab" "$marker" <<'PY'
import sys
path, marker = sys.argv[1], sys.argv[2]
out = []
for line in open(path):
    body = line.rstrip("\n")
    if not body.endswith(marker) or body.lstrip().startswith("#"):
        out.append(line)
        continue
    fields = body[: -len(marker)].split()
    if len(fields) < 4:
        out.append(line)
        continue
    server, _, share = fields[0][2:].partition("/")
    # A name's first label ("truenas"), an address in full.
    host = server if server.replace(".", "").isdigit() else server.split(".")[0]
    name = (share + " on " + host).replace(" ", "\\040")
    opts = [o for o in fields[3].split(",") if o and not o.startswith(
        ("x-systemd.idle-timeout=", "x-gvfs-show", "x-gvfs-name=", "x-gvfs-icon=", "x-gvfs-symbolic-icon="))]
    opts += ["x-gvfs-show", "x-gvfs-name=" + name, "x-gvfs-icon=folder-remote", "x-gvfs-symbolic-icon=folder-remote-symbolic"]
    fields[3] = ",".join(opts)
    out.append(" ".join(fields) + " " + marker + "\n")
sys.stdout.write("".join(out))
PY
) || { echo "couldn't read $fstab"; exit 1; }

if [[ $new != "$(cat "$fstab")" ]]; then
  if ! { printf '%s\n' "$new" | sudo tee "$fstab.karchy-new" >/dev/null &&
    sudo chmod 644 "$fstab.karchy-new" && sudo mv "$fstab.karchy-new" "$fstab"; }; then
    echo "couldn't update $fstab"
    exit 1
  fi
  sudo systemctl daemon-reload
fi
if [[ -x /usr/lib/karchy/kept-shares ]]; then
  sudo /usr/lib/karchy/kept-shares || true
fi
