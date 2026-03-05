#!/bin/bash
# Karchy installer
# Clones the repo and sets up PATH, keybinding, and desktop entry.
# Run: curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/install.sh | bash
set -euo pipefail

REPO_URL="https://github.com/Nulifyer/karchy.git"
INSTALL_DIR="$HOME/.local/share/karchy"
BIN_DIR="$INSTALL_DIR/bin"
SKIP_DEPS=false

for arg in "$@"; do
  case "$arg" in
    --no-deps) SKIP_DEPS=true ;;
  esac
done

echo "Installing karchy..."

# ── Dependencies ────────────────────────────────────────────────────────────
if [[ "$SKIP_DEPS" == false ]]; then
  PACKAGES=(fuzzel gum alacritty networkmanager fzf chafa python-pyqt6 pacman-contrib)
  AUR_PACKAGES=(paru-git)
  echo "Checking dependencies..."
  sudo pacman -S --needed --noconfirm "${PACKAGES[@]}"
  if command -v paru &>/dev/null; then
    paru -S --needed --noconfirm "${AUR_PACKAGES[@]}"
  else
    echo "  paru not found, installing paru-git from AUR manually..."
    tmpdir=$(mktemp -d)
    git clone https://aur.archlinux.org/paru-git.git "$tmpdir/paru-git"
    (cd "$tmpdir/paru-git" && makepkg -si --noconfirm)
    rm -rf "$tmpdir"
  fi
fi

# ── Clone / update repo ───────────────────────────────────────────────────
echo ""
if [[ -d "$INSTALL_DIR/.git" ]]; then
  echo "Updating existing installation..."
  git -C "$INSTALL_DIR" pull --ff-only
else
  if [[ -d "$INSTALL_DIR" ]]; then
    rm -rf "$INSTALL_DIR"
  fi
  echo "Cloning karchy to $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

