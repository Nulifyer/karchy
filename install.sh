#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/karchy/bin"

echo "Installing karchy..."

# ── Dependencies ────────────────────────────────────────────────────────────
PACKAGES=(fuzzel gum alacritty paru networkmanager)
AUR_PACKAGES=(gazelle-tui)

echo "Checking dependencies..."
sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"
paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"

# ── Scripts ─────────────────────────────────────────────────────────────────
echo ""
echo "Installing scripts to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"

for script in "$REPO_DIR"/bin/*; do
  name=$(basename "$script")
  cp "$script" "$INSTALL_DIR/$name"
  chmod +x "$INSTALL_DIR/$name"
  echo "  installed $name"
done

# ── PATH (fish) ─────────────────────────────────────────────────────────────
FISH_CONFIG="$HOME/.config/fish/config.fish"
if [[ -f "$FISH_CONFIG" ]] || [[ "$(basename "$SHELL")" == "fish" ]]; then
  mkdir -p "$(dirname "$FISH_CONFIG")"
  if ! grep -q 'karchy/bin' "$FISH_CONFIG" 2>/dev/null; then
    printf '\n# Karchy\nfish_add_path -g $HOME/.local/share/karchy/bin\n' >> "$FISH_CONFIG"
    echo "  added karchy/bin to PATH in config.fish"
  fi
fi

# ── PATH (zsh) ──────────────────────────────────────────────────────────────
if [[ -f "$HOME/.zshrc" ]]; then
  if ! grep -q 'karchy/bin' "$HOME/.zshrc" 2>/dev/null; then
    printf '\n# Karchy\nexport PATH="$HOME/.local/share/karchy/bin:$PATH"\n' >> "$HOME/.zshrc"
    echo "  added karchy/bin to PATH in .zshrc"
  fi
fi

# ── PATH (bash) ─────────────────────────────────────────────────────────────
if [[ -f "$HOME/.bashrc" ]]; then
  if ! grep -q 'karchy/bin' "$HOME/.bashrc" 2>/dev/null; then
    printf '\n# Karchy\nexport PATH="$HOME/.local/share/karchy/bin:$PATH"\n' >> "$HOME/.bashrc"
    echo "  added karchy/bin to PATH in .bashrc"
  fi
fi

# ── KWin rule (borderless centered popup for karchy-float) ──────────────────
KWINRULES="$HOME/.config/kwinrulesrc"
KARCHY_RULE_ID="karchy-float-popup-rule"

# Always write/update the rule values
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key Description "Karchy Popup"
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key wmclass "karchy-float"
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key wmclassmatch 2
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key noborder true
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key noborderrule 2
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key placement 5
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key placementrule 2
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key above true
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key aboverule 2

# Register the rule if not already in the list
existing_rules=$(kreadconfig6 --file "$KWINRULES" --group General --key rules 2>/dev/null || true)
if [[ "$existing_rules" != *"$KARCHY_RULE_ID"* ]]; then
  existing_count=$(kreadconfig6 --file "$KWINRULES" --group General --key count 2>/dev/null || echo 0)
  if [[ -n "$existing_rules" ]]; then
    new_rules="${existing_rules},${KARCHY_RULE_ID}"
  else
    new_rules="$KARCHY_RULE_ID"
  fi
  kwriteconfig6 --file "$KWINRULES" --group General --key rules "$new_rules"
  kwriteconfig6 --file "$KWINRULES" --group General --key count $((existing_count + 1))
fi

qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
echo "  applied KWin rule for borderless centered popups"

# ── Desktop entry (for KDE shortcut binding) ────────────────────────────────
DESKTOP_FILE="$HOME/.local/share/applications/karchy-menu.desktop"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Karchy Menu
Comment=Karchy system menu launcher
Exec=$INSTALL_DIR/karchy-menu
Icon=utilities-terminal
Type=Application
Categories=System;Utility;
EOF
echo "  created karchy-menu.desktop"

# ── Keybinding (Super+Space → karchy-menu) ──────────────────────────────────
SHORTCUTS="$HOME/.config/kglobalshortcutsrc"

# Unbind Meta+Space from KRunner
kwriteconfig6 --file "$SHORTCUTS" \
  --group "services" --group "org.kde.krunner.desktop" \
  --key "_launch" "none"

# Bind Meta+Space to karchy-menu
kwriteconfig6 --file "$SHORTCUTS" \
  --group "services" --group "karchy-menu.desktop" \
  --key "_launch" "Meta+Space"

# Reload
update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
systemctl --user restart plasma-krunner.service 2>/dev/null || true
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
echo "  bound Super+Space to karchy-menu (may need logout/login)"

echo ""
echo "Done! Restart your shell or run: source ~/.config/fish/config.fish"
