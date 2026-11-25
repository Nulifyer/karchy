# The boot menu's letters are Limine's own font, doubled both ways (D-182),
# no longer a font of karchy's on the ESP (D-121, D-154). The package brings
# the new limine-brand; this has it write its block of limine.conf again and
# remove the font files from the ESP, which no package owns. Every user of
# the machine runs it; only the first changes anything.
limine=/etc/default/limine
brand=/usr/lib/karchy/limine-brand

[[ -f $limine ]] || { echo "$limine not found: not a karchy boot setup, nothing to do"; exit 0; }
[[ -x $brand ]] || { echo "$brand is not installed"; exit 1; }

esp=$(sed -n 's/^ESP_PATH=["'\'']\?\([^"'\'']*\).*/\1/p' "$limine" | tail -n 1)
config=${esp:-/boot}/limine.conf
# Reading the ESP needs root. Without sudo (no password to give it) this
# fails here rather than taking an unreadable menu for one without a block.
sudo true
# A menu without karchy's block was never branded, or someone took the block
# out: it stays as it is.
sudo grep -qs '^### karchy: begin' "$config" || { echo "$config has no karchy block: the menu stays as it is"; exit 0; }

sudo "$brand"
if sudo grep -q '^term_font: ' "$config"; then
  echo "$config still names a font file after limine-brand"
  exit 1
fi
