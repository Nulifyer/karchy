# Vesktop (Discord) follows the theme (D-161). Its theme file is made from a
# template the applied theme doesn't have yet, so on a machine with Vesktop the
# current theme is applied again: that renders the file and
# karchy-theme-set-vesktop puts it in place. A machine without Vesktop gets the
# file with its next theme change, which is soon enough: nothing reads it.
#
# stdin is not the terminal, so the browser's part of a theme change can't
# stop to ask for a password while this output goes to a log.
if [[ -d ${XDG_CONFIG_HOME:-$HOME/.config}/vesktop ]] || command -v vesktop >/dev/null; then
  if [[ ! -f $HOME/.local/state/karchy/current/theme/vesktop.css ]]; then
    karchy-theme-refresh </dev/null
  else
    karchy-theme-set-vesktop
  fi
fi
