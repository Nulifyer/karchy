#!/usr/bin/env bash
# Karchy Uninstaller for Linux/macOS
# Usage: curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/uninstall.sh | bash
set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
KARCHY="${INSTALL_DIR}/karchy"

echo "Uninstalling Karchy..."

# 1. Run self-uninstall (stops daemon, removes autostart)
if [ -x "$KARCHY" ]; then
    "$KARCHY" uninstall || true
fi

# 2. Remove binary
rm -f "$KARCHY"
echo "  Removed ${KARCHY}"

echo ""
echo "Karchy uninstalled."
