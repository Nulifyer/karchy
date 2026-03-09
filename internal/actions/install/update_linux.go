//go:build linux

package install

import (
	"github.com/nulifyer/karchy/internal/terminal"
)

// SystemUpdate runs a full system upgrade: keyrings, pacman, AUR, orphan cleanup, and kernel reboot check.
// SystemUpdate runs a full system upgrade and returns the terminal PID.
// The caller can wait on the PID to know when the update finishes.
func SystemUpdate() int {
	script := `
set -e
trap 'echo ""; echo -e "\033[1;31mSomething went wrong during the update! Review the output above.\033[0m"' ERR

BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

step() {
  local label="$1"; shift
  echo
  echo -e "${BOLD}${CYAN}$label${RESET}"
  echo -e "${DIM}────────────────────────────────────────${RESET}"
  "$@"
}

# Refresh keyrings
step "Refresh keyrings" \
  sudo pacman -Sy --noconfirm archlinux-keyring cachyos-keyring 2>/dev/null || \
  sudo pacman -Sy --noconfirm archlinux-keyring

# System update
step "Update system packages" \
  sudo pacman -Syu --noconfirm

# AUR updates (if paru is available and AUR packages exist)
if command -v paru &>/dev/null && pacman -Qem &>/dev/null; then
  step "Update AUR packages" \
    paru -Sua --noconfirm --cleanafter
fi

# Remove orphan packages
orphans=$(pacman -Qtdq 2>/dev/null || true)
if [[ -n $orphans ]]; then
  step "Remove orphan packages" \
    bash -c 'echo "$0" | sudo pacman -Rs --noconfirm -' "$orphans" || true
fi

# Kernel reboot check
echo
if [[ ! -d /usr/lib/modules/$(uname -r) ]]; then
  echo -e "${BOLD}${YELLOW}Kernel updated — a reboot is recommended.${RESET}"
fi

echo
echo -e "${BOLD}${GREEN}All done!${RESET}"
echo
read -rp "Press Enter to close..."
`
	pid, _ := terminal.LaunchShell(100, 30, "System Update", script)
	return pid
}
