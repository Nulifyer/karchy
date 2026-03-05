#!/bin/bash
# One-liner installer for karchy:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/remote-install.sh)

set -euo pipefail

REPO_URL="https://github.com/Nulifyer/karchy.git"
CACHE_DIR="$HOME/.cache/karchy"

echo "Downloading karchy..."
rm -rf "$CACHE_DIR"
git clone "$REPO_URL" "$CACHE_DIR"

bash "$CACHE_DIR/install.sh"
