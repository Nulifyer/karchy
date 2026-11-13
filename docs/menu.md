# Menu

The Omarchy menu engine with a karchy tree (D-18). Super+Space opens it, and typing searches apps. Tags: [O] Omarchy entry kept, [New] karchy addition.

- **Apps:** search installed desktop apps [O].
- **Packages**
  - Install package: fzf over repo packages, `pacman -Sii` preview, multi-select [O]
  - Install AUR package: the same flow through paru [O]
  - Remove package [O]
  - Web apps: create and remove, with fixed icons [O] + [New]
- **Appearance**
  - Theme and background: opens the picker [O]
  - Font: must not rewrite dotfile-managed configs (D-23) [O]
  - Workspace layout: tiling or floating [O]
- **Setup**
  - Plugins: enable, disable, add, clone, remove [O]
  - Security: fingerprint, FIDO2, sshd, SSH agent [O]
  - Config shortcuts: open the Hyprland, git and input configs in the editor [O]
  - Keyboard: keybinding viewer, keyboard layouts and inputs [O]
- **Update**
  - Restart components: shell, Hyprland reload, audio, Wi-Fi, Bluetooth, trackpad [O]
  - Passwords: drive encryption (LUKS) and user [O]
  - Time and timezone [O]
  - Firmware (fwupd) [O]
- **About:** fastfetch [O]
- **System:** lock, suspend, hibernate (only if available), logout, reboot, shutdown [O]

Proposed additions (need user approval):
- **Add network share** (optional, D-24), if the Thunar "keep" flow is not enough [New].
- Update › **karchy** runs `karchy update` [New].

Dropped: Agent, Learn, the Install and Remove app catalogs, toggles, the Capture submenu, Share (LocalSend), bar and window style options, channels, kernel picker, branding, Direct Boot, Reset Computer.
