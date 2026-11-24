# The VPN is part of karchy (D-156): karchy-settings installs it at the paths
# the karchy-vpn add-on used, so a VPN set up with the add-on carries on
# with its configuration, mode and units. The add-on became an empty
# transitional package; marked as a dependency, the next `karchy update`
# removes it (default/karchy/retired-packages).
if [[ -n $(pacman -Qqe karchy-vpn 2>/dev/null) ]]; then
  sudo pacman -D --asdeps karchy-vpn >/dev/null
fi

# The add-on's shield in the bar is gone: the network icon shows the VPN,
# and its panel has the details. Its place in the bar layout goes too.
config=${XDG_CONFIG_HOME:-$HOME/.config}/karchy/shell.json
if [[ -f $config ]] &&
  jq -e '[.bar.layout // {} | .[] | arrays | .[] | select((.id? // .) == "karchy.vpn")] | length > 0' "$config" >/dev/null 2>&1; then
  tmp=$(mktemp "$config.XXXXXX")
  jq '.bar.layout |= with_entries(if (.value | type) == "array" then .value |= map(select((.id? // .) != "karchy.vpn")) else . end)' \
    "$config" >"$tmp"
  mv -f "$tmp" "$config"
fi
