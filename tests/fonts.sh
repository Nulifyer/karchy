#!/bin/bash
# Fonts (D-120), without a desktop:
#  - 50-karchy.conf: what "monospace", "sans-serif" and a named font turn into,
#    with and without a font chosen by karchy-font-set, and that the user's
#    own fontconfig still wins (fc-pattern on a config of only these files:
#    substitution needs no fonts installed)
#  - karchy-font-set, karchy-font-list and karchy-font-app-* against a fake
#    fc-list, fc-match and gsettings
#  - the migration that moves an earlier choice into karchy's state
#  - every font on the Quick install list names a family and has its picture
# Usage: tests/fonts.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

export HOME=$tmp/home XDG_CONFIG_HOME=$tmp/home/.config XDG_STATE_HOME=$tmp/home/.local/state
mkdir -p "$HOME" "$XDG_CONFIG_HOME"
state=$HOME/.local/state/karchy/fontconfig/font.conf
legacy=$XDG_CONFIG_HOME/fontconfig/conf.d/60-karchy-font.conf

# ---- fontconfig -----------------------------------------------------------
# karchy's file, then the user's, as /etc/fonts/conf.d orders them
# (50-karchy.conf before 50-user.conf).
cat >"$tmp/fonts.conf" <<XML
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <cachedir>$tmp/cache</cachedir>
  <include>$root/system/fontconfig/50-karchy.conf</include>
  <include ignore_missing="yes" prefix="xdg">fontconfig/fonts.conf</include>
</fontconfig>
XML
# The families a pattern becomes, in order, comma-separated.
families() {
  FONTCONFIG_FILE=$tmp/fonts.conf fc-pattern -c "$1" family | grep -o '"[^"]*"' | tr -d '"' | paste -sd, -
}
if command -v fc-pattern >/dev/null; then
  check "monospace is the default font, then icons, the mark, then emoji" "$(families monospace)" \
    "Noto Sans Mono,monospace,Symbols Nerd Font Mono,karchy Symbols,Noto Color Emoji"
  check "sans-serif gets icons from the symbols font" "$(families 'sans\-serif')" "sans-serif,Symbols Nerd Font Mono,karchy Symbols,Noto Color Emoji"
  check "serif gets icons from the symbols font" "$(families serif)" "serif,Symbols Nerd Font Mono,karchy Symbols,Noto Color Emoji"
  check "the mark follows the symbols font asked for by name" "$(families 'Symbols Nerd Font Mono')" "Symbols Nerd Font Mono,karchy Symbols"
  check "ui-monospace is the monospace font" "$(families 'ui\-monospace' | cut -d, -f1-2)" "ui-monospace,Noto Sans Mono"
  check "a font asked for by name stays first" "$(families 'Hack:family=monospace' | cut -d, -f1-2)" "Hack,Noto Sans Mono"
  check "system-ui is Noto Sans" "$(families 'system\-ui' | cut -d, -f1)" "Noto Sans"
else
  echo "skip: fc-pattern is not installed"
fi

# ---- the commands, against a fake system ----------------------------------
mkdir -p "$tmp/bin"
# Installed fonts: "family names<TAB>fixed|prop<TAB>icons|plain", the first
# name being the one fc-list prints with %{family[0]}. Noto Sans Mono is
# "prop" as on a real system: fontconfig doesn't mark it fixed-width.
cat >"$tmp/fontlist" <<'LIST'
JetBrainsMono Nerd Font,JetBrainsMono NF	fixed	icons
JetBrainsMono Nerd Font Mono,JetBrainsMono NFM	fixed	icons
AtkynsonMono Nerd Font Mono	fixed	icons
Adwaita Mono	fixed	plain
Noto Sans Mono CJK JP	fixed	plain
Noto Color Emoji	fixed	plain
Symbols Nerd Font Mono	fixed	icons
Adwaita Sans	prop	plain
Noto Sans	prop	plain
Noto Sans Bengali	prop	plain
Noto Sans Mono	prop	plain
A & B <Mono>	fixed	plain
LIST
cat >"$tmp/bin/fc-list" <<'FAKE'
#!/bin/bash
# fc-list <pattern> family | fc-list <pattern> -f '%{family[0]}\n'
# A pattern without a colon is a family's name.
pattern=$1 first=0
[[ ${2:-} == -f ]] && first=1
while IFS=$'\t' read -r names spacing icons; do
  [[ $pattern != *:* && ,$names, != *,"$pattern",* ]] && continue
  [[ $pattern == *spacing=100* && $spacing != fixed ]] && continue
  [[ $pattern == *charset=* && $icons != icons ]] && continue
  if ((first)); then echo "${names%%,*}"; else echo "$names"; fi
