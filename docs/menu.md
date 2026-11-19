# Menu

The Omarchy menu engine with a karchy tree (D-18). Super+Space opens it, and typing searches apps. Tags: [O] Omarchy entry kept, [New] karchy addition.

Layout revised 2026-11-15 from a menu audit (D-73): every row says what it does, so a search result reads on its own ("Restart Wi-Fi", not "Wi-Fi"); one card width at every level; the header shows where you are ("Update › Restart"), or "Search…" at the top; the current choice (font, layout) has a check mark on the right and the cursor starts on it.

- **Apps:** search installed desktop apps [O]. App results carry no "Apps" subtitle.
- **Packages**
  - Quick Install: the Quick install window, common apps and karchy's optional features by category, searched like fzf (D-70) [New]
  - Install Package: fzf over repo packages, `pacman -Sii` preview, multi-select [O]
  - Install AUR Package: the same flow through paru [O]
  - Remove Package [O]
  - Install Web App, Remove Web App (once one exists): icons from the site, then Dashboard Icons (D-82) [O] + [New]
- **Record Screen:** Stop Recording while one runs; No Audio, Desktop Audio, Desktop + Microphone, Desktop + Microphone + Webcam (only when a webcam is present). Then pick a region, window or monitor [O] + [New]
- **Appearance**
  - Theme: opens the picker [O]
  - Background [O]
  - Font: must not rewrite dotfile-managed configs (D-23) [O]
  - Workspace Layout: Tiling or Floating [O]
- **Settings:** opens the karchy Settings window (D-27). Its pages are search-only rows (user 2026-11-15): searching wifi or network offers Network Settings, keyboard or mouse Input Settings, displays or scale Display Settings, text size Appearance Settings, ssh SSH Settings, default browser Default Apps; each opens Settings at that page. In search, a row whose name matches comes before a submenu matched only by an alias ("install package" puts Install Package first) [New]
- **Setup**
  - Security: Set Up Fingerprint (with a reader), Set Up FIDO2 Key; Remove Fingerprint and Remove FIDO2 Key once each is set up [O]. SSH is in Settings › SSH (D-78)
  - Network Shares: Keep a Share Mounted (pick a share open in the file manager, or type `smb://server/share`) and Remove a Kept Share (once one is kept); D-24, D-76 [New]
  - Set Up Git: name, email and GitHub sign-in [O]
  - Keybindings: the keybinding viewer (Super+K) [O]
  - Config Files: Edit Hyprland Config, Edit Keybindings, Edit Input Config, opened in the editor; Settings has the same choices as controls [O]
- **Update**
  - Update System: the Updates window (`karchy updates`; D-81) [New]
  - Update Firmware (fwupd) [O]
  - Restart: Restart Shell, Reload Hyprland, Restart Audio, Restart Wi-Fi, Restart Bluetooth (with an adapter), Restart Trackpad (with a touchpad) [O]
  - Passwords: Change User Password, Change Drive Password (LUKS) [O]
  - Set Timezone, Sync Clock [O]
- **System Info:** fastfetch [O]
- **Power:** Lock, Suspend, Hibernate (only if available), Log Out, Reboot, Shutdown; Super+Escape and the power key open it [O]

Dropped: Agent, Learn, the Install and Remove app catalogs, toggles, the rest of the Capture submenu (text, QR, color; screenshots stay on Print), Share (LocalSend), bar and window style options, channels, kernel picker, branding, Direct Boot, Reset Computer.
