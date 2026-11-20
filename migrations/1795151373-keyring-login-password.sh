# The login keyring is locked with the login password wherever karchy's login
# screen is how people get in (D-142). An encrypted install with automatic
# login off (a second person was added, or it was turned off) kept a random
# key per person in /etc/credstore until now, which an administrator could
# read. This marks such an install; nothing is re-keyed here. Each person's
# keyring gets their password at their next login at the login screen, and
# their key is deleted then (/usr/lib/karchy/keyring-login). People who log
# in automatically, and installs without disk encryption, are as they should
# be already.
helper=/usr/lib/karchy/users-settings
[[ -x $helper ]] || { echo "karchy-settings has no users helper yet"; exit 1; }
[[ ! -e /etc/karchy/keyring-login-password ]] || exit 0
status=$("$helper" status)
[[ $(jq -r '.encrypted and (.autologin.on | not)' <<<"$status") == true ]] || exit 0
# An administrator's update does it; a standard user has no sudo.
id -nG | grep -qw wheel || exit 0
# "Off" is what it is already: this writes the mark, passwd's keyring line
# and the login screen's PAM service, and changes nothing else.
sudo "$helper" autologin off
