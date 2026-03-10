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

# Stop daemon if running
LOCKFILE="${XDG_CACHE_HOME:-$HOME/.cache}/karchy-daemon.lock"
if [[ -x "$EXE" ]]; then
    echo "Stopping daemon..."
    "$EXE" daemon stop 2>/dev/null || true
    sleep 5
    # Only kill the daemon PID from the lockfile, not all karchy processes
    if [[ -f "$LOCKFILE" ]]; then
        DPID=$(cat "$LOCKFILE" 2>/dev/null || true)
        if [[ -n "$DPID" ]] && kill -0 "$DPID" 2>/dev/null; then
            echo "Force killing daemon (pid $DPID)..."
            kill -9 "$DPID" 2>/dev/null || true
        fi
        rm -f "$LOCKFILE"
    fi
fi

# Build
cd "$REPO_ROOT"
go build -ldflags "-s -w -X main.Version=$VERSION" -o karchy .

# Install
mkdir -p "$INSTALL_DIR"
mv karchy "$EXE"
chmod +x "$EXE"

echo "Installed $EXE ($VERSION)"

# Restart daemon
echo "Starting daemon..."
"$EXE" daemon start

echo "Done!"
