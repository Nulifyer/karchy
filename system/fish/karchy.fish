# karchy: the same environment for fish outside the session (TTY, SSH).
# Dev mode (/etc/karchy.conf, D-55) applies to users only: root keeps the
# packaged copy, because the checkout is writable by its user (D-50).
set -gx KARCHY_PATH /usr/share/karchy
# Terminal editor for git, sudoedit and friends; your own EDITOR wins.
set -q EDITOR; or set -gx EDITOR micro
if test (id -u) -ne 0; and test -r /etc/karchy.conf
    set -l dev (string replace -rf '^KARCHY_PATH=["\']?([^"\']*)["\']?$' '$1' < /etc/karchy.conf)
    if test -n "$dev"
        set -gx KARCHY_PATH $dev[-1]
        fish_add_path --global --path $KARCHY_PATH/bin
    end
end
