# A theme installed from a git repo can no longer supply obsidian.css (D-166):
# CSS in Obsidian can fetch from an address its author chose. When the theme
# applied now is such a theme and ships one, it is applied again, which puts
# karchy's own obsidian.css, made from the theme's colours, in place of it in
# every vault. Any other theme already has karchy's file.
#
# stdin is not the terminal, so the browser's part of a theme change can't
# stop to ask for a password while this output goes to a log.
name=$(cat "$HOME/.local/state/karchy/current/theme.name" 2>/dev/null || true)
theme=$HOME/.config/karchy/themes/$name
if [[ -n $name && ! -L $theme && -d $theme/.git && -f $theme/obsidian.css ]]; then
  karchy-theme-refresh </dev/null
fi
