#!/usr/bin/env bash
# Karchy Installer for Linux/macOS
# Usage: curl -fsSL https://raw.githubusercontent.com/Nulifyer/karchy/main/.scripts/install.sh | bash
set -euo pipefail

REPO="Nulifyer/karchy"
INSTALL_DIR="${HOME}/.local/bin"

# Detect OS and architecture
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    *)
        echo "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

case "$OS" in
    linux|darwin) ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

BINARY_NAME="karchy-${OS}-${ARCH}"

echo "Installing Karchy for ${OS}/${ARCH}..."

# 1. Get latest release URL
TAG=$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)
if [ -z "$TAG" ]; then
    echo "ERROR: Could not fetch latest release"
    exit 1
fi
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${BINARY_NAME}"

# 2. Download binary
echo "  Downloading ${TAG}..."
mkdir -p "$INSTALL_DIR"
TMP_FILE=$(mktemp)
curl -fsSL "$DOWNLOAD_URL" -o "$TMP_FILE"
chmod +x "$TMP_FILE"
mv "$TMP_FILE" "${INSTALL_DIR}/karchy"
echo "  Downloaded to ${INSTALL_DIR}/karchy"

# 3. Check PATH
case ":$PATH:" in
    *":${INSTALL_DIR}:"*) ;;
    *)
        echo "  NOTE: ${INSTALL_DIR} is not in your PATH."
        echo "  Add this to your shell rc file:"
        echo "    export PATH=\"\$HOME/.local/bin:\$PATH\""
        ;;
esac

# 4. Run self-install (registers autostart, checks deps, starts daemon)
"${INSTALL_DIR}/karchy" install

echo ""
echo "Karchy ${TAG} installed!"
