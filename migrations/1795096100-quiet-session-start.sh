# The session greetd starts after the disk is unlocked no longer prints
# uwsm's start messages on the screen between the boot splash and the desktop
# (D-122); they stay in the journal. Only the line the installer wrote is
# changed; a session command someone edited stays.
config=/etc/greetd/config.toml
old='command = "uwsm start -g -1 -e -D Hyprland hyprland.desktop"'
grep -qsxF "$old" "$config" || exit 0
sudo sed -i "s|^$old\$|${old%\"} >/dev/null\"|" "$config"
