#!/usr/bin/env bash
# dev-deploy.sh — Build and install dev binary to production path
# Usage: ./.scripts/dev-deploy.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT_SHORT="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
VERSION="dev-$COMMIT_SHORT"

# Determine install path
if [[ "$(uname)" == "Darwin" ]]; then
    INSTALL_DIR="$HOME/.local/bin"
else
    INSTALL_DIR="$HOME/.local/bin"
fi
EXE="$INSTALL_DIR/karchy"

echo "Building karchy $VERSION ..."

# Kill all karchy processes
if pkill -9 karchy 2>/dev/null; then
    echo "Killed karchy processes"
fi
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/karchy-daemon.lock"

# Build
cd "$REPO_ROOT"
go build -ldflags "-s -w -X main.Version=$VERSION" -o karchy .

# Clear logs
rm -f ~/.config/karchy/karchy.log

# Install
mkdir -p "$INSTALL_DIR"
mv karchy "$EXE"
chmod +x "$EXE"

echo "Installed $EXE ($VERSION)"

# Start daemon in debug mode via systemd user session
echo "Starting daemon (debug mode)..."
systemctl --user stop karchy.service 2>/dev/null || true
systemctl --user reset-failed karchy.service 2>/dev/null || true
systemctl --user stop karchy-dev.service 2>/dev/null || true
systemctl --user reset-failed karchy-dev.service 2>/dev/null || true
systemd-run --user --unit=karchy-dev --description="Karchy (dev)" "$EXE" --debug daemon run

echo "Done! Log: ${XDG_CONFIG_HOME:-$HOME/.config}/karchy/karchy.log"
