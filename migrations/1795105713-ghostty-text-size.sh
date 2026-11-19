# Ghostty scales its font by GTK's text scale, so at any text size but the
# default it came out larger than the other terminals (13pt at text size 16
# showed as 17.7pt). karchy-display-text-size now writes Ghostty's size
# divided by that scale; writing the files again from the current size fixes
# a machine set before. Only ghostty.conf changes; the others are rewritten
# to the same text, which leaves them alone.
karchy-display-text-size sync
