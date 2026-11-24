#!/bin/bash
# The Vesktop (Discord) theme (D-161), in a made-up home:
#  - every theme renders default/themed/vesktop.css.tpl to CSS with no
#    placeholder left, balanced braces and only six-digit colours, and every
#    colour variable the map uses is one the top of the file defines
#  - karchy-theme-set-vesktop leaves a machine without Vesktop alone, writes
#    the theme where Vesktop has run or is installed, and turns it on once:
#    never over a theme, a theme link or QuickCSS of the user's own, never
#    again after they turned it off, never while Vesktop runs, never in a
#    linked or broken settings file
#  - a second run changes nothing
#  - with Discord's stylesheets in a folder given as the second argument (see
#    tools/discord-theme-map), the template's map is the one they give
# Usage: tests/vesktop-theme.sh [repo root] [folder of Discord's stylesheets]
set -uo pipefail
root=$(realpath "${1:-.}")
stylesheets=${2:-}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

export KARCHY_PATH=$root
unset XDG_CONFIG_HOME

# Stand-ins: no glass tint, no Vesktop process unless a test says so, and a
# `vesktop` command only where a test installs it.
mkdir -p "$tmp/bin" "$tmp/vesktop-bin"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/karchy-theme-set-glass"
# shellcheck disable=SC2016  # $HOME is for the stand-in to expand
printf '#!/bin/bash\n[[ -f $HOME/vesktop-is-running ]]\n' >"$tmp/bin/pgrep"
printf '#!/bin/bash\nexit 0\n' >"$tmp/vesktop-bin/vesktop"
chmod +x "$tmp/bin"/* "$tmp/vesktop-bin/vesktop"
base_path=$tmp/bin:$root/bin:/usr/bin:/bin
export PATH=$base_path

# A home with one theme applied the way karchy-theme-set stages it: the
# theme's files, the templates rendered over them, then moved into place.
new_home() {
  export HOME=$tmp/home-$1
  rm -rf "$HOME"
  mkdir -p "$HOME/.local/state/karchy/current/next-theme"
  cp -rL "$root/themes/$2/"* "$HOME/.local/state/karchy/current/next-theme/"
  karchy-theme-set-templates
  mv "$HOME/.local/state/karchy/current/next-theme" "$HOME/.local/state/karchy/current/theme"
}
data() { echo "$HOME/.config/vesktop"; }
theme_file() { echo "$HOME/.config/vesktop/themes/karchy.theme.css"; }
settings() { echo "$HOME/.config/vesktop/settings/settings.json"; }
enabled() { jq -c '.enabledThemes' "$(settings)" 2>/dev/null; }
# Everything under the made-up home, with sizes and times, to see a change.
snapshot() { find "$HOME" -printf '%p %s %T@ %l\n' | sort; }

# ---- the template, for every theme ------------------------------------------
for dir in "$root"/themes/*/; do
  name=$(basename "$dir")
  new_home render "$name"
  css=$HOME/.local/state/karchy/current/theme/vesktop.css
  check "$name: the theme is rendered" "$([[ -s $css ]] && echo yes)" "yes"
  check "$name: no placeholder is left" "$(grep -c '{{' "$css")" "0"
  check "$name: braces balance" "$(tr -cd '{' <"$css" | wc -c)" "$(tr -cd '}' <"$css" | wc -c)"
  check "$name: every colour is six hex digits" "$(grep -oE '#[0-9A-Fa-f]+' "$css" | grep -vcE '^#[0-9A-Fa-f]{6}$')" "0"
  check "$name: light or dark is said" "$(grep -cE '^  color-scheme: (light|dark);$' "$css")" "1"
  check "$name: every declaration ends" "$(grep -E '^  (--|color|background)' "$css" | grep -vc ';$')" "0"
  check "$name: the map uses only colours the palette defines" \
    "$(comm -23 <(grep -oE 'var\(--karchy-[a-z0-9-]+\)' "$css" | tr -d '()' | sed 's/^var//' | sort -u) \
                <(grep -oE '^  --karchy-[a-z0-9-]+:' "$css" | tr -d ' :' | sort -u) | wc -l)" "0"
  check "$name: Vesktop's list gets a name" "$(grep -c '^ \* @name Karchy$' "$css")" "1"
  check "$name: nothing is fetched" "$(grep -cE '@import|url\(' "$css")" "0"
done
check "the map is there" "$( (( $(grep -c '^  --[a-z].*var(--karchy-' "$root/default/themed/vesktop.css.tpl") > 300 )) && echo yes)" "yes"

