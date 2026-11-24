# The boot menu's letters are drawn from an 8x32 font at 2x1, not an 8x16 one
# doubled both ways (D-154). The package brings the font and limine-brand;
# this has limine-brand write its block of limine.conf again and put the font
# on the ESP, which no package owns. Every user of the machine runs it; only
# the first changes anything.
limine=/etc/default/limine
brand=/usr/lib/karchy/limine-brand

[[ -f $limine ]] || { echo "$limine not found: not a karchy boot setup, nothing to do"; exit 0; }
[[ -x $brand ]] || { echo "$brand is not installed"; exit 1; }

esp=$(sed -n 's/^ESP_PATH=["'\'']\?\([^"'\'']*\).*/\1/p' "$limine" | tail -n 1)
config=${esp:-/boot}/limine.conf
# A menu without karchy's block was never branded, or someone took the block
# out: it stays as it is.
sudo grep -qs '^### karchy: begin' "$config" || { echo "$config has no karchy block: the menu stays as it is"; exit 0; }

sudo "$brand"
sudo grep -q '^term_font_size: 8x32$' "$config" || { echo "$config still has the old font after limine-brand"; exit 1; }
