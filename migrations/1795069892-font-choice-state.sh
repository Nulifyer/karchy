# The monospace font chosen with `karchy font set` moves from
# ~/.config/fontconfig/conf.d/60-karchy-font.conf, a karchy file among the
# user's own, into karchy's state, which 50-karchy.conf now includes (D-120).
# Only the file karchy wrote is touched; a hand-written one stays.
old=$HOME/.config/fontconfig/conf.d/60-karchy-font.conf
grep -qs 'Written by karchy-font-set' "$old" || exit 0

family=$(sed -n 's:.*<string>\(.*\)</string>.*:\1:p' "$old" | grep -vx monospace | sed -n '1p' |
  sed 's/&lt;/</g; s/&gt;/>/g; s/&amp;/\&/g') || true
# The shell and open apps already use this font, so nothing is restarted.
# A font that has since been removed is simply not carried over.
if [[ -n $family ]]; then
  karchy-font-set --no-restart "$family" || true
fi
rm -f "$old"
rmdir "${old%/*}" 2>/dev/null || true
