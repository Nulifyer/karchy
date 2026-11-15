# karchy's fish prompt (components.md): the folder, the git branch with a mark
# when tracked files changed, how long the last command took (from 2 s), and
# its exit code when it failed. Colors follow the current theme. A
# fish_prompt.fish in ~/.config/fish/functions replaces this one.
function fish_prompt
    set -l last_status $status
    set -l duration $CMD_DURATION

    set -l colors ~/.local/state/karchy/current/theme/fish.fish
    test -r $colors; and source $colors
    set -q karchy_prompt_path; or set -g karchy_prompt_path cyan
    set -q karchy_prompt_git; or set -g karchy_prompt_git green
    set -q karchy_prompt_dirty; or set -g karchy_prompt_dirty yellow
    set -q karchy_prompt_muted; or set -g karchy_prompt_muted brblack
    set -q karchy_prompt_error; or set -g karchy_prompt_error red

    set_color $karchy_prompt_path
    echo -n (prompt_pwd)

    # Branch, or the short commit when detached. Only tracked files count as
    # changes, which keeps this quick in large repositories.
    set -l branch (command git symbolic-ref --short HEAD 2>/dev/null; or command git rev-parse --short HEAD 2>/dev/null)
    if test -n "$branch"
        set_color $karchy_prompt_git
        echo -n " $branch"
        if not command git diff --quiet --ignore-submodules HEAD 2>/dev/null
            set_color $karchy_prompt_dirty
            echo -n "*"
        end
    end

    if test "$duration" -ge 2000 2>/dev/null
        set_color $karchy_prompt_muted
        if test $duration -ge 60000
            echo -n " "(math --scale=0 $duration / 60000)"m"(math --scale=0 "$duration % 60000 / 1000")"s"
        else
            echo -n " "(math --scale=1 $duration / 1000)"s"
        end
    end

    if test $last_status -ne 0
        set_color $karchy_prompt_error
        echo -n " ✗$last_status"
    end

    set_color $karchy_prompt_path
    echo -n " ❯ "
    set_color normal
end
