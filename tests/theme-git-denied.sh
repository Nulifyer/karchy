#!/bin/bash
# What a theme installed from a git repo may ship (bin/karchy-theme-set,
# INSTALLED_THEME_DENIED), with karchy-theme-set's own staging functions in a
# made-up home:
#  - every template in default/themed is either denied or listed here as
#    colour only, so a new template is a decision, not an oversight
#  - a git theme's Lua, terminal configs, vscode.json, vesktop.css and
#    obsidian.css are not staged and are reported; its colour files are
#  - the templates then make vesktop.css and obsidian.css from the theme's
#    colours, and karchy-theme-set-obsidian puts karchy's file in a vault
#  - a theme folder without .git, or a link to one, is not held to the list
# Usage: tests/theme-git-denied.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

export KARCHY_PATH=$root HOME=$tmp/home PATH=$root/bin:/usr/bin:/bin
unset XDG_CONFIG_HOME
mkdir -p "$HOME"

# The list and the staging functions, as karchy-theme-set has them.
eval "$(sed -n '/^INSTALLED_THEME_DENIED=/p; /^IGNORED_THEME_FILES=/p' "$root/bin/karchy-theme-set")"
eval "$(sed -n '/^is_denied_installed_file() {/,/^THEME_NAME=/p' "$root/bin/karchy-theme-set" | sed '$d')"
check "the list was read" "$(( ${#INSTALLED_THEME_DENIED[@]} > 0 ))" "1"
check "the staging functions were read" "$(declare -F stage_installed_theme theme_came_from_a_repo report_ignored_theme_files | wc -l)" "3"

# ---- every template is a decision -------------------------------------------
# Colour only: they set colours and fonts and load nothing.
colour_only=(btop.theme chromium.theme claude.json fcitx5-theme.conf fish.fish gtk.css gtk4.css helix.toml
  hermes.yaml keyboard.rgb micro.micro pi.json shell.toml t3code.json vscode-theme.json)
for tpl in "$root"/default/themed/*.tpl; do
  name=$(basename "$tpl" .tpl)
  if is_denied_installed_file "$name"; then
    decided=denied
  elif [[ " ${colour_only[*]} " == *" $name "* ]]; then
    decided=colour
  else
    decided=undecided
  fi
  [[ $decided != undecided ]] || echo "FAIL: $name is a new template: deny it in karchy-theme-set or list it here as colour only"
  check "$name is denied or colour only" "$([[ $decided != undecided ]] && echo yes)" "yes"
done
for name in vesktop.css obsidian.css vscode.json kitty.conf neovim.lua hyprland.lua; do
  check "$name is denied" "$(is_denied_installed_file "$name" && echo denied)" "denied"
done

# ---- a theme cloned from a git repo -----------------------------------------
theme=$HOME/.config/karchy/themes/stranger
mkdir -p "$theme/.git" "$theme/backgrounds"
cp "$root/themes/catppuccin/colors.toml" "$theme/"
printf '1.png\n' >"$theme/backgrounds/1.png"
for name in obsidian.css vesktop.css; do
  printf '@import url("https://example.invalid/%s");\n.theme-dark { --background-primary: #000000; }\n' "$name" >"$theme/$name"
done
printf 'vim.cmd("!echo hi")\n' >"$theme/neovim.lua"
printf 'shell /bin/sh\n' >"$theme/kitty.conf"
printf '{}\n' >"$theme/vscode.json"
printf 'theme[main_bg]="#000000"\n' >"$theme/btop.theme"
printf 'A theme\n' >"$theme/README.md"

NEXT_THEME_PATH=$HOME/.local/state/karchy/current/next-theme USER_THEMES_PATH=$HOME/.config/karchy/themes THEME_NAME=stranger
mkdir -p "$NEXT_THEME_PATH"
check "a folder with .git came from a repo" "$(theme_came_from_a_repo "$theme" && echo yes)" "yes"
stage_installed_theme "$theme"
report=$(report_ignored_theme_files 2>&1)
check "what is reported" "$(head -n 1 <<<"$report")" \
  "Ignored in $HOME/.config/karchy/themes/stranger: kitty.conf neovim.lua obsidian.css vesktop.css vscode.json"
check "the reason names both CSS files" "$(grep -c 'vesktop.css or obsidian.css' <<<"$report")" "1"
for name in obsidian.css vesktop.css neovim.lua kitty.conf vscode.json; do
  check "$name is not staged" "$([[ -e $NEXT_THEME_PATH/$name ]] && echo staged || echo no)" "no"
done
for name in colors.toml btop.theme backgrounds/1.png; do
  check "$name is staged" "$([[ -e $NEXT_THEME_PATH/$name ]] && echo staged)" "staged"
done

karchy-theme-set-templates
mv "$NEXT_THEME_PATH" "$HOME/.local/state/karchy/current/theme"
current=$HOME/.local/state/karchy/current/theme
accent=$(sed -n 's/^accent *= *"\(#[0-9A-Fa-f]*\)".*/\1/p' "$root/themes/catppuccin/colors.toml")
for name in obsidian.css vesktop.css; do
  check "$name is karchy's own" "$(grep -c 'example.invalid' "$current/$name")" "0"
  check "$name has the theme's accent" "$(grep -qi -- "$accent" "$current/$name" && echo yes)" "yes"
done
check "obsidian.css is rendered from the template" "$(head -n 1 "$current/obsidian.css")" "/* Karchy Theme for Obsidian */"

# karchy-theme-set-obsidian copies it into each vault Obsidian knows.
vault=$HOME/Notes
mkdir -p "$vault/.obsidian" "$HOME/.config/obsidian"
jq -n --arg path "$vault" '{vaults: {a: {path: $path}}}' >"$HOME/.config/obsidian/obsidian.json"
karchy-theme-set-obsidian
check "the vault gets karchy's file" \
  "$(cmp -s "$current/obsidian.css" "$vault/.obsidian/themes/Karchy/theme.css" && echo same)" "same"

# ---- a theme of the user's own ----------------------------------------------
mine=$HOME/.config/karchy/themes/mine
mkdir -p "$mine"
check "a folder without .git is the user's" "$(theme_came_from_a_repo "$mine" || echo theirs)" "theirs"
rm -rf "$theme/.git"
ln -s "$theme" "$HOME/.config/karchy/themes/linked"
mkdir -p "$theme/.git"
check "a link to a working copy is the user's" "$(theme_came_from_a_repo "$HOME/.config/karchy/themes/linked" || echo theirs)" "theirs"

echo "passed: $pass, failed: $failures"
(( failures == 0 ))
