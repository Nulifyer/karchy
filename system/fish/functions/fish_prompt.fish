# karchy's fish prompt (components.md): karchy's mark, user@host, the folder,
# the git branch (or short commit when detached), and a › that turns red when
# the last command failed. Earlier prompts collapse to the ›, so scrollback
# shows commands, not prompts. Colors follow the current theme. A
# fish_prompt.fish in ~/.config/fish/functions replaces this one.
function fish_prompt
    set -l last_status $status
    # fish redraws an accepted command's prompt with --final-rendering.
    set -g fish_transient_prompt 1

    set -l colors ~/.local/state/karchy/current/theme/fish.fish
    test -r $colors; and source $colors
    set -q karchy_prompt_path; or set -g karchy_prompt_path cyan
    set -q karchy_prompt_user; or set -g karchy_prompt_user yellow
    set -q karchy_prompt_git; or set -g karchy_prompt_git green
    set -q karchy_prompt_muted; or set -g karchy_prompt_muted brblack
    set -q karchy_prompt_error; or set -g karchy_prompt_error red

    # The mark is U+100000 in karchy Symbols (the karchy package), which
    # fontconfig finds whatever the text font is. The console's font has
    # neither it nor the Nerd Font icons.
    set -l logo 􀀀' '
    set -l branch_icon ' '
    set -l end 
    if test "$TERM" = linux
        set logo ''
        set branch_icon ''
        set end '>'
    end

    if contains -- --final-rendering $argv
        set_color $karchy_prompt_muted
        echo -n "$end "
        set_color normal
        return
    end

    set_color $karchy_prompt_muted
    echo -n $logo
    set_color $karchy_prompt_user
    echo -n (whoami)@(prompt_hostname)' '
    set_color $karchy_prompt_path
    echo -n (prompt_pwd)' '

    set -l branch (command git symbolic-ref --quiet --short HEAD 2>/dev/null; or command git rev-parse --short HEAD 2>/dev/null)
    if test -n "$branch"
        set_color $karchy_prompt_git
        echo -n "$branch_icon$branch "
    end

    if test $last_status -eq 0
        set_color $karchy_prompt_git
    else
        set_color $karchy_prompt_error
    end
    echo -n "$end "
    set_color normal
end