done <"$FAKE_FONTS"
FAKE
cat >"$tmp/bin/fc-match" <<'FAKE'
#!/bin/bash
# The font karchy-font-set wrote, else the default.
chosen=$(sed -n 's:.*<string>\(.*\)</string>.*:\1:p' "$HOME/.local/state/karchy/fontconfig/font.conf" 2>/dev/null | grep -vx monospace | head -n1)
echo "${chosen:-Noto Sans Mono}"
FAKE
cat >"$tmp/bin/gsettings" <<'FAKE'
#!/bin/bash
store=$FAKE_GSETTINGS
case $1 in
  get) cat "$store/$3" 2>/dev/null || echo "'Noto Sans 11'" ;;
  set) printf "'%s'\n" "$4" >"$store/$3" ;;
  reset) rm -f "$store/$3" ;;
esac
FAKE
# A system with no package database: sizes are simply left out.
printf '#!/bin/bash\nexit 1\n' >"$tmp/bin/pacman"
chmod +x "$tmp/bin"/*
export PATH=$tmp/bin:$root/bin:$PATH FAKE_FONTS=$tmp/fontlist FAKE_GSETTINGS=$tmp/gsettings KARCHY_PATH=$root
mkdir -p "$FAKE_GSETTINGS"

check "font list: one line per family, no symbol, emoji or CJK fonts" "$(karchy-font-list | paste -sd'|' -)" \
  "A & B <Mono>|Adwaita Mono|AtkynsonMono Nerd Font Mono|JetBrainsMono Nerd Font|Noto Sans Mono"
check "font list --names: every name of a fixed-width family, and Noto Sans Mono" \
  "$(karchy-font-list --names | grep -c -x -e 'JetBrainsMono NF' -e 'Noto Sans Mono')" "2"

karchy-font-set --no-restart "adwaita mono" >/dev/null 2>&1
check "font set: the file is well-formed" "$(FONTCONFIG_FILE=$state fc-pattern -c x 2>&1 | grep -c 'error')" "0"
check "font set: writes karchy's state file" "$(grep -c '<string>Adwaita Mono</string>' "$state" 2>/dev/null)" "1"
check "font set: puts it before monospace, not first" "$(grep -c 'mode="prepend"' "$state" 2>/dev/null)" "1"
check "font set: nothing in the user's fontconfig" "$(ls "$XDG_CONFIG_HOME/fontconfig" 2>/dev/null)" ""
check "font current" "$(karchy-font-current)" "Adwaita Mono"

if command -v fc-pattern >/dev/null; then
  check "chosen font comes before the default" "$(families monospace | cut -d, -f1-2)" "Adwaita Mono,Noto Sans Mono"
  check "a font asked for by name stays first, with one chosen" "$(families 'Hack:family=monospace' | cut -d, -f1-3)" "Hack,Adwaita Mono,Noto Sans Mono"
  mkdir -p "$XDG_CONFIG_HOME/fontconfig"
  cat >"$XDG_CONFIG_HOME/fontconfig/fonts.conf" <<'XML'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="pattern">
    <test name="family" qual="any"><string>monospace</string></test>
    <edit name="family" mode="prepend_first" binding="strong"><string>Mine</string></edit>
  </match>
</fontconfig>
XML
  check "the user's fonts.conf wins" "$(families monospace | cut -d, -f1-2)" "Mine,Adwaita Mono"
  rm -r "$XDG_CONFIG_HOME/fontconfig"
fi

before=$(cat "$state")
karchy-font-set --no-restart "Adwaita" >/dev/null 2>&1
check "font set: part of a name is refused" "$?" "1"
karchy-font-set --no-restart "Noto Sans" >/dev/null 2>&1
check "font set: a proportional font is refused" "$?" "1"
check "font set: a refusal changes nothing" "$(cat "$state")" "$before"

karchy-font-set --no-restart "A & B <Mono>" >/dev/null 2>&1
check "font set: the name is escaped" "$(grep -c '<string>A &amp; B &lt;Mono&gt;</string>' "$state")" "1"
check "font list --json: chosen is read back" "$(karchy-font-list --json | jq -r .chosen)" "A & B <Mono>"

karchy-font-set --no-restart reset >/dev/null 2>&1
check "font set reset: removes the choice" "$([[ -e $state ]] && echo there || echo gone)" "gone"
check "font current after reset" "$(karchy-font-current)" "Noto Sans Mono"
karchy-font-set --no-restart "noto sans mono" >/dev/null 2>&1
check "font set: Noto Sans Mono is taken, though fontconfig calls it proportional" "$(karchy-font-list --json | jq -r .chosen)" "Noto Sans Mono"
karchy-font-set --no-restart reset >/dev/null 2>&1

json=$(karchy-font-list --json)
check "json: installed fonts first, by name" "$(jq -r '[.fonts[] | select(.installed) | .name] | join("|")' <<<"$json")" \
  "A & B <Mono>|Adwaita Mono|Atkinson Hyperlegible|JetBrains Mono|Noto Sans Mono"
check "json: an installed listed font keeps its id" "$(jq -r '.fonts[] | select(.family == "AtkynsonMono Nerd Font Mono") | .id' <<<"$json")" "font-atkinson-hyperlegible-mono"
check "json: icons from the font or the fallback" "$(jq -r '[.fonts[] | select(.installed) | .icons] | join(",")' <<<"$json")" "false,false,true,true,false"
check "json: listed fonts that aren't installed follow" "$(jq -r '[.fonts[] | select(.installed | not)] | length' <<<"$json")" \
  "$(($(jq '[.apps[] | select(.category == "fonts")] | length' "$root/default/karchy/quick-install.json") - 1))"
check "json: each has a picture that exists" "$(jq -r '.fonts[] | select(.id != "") | .specimen' <<<"$json" | while read -r f; do [[ -s $f ]] || echo "$f"; done)" ""

# ---- the app font ---------------------------------------------------------
check "app list: interface fonts only" "$(karchy-font-app-list | paste -sd'|' -)" "monospace|Adwaita Sans|Noto Sans"
check "app current: karchy's default" "$(karchy-font-app-current)" "Noto Sans"
karchy-font-app-set "adwaita sans"
check "app set: the interface font, at GNOME's size" "$(cat "$FAKE_GSETTINGS/font-name")" "'Adwaita Sans 11'"
check "app set: the document font too" "$(cat "$FAKE_GSETTINGS/document-font-name")" "'Adwaita Sans 12'"
check "app current" "$(karchy-font-app-current)" "Adwaita Sans"
karchy-font-app-set monospace
check "app set monospace: follows the monospace font" "$(cat "$FAKE_GSETTINGS/font-name")" "'monospace 11'"
check "app current: monospace" "$(karchy-font-app-current)" "monospace"
karchy-font-app-set "Nope" >/dev/null 2>&1
check "app set: an unknown font is refused" "$?" "1"
karchy-font-app-set reset
check "app set reset" "$(ls "$FAKE_GSETTINGS")" ""

# ---- the migration --------------------------------------------------------
migration=$(ls "$root"/migrations/*-font-choice-state.sh)
mkdir -p "${legacy%/*}"
printf '<!-- Written by karchy-font-set (Settings › Appearance). -->\n<fontconfig><match><edit name="family" mode="prepend_first"><string>Adwaita Mono</string></edit></match></fontconfig>\n' >"$legacy"
bash -euo pipefail "$migration"
check "migration: the choice moves to karchy's state" "$(grep -c '<string>Adwaita Mono</string>' "$state" 2>/dev/null)" "1"
check "migration: karchy's old file is gone, and its empty folder" "$([[ -e ${legacy%/*} ]] && echo there || echo gone)" "gone"
bash -euo pipefail "$migration"
check "migration: a second run changes nothing" "$(grep -c '<string>Adwaita Mono</string>' "$state" 2>/dev/null)" "1"
rm -f "$state"
mkdir -p "${legacy%/*}"
echo '<fontconfig><!-- mine --></fontconfig>' >"$legacy"
bash -euo pipefail "$migration"
check "migration: a hand-written file stays" "$(cat "$legacy")" '<fontconfig><!-- mine --></fontconfig>'
check "migration: and nothing is chosen for it" "$([[ -e $state ]] && echo there || echo none)" "none"

# ---- the list --------------------------------------------------------------
catalog=$root/default/karchy/quick-install.json
check "every listed font names its family and one package" \
  "$(jq -r '.apps[] | select(.category == "fonts") | select((.font | not) or (.packages | length) != 1) | .id' "$catalog")" ""
check "every listed font has a picture, and no picture is left over" "$("$root/tools/font-specimens" --check 2>&1)" ""

echo "fonts: $pass passed, $failures failed"
((failures == 0))
