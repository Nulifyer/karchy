# The boot menu's block in limine.conf, written again where the old one came
# back (D-182, D-186). On a machine where limine-snapper-sync wrote
# limine.conf from a copy it read just before the D-182 migration, the block
# still names karchy's old 8x32 font, which that migration removed from the
# ESP: Limine falls back to its own 8x16 font at the old 2x1, and the letters
# are squashed. limine-brand now holds limine's boot-partition lock, so this
# write is not undone. Every user of the machine runs it; only the first
# changes anything.
limine=/etc/default/limine
brand=/usr/lib/karchy/limine-brand

[[ -f $limine ]] || { echo "$limine not found: not a karchy boot setup, nothing to do"; exit 0; }
[[ -x $brand ]] || { echo "$brand is not installed"; exit 1; }

esp=$(sed -n 's/^ESP_PATH=["'\'']\?\([^"'\'']*\).*/\1/p' "$limine" | tail -n 1)
config=${esp:-/boot}/limine.conf
# Reading the ESP needs root. Without sudo (no password to give it) this
# fails here rather than taking an unreadable menu for a right one.
sudo true
sudo grep -qs '^### karchy: begin' "$config" || { echo "$config has no karchy block: the menu stays as it is"; exit 0; }
old='^term_font: |^term_font_size: |^term_font_scale: 2x1$'
sudo grep -qE "$old" "$config" || { echo "the boot menu already uses Limine's own font"; exit 0; }

sudo "$brand"
if sudo grep -qE "$old" "$config"; then
  echo "$config still has the old font lines after limine-brand"
  exit 1
fi
