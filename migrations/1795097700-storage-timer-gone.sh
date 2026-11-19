# Settings › Storage no longer counts files every night (D-123): the package
# took the timer's unit away, but a timer that was already running stays
# loaded until the next start and would fire once more at 04:00. Stop it,
# and clear what was left for it: a mask someone set to turn it off, and
# systemd's note of when it last ran.
timer=karchy-storage-measure.timer
[[ ! -e /usr/lib/systemd/system/$timer ]] || exit 0

# systemd may already have dropped it when its unit file went ("failed").
case $(systemctl show "$timer" -P ActiveState 2>/dev/null) in
  active | activating) sudo systemctl stop "$timer" ;;
  failed) sudo systemctl reset-failed "$timer" ;;
esac
if [[ -L /etc/systemd/system/$timer && $(readlink "/etc/systemd/system/$timer") == /dev/null ]]; then
  sudo rm -f "/etc/systemd/system/$timer"
  sudo systemctl daemon-reload
fi
if [[ -e /var/lib/systemd/timers/stamp-$timer ]]; then
  sudo rm -f "/var/lib/systemd/timers/stamp-$timer"
fi
