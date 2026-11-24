#!/bin/bash
# The T3 Code theme (D-171), in a made-up home:
#  - every theme renders default/themed/t3code.json.tpl to JSON with no
#    placeholder left
#  - karchy-theme-set-t3code leaves a machine without T3 Code alone, publishes
#    the theme where T3 Code has run or is installed, and selects it once with
#    `t3 theme set`: never over an environment theme or a published theme of
#    the user's own, never where a T3 Code window has opened (a theme picked
#    there can't be seen), never again after they switched away, never in a
#    linked or broken settings file
#  - a second run changes nothing
#  - the migration
#  - with the t3code-bin app present (or its folder given as the second
#    argument), the same with the real `t3` command
# Usage: tests/t3code-theme.sh [repo root] [T3 Code app folder]
set -uo pipefail
root=$(realpath "${1:-.}")
app_dir=${2:-/opt/t3code-bin}
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

export KARCHY_PATH=$root
unset XDG_CONFIG_HOME T3CODE_HOME
# No real app unless the last section says so.
export T3CODE_APP_DIR=$tmp/no-app

# Stand-ins: no glass tint; a `t3code` command only where a test installs it;
# a `t3` that does what `t3 theme set <id>` does (refuses an id it has no file
# for, writes defaultTheme and defaultThemeSetAt) and logs each call.
mkdir -p "$tmp/bin" "$tmp/t3code-bin" "$tmp/t3-bin"
printf '#!/bin/bash\nexit 0\n' >"$tmp/bin/karchy-theme-set-glass"
printf '#!/bin/bash\nexit 0\n' >"$tmp/t3code-bin/t3code"
# shellcheck disable=SC2016  # for the stand-in to expand
cat >"$tmp/t3-bin/t3" <<'EOF'
#!/bin/bash
set -eu
echo "$*" >>"$HOME/t3-calls"
[[ $1 == theme && $2 == set ]] || exit 2
data=${T3CODE_HOME:-$HOME/.t3}/userdata
[[ -f $data/themes/$3.json ]] || { echo "No theme named \"$3\"" >&2; exit 1; }
settings=$data/settings.json
[[ -s $settings ]] || echo '{}' >"$settings"
jq --arg id "$3" --arg at "$(date -u +%FT%T.%3NZ)" '.defaultTheme = $id | .defaultThemeSetAt = $at' "$settings" >"$settings.new"
mv "$settings.new" "$settings"
EOF
chmod +x "$tmp/bin"/* "$tmp/t3code-bin/t3code" "$tmp/t3-bin/t3"
# The system's commands without T3 Code's own, which this host may have.
mkdir -p "$tmp/sys"
for cmd in /usr/bin/* /bin/*; do
  case ${cmd##*/} in t3 | t3code | t3-code-desktop) continue ;; esac
  [[ -e $tmp/sys/${cmd##*/} || -L $tmp/sys/${cmd##*/} ]] || ln -s "$cmd" "$tmp/sys/${cmd##*/}"
done
base_path=$tmp/bin:$root/bin:$tmp/sys
installed_path=$tmp/t3code-bin:$tmp/t3-bin:$base_path
export PATH=$base_path

# A home with one theme applied the way karchy-theme-set stages it.
new_home() {
  export HOME=$tmp/home-$1
  rm -rf "$HOME"
  mkdir -p "$HOME/.local/state/karchy/current/next-theme"
  cp -rL "$root/themes/$2/"* "$HOME/.local/state/karchy/current/next-theme/"
  karchy-theme-set-templates
  mv "$HOME/.local/state/karchy/current/next-theme" "$HOME/.local/state/karchy/current/theme"
}
data() { echo "$HOME/.t3/userdata"; }
theme_file() { echo "$HOME/.t3/userdata/themes/karchy.json"; }
settings() { echo "$HOME/.t3/userdata/settings.json"; }
selected() { jq -r '.defaultTheme // "none"' "$(settings)" 2>/dev/null || echo none; }
calls() { cat "$HOME/t3-calls" 2>/dev/null | paste -sd';'; }
helper() { PATH=$installed_path karchy-theme-set-t3code; }
snapshot() { find "$HOME" -printf '%p %s %T@ %l\n' | sort; }

# ---- the template, for every theme ------------------------------------------
for dir in "$root"/themes/*/; do
  name=$(basename "$dir")
  new_home render "$name"
  json=$HOME/.local/state/karchy/current/theme/t3code.json
  check "$name: no placeholder is left" "$(grep -c '{{' "$json")" "0"
  check "$name: the theme T3 Code reads" "$(jq -r '[.name, .appearance, (.accent | type), (.colors | type)] | join(",")' "$json" 2>/dev/null)" \
    "Karchy,$(jq -r '.appearance' "$json" 2>/dev/null),string,object"
done

# ---- the helper -------------------------------------------------------------
new_home absent nulifyer
before=$(snapshot)
PATH=$tmp/t3-bin:$base_path karchy-theme-set-t3code
check "without T3 Code, nothing is written" "$(snapshot)" "$before"

new_home installed nulifyer
helper
check "installed and never started: the theme is in place" "$(cmp -s "$(theme_file)" "$HOME/.local/state/karchy/current/theme/t3code.json" && echo same)" "same"
check "installed and never started: the theme is selected" "$(selected)" "karchy"
check "with t3 theme set" "$(calls)" "theme set karchy"
check "nothing but the theme and the settings is made" "$(cd "$(data)" && find . -type f | sort | paste -sd' ')" "./settings.json ./themes/karchy.json"
before=$(snapshot)
helper
check "a second run changes nothing" "$(snapshot)" "$before"

# Switched away (in T3 Code, or with t3 theme set ember): the colours follow
# the next theme, the choice is not touched again.
jq '.defaultTheme = "ember"' "$(settings)" >"$tmp/s" && cp "$tmp/s" "$(settings)"
rm -rf "$HOME/.local/state/karchy/current/theme"
mkdir -p "$HOME/.local/state/karchy/current/next-theme"
cp -rL "$root/themes/catppuccin-latte/"* "$HOME/.local/state/karchy/current/next-theme/"
karchy-theme-set-templates
mv "$HOME/.local/state/karchy/current/next-theme" "$HOME/.local/state/karchy/current/theme"
helper
check "a theme change rewrites the file" "$(jq -r .appearance "$(theme_file)")" "light"
check "switched away by the user, it stays theirs" "$(selected)" "ember"
jq 'del(.defaultTheme, .defaultThemeSetAt)' "$(settings)" >"$tmp/s" && cp "$tmp/s" "$(settings)"
helper
check "cleared by the user, it is not selected again" "$(selected)" "none"
check "t3 ran once in all" "$(calls)" "theme set karchy"

new_home ran nulifyer
mkdir -p "$(data)"
printf '{\n  "favorites": ["a"]\n}\n' >"$(settings)"
helper
check "T3 Code's server has run, no window yet: selected" "$(selected)" "karchy"
check "the other settings are kept" "$(jq -c '.favorites' "$(settings)")" '["a"]'
check "no temporary file is left" "$(find "$(data)" -name '*.??????' | wc -l)" "0"

new_home window nulifyer
mkdir -p "$(data)" "$HOME/.config/t3code-v2"
helper
check "a T3 Code window has opened: the theme is there to pick" "$([[ -f $(theme_file) ]] && echo yes)" "yes"
check "but not selected over what may be picked in it" "$(selected)" "none"
check "and t3 is not run" "$(calls)" ""
rm -rf "$HOME/.config/t3code-v2"
helper
check "and karchy does not decide again later" "$(selected)" "none"

new_home window-v1 nulifyer
mkdir -p "$(data)" "$HOME/.config/t3code"
helper
check "a window of the first T3 Code: not selected" "$(selected)" "none"

new_home xdg nulifyer
mkdir -p "$(data)" "$HOME/elsewhere/t3code-v2"
XDG_CONFIG_HOME=$HOME/elsewhere helper
check "the window's data under XDG_CONFIG_HOME counts too" "$(selected)" "none"

new_home environment nulifyer
mkdir -p "$(data)"
printf '{"defaultTheme": "grove", "defaultThemeSetAt": "2026-01-01T00:00:00.000Z"}\n' >"$(settings)"
helper
check "an environment theme of the user's own stays" "$(selected)" "grove"
check "untouched" "$(jq -r .defaultThemeSetAt "$(settings)")" "2026-01-01T00:00:00.000Z"

new_home published nulifyer
mkdir -p "$(data)/themes"
echo '{"name": "Mine"}' >"$(data)/themes/mine.json"
helper
check "a published theme of the user's own: not selected" "$(selected)" "none"
check "their theme file is untouched" "$(cat "$(data)/themes/mine.json")" '{"name": "Mine"}'

new_home home nulifyer
export T3CODE_HOME=$HOME/t3-elsewhere
mkdir -p "$T3CODE_HOME/userdata"
helper
check "T3CODE_HOME is followed" "$(jq -r .defaultTheme "$T3CODE_HOME/userdata/settings.json")" "karchy"
check "and ~/.t3 is not made" "$([[ -e $HOME/.t3 ]] || echo none)" "none"
unset T3CODE_HOME

new_home no-cli nulifyer
mkdir -p "$(data)"
PATH=$tmp/t3code-bin:$base_path karchy-theme-set-t3code
check "no t3 command: the file is written" "$([[ -f $(theme_file) ]] && echo yes)" "yes"
check "and nothing is decided yet" "$([[ -e $HOME/.local/state/karchy/t3code-theme-offered ]] || echo none)" "none"
helper
check "the next run with t3 selects it" "$(selected)" "karchy"

new_home launcher nulifyer
mkdir -p "$HOME/.t3/bin" "$(data)"
# shellcheck disable=SC2016
printf '#!/bin/bash\necho launcher >>"$HOME/launcher-ran"\nexec %q "$@"\n' "$tmp/t3-bin/t3" >"$HOME/.t3/bin/t3"
chmod +x "$HOME/.t3/bin/t3"
PATH=$base_path karchy-theme-set-t3code
check "the launcher T3 Code writes into its home is used first" "$(cat "$HOME/launcher-ran" 2>/dev/null)" "launcher"
check "and selects it" "$(selected)" "karchy"

new_home dotfile nulifyer
mkdir -p "$(data)" "$HOME/dotfiles"
printf '{"favorites": []}\n' >"$HOME/dotfiles/t3.json"
ln -s "$HOME/dotfiles/t3.json" "$(settings)"
helper
check "a linked settings file is not rewritten" "$(cat "$HOME/dotfiles/t3.json")" '{"favorites": []}'
check "and stays a link" "$([[ -L $(settings) ]] && echo link)" "link"

new_home broken nulifyer
mkdir -p "$(data)"
echo '{ not json' >"$(settings)"
helper
check "a settings file that isn't JSON is left as it is" "$(cat "$(settings)")" "{ not json"
check "the theme file is still written" "$([[ -f $(theme_file) ]] && echo yes)" "yes"

new_home unresolved nulifyer
mkdir -p "$(data)"
echo '{"accent": "{{ accent }}"}' >"$HOME/.local/state/karchy/current/theme/t3code.json"
helper 2>/dev/null
check "a theme with a colour missing is not published" "$([[ -e $(theme_file) ]] || echo none)" "none"
check "nor selected" "$(selected)" "none"

# ---- the migration ----------------------------------------------------------
migration=$(ls "$root"/migrations/*-t3code-theme.sh)
# shellcheck disable=SC2016
printf '#!/bin/bash\necho refreshed >>"$HOME/refresh-ran"\n' >"$tmp/bin/karchy-theme-refresh"
chmod +x "$tmp/bin/karchy-theme-refresh"
new_home migrate-absent nulifyer
before=$(snapshot)
PATH=$tmp/t3-bin:$base_path bash -euo pipefail "$migration"
check "migration, no T3 Code: nothing happens" "$(snapshot)" "$before"
new_home migrate-installed nulifyer
PATH=$installed_path bash -euo pipefail "$migration"
check "migration, installed and never started: selected" "$(selected)" "karchy"
check "and nothing else is applied again" "$([[ -e $HOME/refresh-ran ]] || echo no)" "no"
before=$(snapshot)
PATH=$installed_path bash -euo pipefail "$migration"
check "the migration twice changes nothing" "$(snapshot)" "$before"
new_home migrate-old nulifyer
mkdir -p "$(data)"
rm "$HOME/.local/state/karchy/current/theme/t3code.json"
PATH=$installed_path bash -euo pipefail "$migration"
check "migration, no rendered file: the theme is applied again" "$(cat "$HOME/refresh-ran" 2>/dev/null)" "refreshed"
rm "$tmp/bin/karchy-theme-refresh"

# ---- the commands that call it ----------------------------------------------
check "a theme change runs it" "$(grep -c '^  karchy-theme-set-t3code$' "$root/bin/karchy-theme-set")" "1"
check "Quick install runs it after an install" "$(grep -c 'karchy-theme-set-t3code' "$root/bin/karchy-quick-install")" "1"

# ---- the real t3 command ----------------------------------------------------
if [[ -x $app_dir/t3code && -f $app_dir/resources/app.asar ]]; then
  # The packaged app run as Node, as the helper does without a launcher. Its
  # HOME and T3CODE_HOME are the made-up ones, so nothing real is read.
  new_home real nulifyer
  T3CODE_APP_DIR=$app_dir PATH=$tmp/t3code-bin:$base_path karchy-theme-set-t3code
  check "real t3, never started: karchy is the environment theme" "$(selected)" "karchy"
  real_t3() { T3CODE_HOME=$HOME/.t3 ELECTRON_RUN_AS_NODE=1 "$app_dir/t3code" "$app_dir/resources/app.asar/apps/server/dist/bin.mjs" "$@" 2>&1; }
  check "real t3 theme show reads it back" "$(real_t3 theme show | head -1)" 'Environment theme: "karchy".'
  before=$(cat "$(settings)")
  T3CODE_APP_DIR=$app_dir PATH=$tmp/t3code-bin:$base_path karchy-theme-set-t3code
  check "real t3, a second run changes nothing" "$(cat "$(settings)")" "$before"
  real_t3 theme set ember >/dev/null
  T3CODE_APP_DIR=$app_dir PATH=$tmp/t3code-bin:$base_path karchy-theme-set-t3code
  check "real t3, switched away: stays theirs" "$(selected)" "ember"
else
  echo "skip: no T3 Code app at $app_dir, so the real t3 command isn't run"
fi

echo "passed: $pass, failed: $failures"
(( failures == 0 ))
