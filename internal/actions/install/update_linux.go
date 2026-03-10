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

// FirmwareUpdate runs fwupdmgr to check and install firmware updates.
func FirmwareUpdate() {
	script := `
set -e
echo -e "\033[1;36mChecking for firmware updates...\033[0m"
echo
fwupdmgr refresh --force 2>/dev/null || true
fwupdmgr get-updates 2>/dev/null || echo -e "\033[1;32mNo firmware updates available.\033[0m"
echo
read -rp "Install available updates? [Y/n] " ans
if [[ -z "$ans" || "$ans" =~ ^[Yy] ]]; then
    fwupdmgr update || true
fi
echo
read -rp "Press Enter to close..."
`
	terminal.LaunchShell(100, 25, "Firmware Update", script)
}

// MirrorUpdate refreshes the pacman mirrorlist.
func MirrorUpdate() {
	script := `
set -e
echo -e "\033[1;36mUpdating mirror list...\033[0m"
echo
if command -v rate-mirrors &>/dev/null; then
    echo "Using rate-mirrors..."
    rate-mirrors --allow-root --protocol https arch | sudo tee /etc/pacman.d/mirrorlist
elif command -v reflector &>/dev/null; then
    echo "Using reflector..."
    sudo reflector --latest 20 --protocol https --sort rate --save /etc/pacman.d/mirrorlist
elif command -v rankmirrors &>/dev/null; then
    echo "Using rankmirrors..."
    curl -s "https://archlinux.org/mirrorlist/?country=all&protocol=https&use_mirror_status=on" | sed 's/^#Server/Server/' | rankmirrors -n 10 - | sudo tee /etc/pacman.d/mirrorlist
else
    echo -e "\033[1;31mNo mirror ranking tool found (rate-mirrors, reflector, or rankmirrors).\033[0m"
    echo "Install one: sudo pacman -S rate-mirrors"
fi
echo
echo -e "\033[1;32mDone!\033[0m"
echo
read -rp "Press Enter to close..."
`
	terminal.LaunchShell(100, 25, "Mirror Update", script)
}
