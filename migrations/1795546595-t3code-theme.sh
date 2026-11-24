# T3 Code gets karchy's theme selected for it once (D-171), where it has never
# opened a window and no theme is chosen. Without this a machine with T3 Code
# installed and not yet started would wait for the next theme change, and its
# first start would show T3 Code's own colours. karchy-theme-set-t3code decides
# once and remembers it, so running it here changes nothing it already did.
#
# stdin is not the terminal, so the browser's part of a theme change can't
# stop to ask for a password while this output goes to a log.
if [[ -d ${T3CODE_HOME:-$HOME/.t3}/userdata ]] || command -v t3code >/dev/null; then
  if [[ ! -f $HOME/.local/state/karchy/current/theme/t3code.json ]]; then
    karchy-theme-refresh </dev/null
  else
    karchy-theme-set-t3code
  fi
fi