# ---- the helper -------------------------------------------------------------
new_home absent nulifyer
before=$(snapshot)
karchy-theme-set-vesktop
check "without Vesktop, nothing is written" "$(snapshot)" "$before"

new_home installed nulifyer
PATH=$tmp/vesktop-bin:$base_path karchy-theme-set-vesktop
check "installed and never started: the theme is in place" "$(cmp -s "$(theme_file)" "$HOME/.local/state/karchy/current/theme/vesktop.css" && echo same)" "same"
check "installed and never started: the theme is on" "$(enabled)" '["karchy.theme.css"]'
check "nothing but the theme and the settings is made" "$(cd "$(data)" && find . -type f | sort | paste -sd' ')" "./settings/settings.json ./themes/karchy.theme.css"

new_home ran nulifyer
mkdir -p "$(data)/settings"
printf '{\n    "autoUpdate": true,\n    "enabledThemes": [],\n    "plugins": {"NoTrack": {"enabled": true}}\n}\n' >"$(settings)"
karchy-theme-set-vesktop
check "Vesktop has run: the theme is on" "$(enabled)" '["karchy.theme.css"]'
check "the other settings are kept" "$(jq -c '[.autoUpdate, .plugins.NoTrack.enabled]' "$(settings)")" "[true,true]"
check "no temporary file is left" "$(find "$(data)" -name '*.??????' | wc -l)" "0"
before=$(snapshot)
karchy-theme-set-vesktop
check "a second run changes nothing" "$(snapshot)" "$before"

# The colours follow the next theme; the switch is not touched again.
jq '.enabledThemes = []' "$(settings)" >"$tmp/settings" && cp "$tmp/settings" "$(settings)"
rm -rf "$HOME/.local/state/karchy/current/theme"
mkdir -p "$HOME/.local/state/karchy/current/next-theme"
cp -rL "$root/themes/catppuccin-latte/"* "$HOME/.local/state/karchy/current/next-theme/"
karchy-theme-set-templates
mv "$HOME/.local/state/karchy/current/next-theme" "$HOME/.local/state/karchy/current/theme"
karchy-theme-set-vesktop
check "a theme change rewrites the file" "$(grep -c 'color-scheme: light' "$(theme_file)")" "1"
check "turned off by the user, it stays off" "$(enabled)" "[]"

new_home own-theme nulifyer
mkdir -p "$(data)/settings" "$(data)/themes"
echo '/* mine */' >"$(data)/themes/mine.theme.css"
printf '{"enabledThemes": ["mine.theme.css"]}\n' >"$(settings)"
karchy-theme-set-vesktop
check "a theme of the user's own stays the one that is on" "$(enabled)" '["mine.theme.css"]'
check "their theme file is untouched" "$(cat "$(data)/themes/mine.theme.css")" "/* mine */"
check "karchy's theme is there to be picked" "$([[ -f $(theme_file) ]] && echo yes)" "yes"
printf '{"enabledThemes": []}\n' >"$(settings)"
karchy-theme-set-vesktop
check "and karchy does not decide again later" "$(enabled)" "[]"

new_home link nulifyer
mkdir -p "$(data)/settings"
printf '{"themeLinks": ["https://example.org/a.css"]}\n' >"$(settings)"
karchy-theme-set-vesktop
check "a theme link of the user's own: not turned on" "$(enabled)" "null"

new_home quickcss nulifyer
mkdir -p "$(data)/settings"
printf '{"enabledThemes": []}\n' >"$(settings)"
echo ':root { --text-default: red; }' >"$(data)/settings/quickCss.css"
karchy-theme-set-vesktop
check "QuickCSS of the user's own: not turned on" "$(enabled)" "[]"
check "their QuickCSS is untouched" "$(cat "$(data)/settings/quickCss.css")" ":root { --text-default: red; }"

new_home empty-quickcss nulifyer
mkdir -p "$(data)/settings"
printf '\n' >"$(data)/settings/quickCss.css"
karchy-theme-set-vesktop
check "an empty QuickCSS file is nobody's styling" "$(enabled)" '["karchy.theme.css"]'

