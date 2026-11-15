# karchy: the same environment for login shells outside the session (TTY, SSH).
# Dev mode (/etc/karchy.conf, D-55) applies to users only: root keeps the
# packaged copy, because the checkout is writable by its user (D-50).
KARCHY_PATH=/usr/share/karchy
if [ "$(id -u)" -ne 0 ] && [ -r /etc/karchy.conf ]; then
  . /etc/karchy.conf
fi
export KARCHY_PATH
# Terminal editor for git, sudoedit and friends; your own EDITOR wins.
export EDITOR="${EDITOR:-micro}"
if [ "$KARCHY_PATH" != /usr/share/karchy ]; then
  case ":$PATH:" in
    *":$KARCHY_PATH/bin:"*) ;;
    *) export PATH="$KARCHY_PATH/bin:$PATH" ;;
  esac
fi
