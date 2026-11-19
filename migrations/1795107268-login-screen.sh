# Logging out shows karchy's login screen instead of the text greeter (D-130),
# and the session is started by one command, /usr/lib/karchy/session. Only the
# lines the installer wrote are changed; ones someone edited stay. Takes
# effect the next time greetd starts a greeter: at the next log out.
config=/etc/greetd/config.toml
[[ -f $config ]] || exit 0
[[ -x /usr/lib/karchy/greeter && -x /usr/lib/karchy/session ]] ||
  { echo "the karchy package has no login screen yet"; exit 1; }

session='uwsm start -g -1 -e -D Hyprland hyprland.desktop'
old_greeter="command = \"agreety --cmd '$session'\""
old_session="command = \"$session >/dev/null\""

if grep -qsxF "$old_greeter" "$config"; then
  sudo sed -i "s|^$old_greeter\$|command = \"/usr/lib/karchy/greeter\"|" "$config"
fi
if grep -qsxF "$old_session" "$config"; then
  sudo sed -i "s|^$old_session\$|command = \"/usr/lib/karchy/session\"|" "$config"
fi