chmod +x "$BIN_DIR"/*

# ── PATH (detect user's shell) ───────────────────────────────────────────────
USER_SHELL="$(basename "$SHELL")"

case "$USER_SHELL" in
  fish)
    FISH_CONFIG="$HOME/.config/fish/config.fish"
    mkdir -p "$(dirname "$FISH_CONFIG")"
    if ! grep -q 'karchy/bin' "$FISH_CONFIG" 2>/dev/null; then
      printf '\n# Karchy\nfish_add_path -g $HOME/.local/share/karchy/bin\n' >> "$FISH_CONFIG"
      echo "  added karchy/bin to PATH in config.fish"
    fi
    ;;
  zsh)
    if ! grep -q 'karchy/bin' "$HOME/.zshrc" 2>/dev/null; then
      printf '\n# Karchy\nexport PATH="$HOME/.local/share/karchy/bin:$PATH"\n' >> "$HOME/.zshrc"
      echo "  added karchy/bin to PATH in .zshrc"
    fi
    ;;
  bash)
    if ! grep -q 'karchy/bin' "$HOME/.bashrc" 2>/dev/null; then
      printf '\n# Karchy\nexport PATH="$HOME/.local/share/karchy/bin:$PATH"\n' >> "$HOME/.bashrc"
      echo "  added karchy/bin to PATH in .bashrc"
    fi
    ;;
  *)
    echo "  warning: unknown shell ($USER_SHELL), add $BIN_DIR to your PATH manually"
    ;;
esac

# ── Fuzzel config (set terminal for Terminal=true apps) ──────────────────────
FUZZEL_INI="$HOME/.config/fuzzel/fuzzel.ini"
mkdir -p "$(dirname "$FUZZEL_INI")"
if [[ ! -f "$FUZZEL_INI" ]]; then
  printf '[main]\nterminal=%s/karchy-terminal -e\n' "$BIN_DIR" > "$FUZZEL_INI"
  echo "  created fuzzel config with karchy-terminal wrapper"
elif ! grep -q '^terminal=' "$FUZZEL_INI"; then
  sed -i '/^\[main\]/a terminal='"$BIN_DIR"'/karchy-terminal -e' "$FUZZEL_INI"
  echo "  added karchy-terminal to fuzzel config"
fi

# ── KWin rule (borderless centered popup for karchy-float) ──────────────────
KWINRULES="$HOME/.config/kwinrulesrc"
KARCHY_RULE_ID="karchy-float-popup-rule"

kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key Description "Karchy Popup"
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key wmclass "karchy-float"
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key wmclassmatch 2
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key noborder true
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key noborderrule 2
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key placement 5
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key placementrule 2
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key above true
kwriteconfig6 --file "$KWINRULES" --group "$KARCHY_RULE_ID" --key aboverule 2

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

echo "  applied KWin rule for borderless centered popups"

# ── KWin rule (default size for karchy web apps) ─────────────────────────────
WEBAPP_RULE_ID="karchy-webapp-size-rule"

kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key Description "Karchy Web App Default Size"
kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key wmclass -- '-Default$'
kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key wmclassmatch 3
kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key size "1280,800"
kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key sizerule 4
kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key placement 5
kwriteconfig6 --file "$KWINRULES" --group "$WEBAPP_RULE_ID" --key placementrule 4

existing_rules=$(kreadconfig6 --file "$KWINRULES" --group General --key rules 2>/dev/null || true)
if [[ "$existing_rules" != *"$WEBAPP_RULE_ID"* ]]; then
  existing_count=$(kreadconfig6 --file "$KWINRULES" --group General --key count 2>/dev/null || echo 0)
  if [[ -n "$existing_rules" ]]; then
    new_rules="${existing_rules},${WEBAPP_RULE_ID}"
  else
    new_rules="$WEBAPP_RULE_ID"
  fi
  kwriteconfig6 --file "$KWINRULES" --group General --key rules "$new_rules"
  kwriteconfig6 --file "$KWINRULES" --group General --key count $((existing_count + 1))
fi

qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
echo "  applied KWin rules"

# ── Desktop entry (for KDE shortcut binding) ────────────────────────────────
DESKTOP_FILE="$HOME/.local/share/applications/karchy-menu.desktop"
cat > "$DESKTOP_FILE" << EOF
[Desktop Entry]
Name=Karchy Menu
Comment=Karchy system menu launcher
Exec=$BIN_DIR/karchy-menu
Icon=utilities-terminal
Type=Application
Categories=System;Utility;
StartupNotify=false
EOF
echo "  created karchy-menu.desktop"

# ── Keybinding (Super+Space → karchy-menu) ──────────────────────────────────
SHORTCUTS="$HOME/.config/kglobalshortcutsrc"

kwriteconfig6 --file "$SHORTCUTS" \
  --group "services" --group "org.kde.krunner.desktop" \
  --key "_launch" "none"

kwriteconfig6 --file "$SHORTCUTS" \
  --group "services" --group "karchy-menu.desktop" \
  --key "_launch" "Meta+Space"

update-desktop-database "$HOME/.local/share/applications/" 2>/dev/null || true
kbuildsycoca6 2>/dev/null || true
systemctl --user restart plasma-krunner.service 2>/dev/null || true
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
echo "  bound Super+Space to karchy-menu (may need logout/login)"

# ── Update notifier (systemd user units) ─────────────────────────────────
SYSTEMD_USER_DIR="$HOME/.config/systemd/user"
mkdir -p "$SYSTEMD_USER_DIR"

for unit in "$INSTALL_DIR"/systemd/*; do
  cp "$unit" "$SYSTEMD_USER_DIR/"
  echo "  installed $(basename "$unit")"
done

systemctl --user daemon-reload
systemctl --user enable --now karchy-update-notifier.service 2>/dev/null || true
systemctl --user enable --now karchy-update-check.timer 2>/dev/null || true
echo "  enabled update notifier and check timer"

echo ""
echo "Done! Restart your shell to pick up PATH changes."
