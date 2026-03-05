#!/bin/bash
set -euo pipefail

INSTALL_DIR="$HOME/.local/share/karchy/bin"

echo "Uninstalling karchy..."

# ── Systemd units ──────────────────────────────────────────────────────────
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
systemctl --user disable --now karchy-update-notifier.service 2>/dev/null || true
systemctl --user disable --now karchy-update-check.timer 2>/dev/null || true
rm -f "$SYSTEMD_USER_DIR"/karchy-update-notifier.service
rm -f "$SYSTEMD_USER_DIR"/karchy-update-check.timer
systemctl --user daemon-reload
echo "  removed systemd units"

# ── Keybinding ─────────────────────────────────────────────────────────────
SHORTCUTS="$HOME/.config/kglobalshortcutsrc"
if [[ -f "$SHORTCUTS" ]]; then
  kwriteconfig6 --file "$SHORTCUTS" \
    --group "services" --group "karchy-menu.desktop" \
    --key "_launch" "none" 2>/dev/null || true
  echo "  removed keybinding"
fi

# ── Desktop entry ──────────────────────────────────────────────────────────
rm -f "$HOME/.local/share/applications/karchy-menu.desktop"
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
echo "  removed desktop entry"

# ── KWin rules ─────────────────────────────────────────────────────────────
KWINRULES="$HOME/.config/kwinrulesrc"
KARCHY_RULE_ID="karchy-float-popup-rule"
WEBAPP_RULE_ID="karchy-webapp-size-rule"

for rule_id in "$KARCHY_RULE_ID" "$WEBAPP_RULE_ID"; do
  kwriteconfig6 --file "$KWINRULES" --group "$rule_id" --key Description --delete 2>/dev/null || true
  # Remove the entire group by deleting all known keys
  for key in wmclass wmclassmatch noborder noborderrule placement placementrule above aboverule size sizerule Description; do
    kwriteconfig6 --file "$KWINRULES" --group "$rule_id" --key "$key" --delete 2>/dev/null || true
  done

  # Remove from the rules list
  existing_rules=$(kreadconfig6 --file "$KWINRULES" --group General --key rules 2>/dev/null || true)
  if [[ "$existing_rules" == *"$rule_id"* ]]; then
    new_rules=$(echo "$existing_rules" | sed "s/,${rule_id}//;s/${rule_id},//;s/${rule_id}//")
    existing_count=$(kreadconfig6 --file "$KWINRULES" --group General --key count 2>/dev/null || echo 0)
    kwriteconfig6 --file "$KWINRULES" --group General --key rules "$new_rules"
    kwriteconfig6 --file "$KWINRULES" --group General --key count $((existing_count - 1))
  fi
done

qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
echo "  removed KWin rules"

# ── Fuzzel config ──────────────────────────────────────────────────────────
FUZZEL_INI="$HOME/.config/fuzzel/fuzzel.ini"
if [[ -f "$FUZZEL_INI" ]]; then
  sed -i '/karchy-terminal/d' "$FUZZEL_INI"
  echo "  cleaned fuzzel config"
fi

# ── PATH from shell config ────────────────────────────────────────────────
for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/fish/config.fish"; do
  if [[ -f "$rc" ]] && grep -q 'karchy/bin' "$rc"; then
    sed -i '/# Karchy/d;/karchy\/bin/d' "$rc"
    echo "  removed PATH entry from $(basename "$rc")"
  fi
done

# ── Scripts ────────────────────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR" ]]; then
  rm -rf "$INSTALL_DIR"
  echo "  removed $INSTALL_DIR"
fi

# Clean up empty parent dir
rmdir "$HOME/.local/share/karchy" 2>/dev/null || true

echo ""
echo "Done! Restart your shell to pick up PATH changes."
