#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
INSTALL_DIR="$HOME/.local/share/karchy/bin"

echo "Installing karchy to $INSTALL_DIR"

mkdir -p "$INSTALL_DIR"

for script in "$REPO_DIR"/bin/*; do
  name=$(basename "$script")
  cp "$script" "$INSTALL_DIR/$name"
  chmod +x "$INSTALL_DIR/$name"
  echo "  installed $name"
done

# Ensure PATH entry exists in .zshrc
if ! grep -q 'karchy/bin' "$HOME/.zshrc" 2>/dev/null; then
  printf '\n# Karchy\nexport PATH="$HOME/.local/share/karchy/bin:$PATH"\n' >> "$HOME/.zshrc"
  echo "  added karchy/bin to PATH in .zshrc"
fi

echo "Done! Restart your shell or run: source ~/.zshrc"