new_home running nulifyer
mkdir -p "$(data)/settings"
printf '{"enabledThemes": []}\n' >"$(settings)"
touch "$HOME/vesktop-is-running"
karchy-theme-set-vesktop
check "while Vesktop runs: the file is written" "$([[ -f $(theme_file) ]] && echo yes)" "yes"
check "while Vesktop runs: its settings are left alone" "$(enabled)" "[]"
rm "$HOME/vesktop-is-running"
ln -s "$(hostname)-$$" "$(data)/SingletonLock"
karchy-theme-set-vesktop
check "while Vesktop holds its lock: its settings are left alone" "$(enabled)" "[]"
ln -sfn "$(hostname)-999999999" "$(data)/SingletonLock"
karchy-theme-set-vesktop
check "a lock left by a crash doesn't count; the theme is turned on then" "$(enabled)" '["karchy.theme.css"]'

new_home dotfile nulifyer
mkdir -p "$(data)/settings" "$HOME/dotfiles"
printf '{"enabledThemes": []}\n' >"$HOME/dotfiles/vesktop.json"
ln -s "$HOME/dotfiles/vesktop.json" "$(settings)"
karchy-theme-set-vesktop
check "a linked settings file is not rewritten" "$(cat "$HOME/dotfiles/vesktop.json")" '{"enabledThemes": []}'
check "and stays a link" "$([[ -L $(settings) ]] && echo link)" "link"

new_home broken nulifyer
mkdir -p "$(data)/settings"
echo '{ not json' >"$(settings)"
karchy-theme-set-vesktop
check "a settings file that isn't JSON is left as it is" "$(cat "$(settings)")" "{ not json"
check "the theme file is still written" "$([[ -f $(theme_file) ]] && echo yes)" "yes"

new_home toggle nulifyer
mkdir -p "$(data)" "$HOME/.local/state/karchy/toggles"
touch "$HOME/.local/state/karchy/toggles/skip-vesktop-theme-changes"
karchy-theme-set-vesktop
check "the skip toggle: nothing is written" "$([[ -e $(theme_file) ]] || echo none)" "none"

new_home unresolved nulifyer
mkdir -p "$(data)"
echo ':root { --karchy-accent: {{ accent }}; }' >"$HOME/.local/state/karchy/current/theme/vesktop.css"
karchy-theme-set-vesktop 2>/dev/null
check "a theme with a colour missing is not published" "$([[ -e $(theme_file) ]] || echo none)" "none"

# ---- the migration ----------------------------------------------------------
# karchy-theme-refresh is a stand-in that says it ran; the real one sets the
# whole theme again.
migration=$(ls "$root"/migrations/*-vesktop-theme.sh)
# shellcheck disable=SC2016
printf '#!/bin/bash\necho refreshed >>"$HOME/refresh-ran"\n' >"$tmp/bin/karchy-theme-refresh"
chmod +x "$tmp/bin/karchy-theme-refresh"
new_home migrate-absent nulifyer
before=$(snapshot)
bash -euo pipefail "$migration"
check "migration, no Vesktop: nothing happens" "$(snapshot)" "$before"
new_home migrate-old nulifyer
mkdir -p "$(data)"
rm "$HOME/.local/state/karchy/current/theme/vesktop.css"
bash -euo pipefail "$migration"
check "migration, a theme applied before the template: the theme is applied again" "$(cat "$HOME/refresh-ran" 2>/dev/null)" "refreshed"
new_home migrate-new nulifyer
mkdir -p "$(data)"
bash -euo pipefail "$migration"
check "migration, the file already rendered: it is put in place" "$([[ -f $(theme_file) ]] && echo yes)" "yes"
check "and nothing else is applied again" "$([[ -e $HOME/refresh-ran ]] || echo no)" "no"
before=$(snapshot)
bash -euo pipefail "$migration"
check "the migration twice changes nothing" "$(snapshot)" "$before"

# ---- the commands that call it ----------------------------------------------
check "a theme change runs it" "$(grep -c '^  karchy-theme-set-vesktop$' "$root/bin/karchy-theme-set")" "1"
check "Quick install runs it after an install" "$(grep -c 'karchy-theme-set-vesktop' "$root/bin/karchy-quick-install")" "1"
check "a theme from a git repo cannot supply the file" \
  "$(grep -c '^INSTALLED_THEME_DENIED=.*vesktop\.css' "$root/bin/karchy-theme-set")" "1"

# ---- the map against Discord's stylesheets ----------------------------------
if [[ -n $stylesheets ]]; then
  check "the map is the one Discord's stylesheets give" \
    "$("$root/tools/discord-theme-map" "$stylesheets" --check >/dev/null 2>&1 && echo same)" "same"
else
  echo "skip: no folder of Discord's stylesheets given, so the map isn't compared with them"
fi

echo "passed: $pass, failed: $failures"
(( failures == 0 ))
