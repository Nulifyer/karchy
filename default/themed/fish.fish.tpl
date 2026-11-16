# karchy prompt colors from the current theme (default/themed/fish.fish.tpl),
# read by karchy's fish_prompt on every prompt so a theme switch shows at once.
set -g karchy_prompt_path {{ accent_strip }}
set -g karchy_prompt_git {{ green_strip }}
set -g karchy_prompt_dirty {{ yellow_strip }}
set -g karchy_prompt_muted {{ muted_strip }}
set -g karchy_prompt_error {{ red_strip }}
