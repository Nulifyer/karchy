# Curated app picks from other distros

Collected 2026-11-14 for the karchy quick-install catalog. Omarchy, CachyOS and Linutil are covered elsewhere and are not included here. Package repos were checked on this host with `pacman -Si` (cachyos*, core, extra, multilib). Names not found there were checked with the AUR RPC v5 `info` call. Nothing was installed.

## Sources read

| Source key | What was read | Notes |
|---|---|---|
| Mint | `github.com/linuxmint/mintinstall`: `usr/share/linuxmint/mintinstall/featured/featured.json` (Featured banner) and `.../categories/picks.list` (Editor's Picks). `github.com/linuxmint/mintwelcome`: `usr/lib/linuxmint/mintwelcome/mintwelcome.py` (First Steps buttons) | First Steps adds Timeshift and Gufw. The other First Steps buttons open Mint's own tools (Update Manager, Driver Manager, Software Manager, settings) and are left out. |
| Pop | `github.com/pop-os/cosmic-store`: `src/editors_choice.rs` (current COSMIC Store Editor's Choice). `github.com/pop-os/shop`: `src/Views/Homepage.vala` `pop_picks` (older Pop Shop, last commit Mar 2024) | Both lists are merged into one source. |
| Bazzite | `github.com/ublue-os/bazzite`: `system_files/desktop/shared/usr/share/ublue-os/bazaar/content.yaml` (Bazaar sections: Gaming, Streaming & Chat, Music & Media, Office & Productivity, Utilities) and the `ujust` recipes in `.../ublue-os/just/82-bazzite-apps.just`, `82-bazzite-sunshine.just`, `82-bazzite-waydroid.just`, `84-bazzite-virt.just`, `87-bazzite-framegen.just`, `91-bazzite-decky.just`, `94-bazzite-protonplus.just` | The Bazaar list is the main source. The ujust recipes add CoolerControl, JetBrains Toolbox, asusctl, SteamCMD, OpenRazer, EmuDeck, OpenRGB, Boxtron, Resilio Sync, OpenTabletDriver, Sunshine, Waydroid, Decky Loader, lsfg-vk and virt-manager. DisplayLink (a driver) is left out. |
| EOS | `github.com/endeavouros-team/welcome`: `welcome` `AddMoreApps()`, which launches `eos-quickstart`. `github.com/endeavouros-team/eos-quickstart`: `eos-quickstart.conf` (the app picker list) | The Add More Apps tab itself contains only eos-quickstart and links to the Arch wiki app list, Arch packages and the AUR. `EndeavourOS-packages-lists/recom-apps` was read but not used, because it lists base CLI tools. The `flatpak` entry is left out. |
| Garuda | `gitlab.com/garuda-linux/applications/garuda-setup-assistant`: `qt/main.cpp` and `qt/setupassistant.cpp`. Package selection moved to Rani in commit `1f6bf9d` (2026-03-28). Rani is `gitlab.com/garuda-linux/applications/toolbox` (the binary was renamed `garuda-toolbox`): `packages/renderer/src/app/components/setup-wizard/setup-wizard.data.ts` | Left out as not desktop apps: the kernels and input-method categories, and the Development entries Cockpit, Ansible, Docker, Podman, Jenkins, Puppet, Prometheus and Terraform. |
| Manjaro | `github.com/manjaro-contrib/applications-application-utility` (a GitHub mirror; last commit 2025-01-27): `share/default.json` and `share/preferences.json`. Manjaro Hello (`github.com/manjaro-contrib/applications-manjaro-hello`) embeds this utility. | `gitlab.manjaro.org` returned HTTP 502, so the canonical repo could not be read. `preferences.json` fetches `default.json` from the GitLab `master` branch at runtime, so the live list may differ from the mirror. The language-support and printing meta packages are left out. |
| Ubuntu | `github.com/ubuntu/app-center`: `packages/app_center/lib/explore/explore_page.dart` and `.../snapd/snap_category_enum.dart` (hard-coded `featuredSnapNames` for the Development, Games, Productivity and Ubuntu Desktop sections). The live Snap Store `featured` category from `api.snapcraft.io/v2/snaps/find?category=featured` (15 snaps on 2026-11-14) | From the live featured list, these are kept: Steam, Signal, Blender, Slack, Todoist, Mindustry and Defold. These are left out as snap-only, CLI or niche: soundcraft, crystal, iamb, gridcraft, verdigris-protocol, paraphrase, ruff and bing-wall. WeKan (a server app) is left out of Productivity. The emulator, GNOME Games and KDE Games sub-page lists are not on the Explore page and are left out. |
| Fedora | GNOME Software upstream: `gitlab.gnome.org/GNOME/gnome-software` `data/assets/org.gnome.Software.Featured.xml` and `org.gnome.Software.Curated.xml`. Fedora Workstation third-party repos: `src.fedoraproject.org/rpms/fedora-workstation-repositories` (tree before the `dead.package` commit) | The third-party repos are Google Chrome and RPM Fusion Steam. The NVIDIA driver repo is left out, and the PyCharm COPR was removed in Aug 2026. The package is now marked "superseded by fedora-third-party-repositories", but that repo was not found on src.fedoraproject.org. Whether Fedora ships its own featured list instead of the upstream GNOME one was not checked. |
| Flathub | `https://flathub.org/api/v2/collection/popular?page=1&per_page=60`, top 40 by `installs_last_month` (2026-11-14) | |

### Package-name caveats

- AUR name collisions, so these are marked Flatpak only: `sober-bin` is an unrelated code-review tool, not Roblox Sober. `ignition` is a first-boot installer, not the flattool autostart manager. `mimic` is Mycroft's text-to-speech engine, not the default-apps manager.
- `intellij-idea-community-edition` no longer exists, and IntelliJ is listed as `intellij-idea-oss` (extra). The repo package `pycharm-community-edition` now describes the unified PyCharm.
- EndeavourOS and Manjaro ship Code - OSS (`code`), while Mint, Pop, Ubuntu and Flathub ship Microsoft's VS Code. They are merged into one row with both packages.
- Sylpheed is not packaged under that name. Only the `sylpheed-lite` and `sylpheed-beta-iconmod` variants exist in the AUR, so it is marked missing.
- The AI category is empty. None of these sources features an AI desktop app; the one AI snap, Paraphrase, was left out above.
- Where several packages are listed, all of them resolved. The first one is the closest match to what the source features.

## Merged list

The list has 438 apps. By number of sources: 7 sources: 1 app, 6: 6, 5: 9, 4: 13, 3: 20, 2: 72, 1: 317. By package: 326 are in the official or CachyOS repos, 103 are AUR only, 8 are Flatpak only and 1 is missing.

| App | Category | Sources | # | Arch package (repo) |
|---|---|---|---|---|
| Visual Studio Code / Code - OSS | Editors | Mint, Pop, EOS, Garuda, Manjaro, Ubuntu, Flathub | 7 | `visual-studio-code-bin` (AUR); `code` (cachyos-extra-v3, extra) |
| Chromium | Browsers | Pop, EOS, Garuda, Manjaro, Ubuntu, Flathub | 6 | `chromium` (extra) |
| Telegram Desktop | Chat | Mint, Pop, EOS, Garuda, Manjaro, Flathub | 6 | `telegram-desktop` (extra) |
| GIMP | Media & creative | Mint, Bazzite, EOS, Garuda, Manjaro, Flathub | 6 | `gimp` (cachyos-extra-v3, extra) |
| VLC | Media & creative | Mint, Bazzite, EOS, Garuda, Manjaro, Flathub | 6 | `vlc` (cachyos-extra-v3, extra) |
| LibreOffice | Office & notes | Bazzite, EOS, Garuda, Manjaro, Ubuntu, Flathub | 6 | `libreoffice-fresh` (cachyos-extra-v3, extra); `libreoffice-still` (cachyos-extra-v3, extra) |
| qBittorrent | Sync & remote | Mint, Bazzite, EOS, Garuda, Manjaro, Flathub | 6 | `qbittorrent` (extra) |
| Firefox | Browsers | EOS, Garuda, Manjaro, Ubuntu, Flathub | 5 | `firefox` (cachyos-extra-v3, extra) |
| Discord | Chat | Mint, Bazzite, Garuda, Ubuntu, Flathub | 5 | `discord` (extra) |
| Slack | Chat | Mint, Pop, Bazzite, Garuda, Ubuntu | 5 | `slack-desktop` (AUR) |
| Steam | Gaming | Mint, Pop, Ubuntu, Fedora, Flathub | 5 | `steam` (multilib) |
| Blender | Media & creative | Mint, Bazzite, Garuda, Manjaro, Ubuntu | 5 | `blender` (extra) |
| Inkscape | Media & creative | Mint, Bazzite, EOS, Garuda, Manjaro | 5 | `inkscape` (cachyos-extra-v3, extra) |
| OBS Studio | Media & creative | Mint, Bazzite, Garuda, Manjaro, Flathub | 5 | `obs-studio` (cachyos-extra-v3, extra) |
| Thunderbird | Office & notes | Bazzite, EOS, Garuda, Manjaro, Ubuntu | 5 | `thunderbird` (cachyos-extra-v3, extra) |
| Bitwarden | Passwords & security | Mint, Bazzite, EOS, Manjaro, Flathub | 5 | `bitwarden` (cachyos-extra-v3, extra) |
| Signal | Chat | Mint, Pop, Garuda, Ubuntu | 4 | `signal-desktop` (extra) |
| GNOME Builder | Development | EOS, Garuda, Manjaro, Fedora | 4 | `gnome-builder` (cachyos-extra-v3, extra) |
| Audacious | Media & creative | Bazzite, EOS, Garuda, Manjaro | 4 | `audacious` (cachyos-extra-v3, extra) |
| Audacity | Media & creative | Mint, Bazzite, Garuda, Manjaro | 4 | `audacity` (extra) |
| Krita | Media & creative | Bazzite, EOS, Garuda, Manjaro | 4 | `krita` (cachyos-extra-v3, extra) |
| Spotify | Media & creative | Mint, Pop, Bazzite, Flathub | 4 | `spotify` (AUR); `spotify-launcher` (cachyos-extra-v3, extra) |
| Strawberry | Media & creative | Bazzite, EOS, Garuda, Manjaro | 4 | `strawberry` (cachyos-extra-v3, extra) |
| Evolution | Office & notes | EOS, Garuda, Manjaro, Fedora | 4 | `evolution` (cachyos-extra-v3, extra) |
| Geary | Office & notes | EOS, Garuda, Manjaro, Fedora | 4 | `geary` (cachyos-extra-v3, extra) |
| ONLYOFFICE | Office & notes | Bazzite, Garuda, Manjaro, Flathub | 4 | `onlyoffice-bin` (cachyos) |
| KeePassXC | Passwords & security | Bazzite, EOS, Garuda, Manjaro | 4 | `keepassxc` (cachyos-extra-v3, extra) |
| GNOME Boxes | System | EOS, Garuda, Manjaro, Fedora | 4 | `gnome-boxes` (cachyos-extra-v3, extra) |
| Virtual Machine Manager | System | Pop, Bazzite, Garuda, Manjaro | 4 | `virt-manager` (extra) |
| Falkon | Browsers | EOS, Garuda, Manjaro | 3 | `falkon` (cachyos-extra-v3, extra) |
| Vivaldi | Browsers | EOS, Garuda, Manjaro | 3 | `vivaldi` (cachyos-extra-v3, extra) |
| Element | Chat | Bazzite, Garuda, Manjaro | 3 | `element-desktop` (extra) |
| Fractal (Matrix) | Chat | Bazzite, Garuda, Manjaro | 3 | `fractal` (cachyos-extra-v3, extra) |
| Pidgin | Chat | Bazzite, EOS, Manjaro | 3 | `pidgin` (AUR) |
| Postman | Development | Pop, Garuda, Ubuntu | 3 | `postman-bin` (AUR) |
| darktable | Media & creative | EOS, Garuda, Flathub | 3 | `darktable` (cachyos-extra-v3, extra) |
| GNOME Photos | Media & creative | EOS, Manjaro, Fedora | 3 | `gnome-photos` (cachyos-extra-v3, extra) |
| Lollypop | Media & creative | EOS, Garuda, Manjaro | 3 | `lollypop` (extra) |
| Shotwell | Media & creative | EOS, Manjaro, Ubuntu | 3 | `shotwell` (cachyos-extra-v3, extra) |
| SMPlayer | Media & creative | EOS, Garuda, Manjaro | 3 | `smplayer` (cachyos-extra-v3, extra) |
| Totem (GNOME Videos) | Media & creative | EOS, Manjaro, Fedora | 3 | `totem` (cachyos-extra-v3, extra) |
| Evince | Office & notes | EOS, Manjaro, Fedora | 3 | `evince` (cachyos-extra-v3, extra) |
| KMail | Office & notes | EOS, Garuda, Manjaro | 3 | `kmail` (cachyos-extra-v3, extra) |
| Obsidian | Office & notes | Bazzite, Garuda, Flathub | 3 | `obsidian` (extra) |
| Deluge | Sync & remote | EOS, Garuda, Manjaro | 3 | `deluge-gtk` (cachyos-extra-v3, extra); `deluge` (cachyos-extra-v3, extra) |
| FileZilla | Sync & remote | Mint, Garuda, Manjaro | 3 | `filezilla` (cachyos-extra-v3, extra) |
| Transmission | Sync & remote | EOS, Manjaro, Ubuntu | 3 | `transmission-gtk` (extra); `transmission-qt` (extra) |
| Deja Dup | System | Pop, Manjaro, Fedora | 3 | `deja-dup` (extra) |
| VirtualBox | System | Mint, Garuda, Manjaro | 3 | `virtualbox` (extra) |
| Brave | Browsers | Garuda, Flathub | 2 | `brave-bin` (cachyos) |
| Google Chrome | Browsers | Fedora, Flathub | 2 | `google-chrome` (AUR) |
| Konqueror | Browsers | EOS, Manjaro | 2 | `konqueror` (cachyos-extra-v3, extra) |
| LibreWolf | Browsers | Garuda, Flathub | 2 | `librewolf` (cachyos-extra-v3, extra) |
| Tor Browser Launcher | Browsers | EOS, Garuda | 2 | `torbrowser-launcher` (extra) |
| HexChat | Chat | EOS, Manjaro | 2 | `hexchat` (AUR) |
| Mumble | Chat | Bazzite, Garuda | 2 | `mumble` (cachyos-extra-v3, extra) |
| NeoChat | Chat | EOS, Garuda | 2 | `neochat` (cachyos-extra-v3, extra) |
| Polari | Chat | EOS, Fedora | 2 | `polari` (cachyos-extra-v3, extra) |
| Teams for Linux | Chat | Bazzite, Garuda | 2 | `teams-for-linux` (cachyos); `teams-for-linux-bin` (AUR) |
| Zoom | Chat | Mint, Garuda | 2 | `zoom` (AUR) |
| IntelliJ IDEA (OSS build) | Development | EOS, Garuda | 2 | `intellij-idea-oss` (cachyos-extra-v3, extra) |
| KDevelop | Development | EOS, Garuda | 2 | `kdevelop` (cachyos-extra-v3, extra) |
| NetBeans | Development | EOS, Garuda | 2 | `netbeans` (extra) |
| PyCharm | Development | EOS, Garuda | 2 | `pycharm-community-edition` (cachyos-extra-v3, extra); `pycharm` (AUR) |
| Qt Creator | Development | EOS, Garuda | 2 | `qtcreator` (cachyos-extra-v3, extra) |
| FeatherPad | Editors | EOS, Manjaro | 2 | `featherpad` (cachyos-extra-v3, extra) |
| gedit | Editors | EOS, Manjaro | 2 | `gedit` (cachyos-extra-v3, extra) |
| Vim / GVim | Editors | Garuda, Manjaro | 2 | `gvim` (cachyos-extra-v3, extra); `vim` (cachyos-extra-v3, extra) |
| Xed | Editors | EOS, Manjaro | 2 | `xed` (cachyos-extra-v3, extra) |
| 0 A.D. | Gaming | Garuda, Ubuntu | 2 | `0ad` (cachyos-extra-v3, extra) |
| AisleRiot | Gaming | Garuda, Fedora | 2 | `aisleriot` (cachyos-extra-v3, extra) |
| Dolphin Emulator | Gaming | Bazzite, Flathub | 2 | `dolphin-emu` (cachyos-extra-v3, extra) |
| Heroic Games Launcher | Gaming | Bazzite, Flathub | 2 | `heroic-games-launcher-bin` (cachyos); `heroic-games-launcher` (cachyos) |
| Lutris | Gaming | Pop, Flathub | 2 | `lutris` (extra) |
| PPSSPP | Gaming | Bazzite, Flathub | 2 | `ppsspp` (cachyos-extra-v3, extra) |
| Prism Launcher | Gaming | Bazzite, Flathub | 2 | `prismlauncher` (cachyos-extra-v3, extra) |
| ProtonPlus | Gaming | Bazzite, Flathub | 2 | `protonplus` (cachyos) |
| RetroArch | Gaming | Bazzite, Flathub | 2 | `retroarch` (extra) |
| Sober (Roblox) | Gaming | Bazzite, Flathub | 2 | Flatpak only |
| Space Cadet Pinball | Gaming | Bazzite, Flathub | 2 | `spacecadetpinball-git` (AUR) |
| SuperTux | Gaming | Bazzite, Garuda | 2 | `supertux` (extra) |
| SuperTuxKart | Gaming | Bazzite, Garuda | 2 | `supertuxkart` (cachyos-extra-v3, extra) |
| Amberol | Media & creative | Bazzite, Fedora | 2 | `amberol` (cachyos-extra-v3, extra) |
| Ardour | Media & creative | Bazzite, Garuda | 2 | `ardour` (cachyos-extra-v3, extra) |
| Baka MPlayer | Media & creative | EOS, Garuda | 2 | `baka-mplayer` (cachyos-extra-v3, extra) |
| digiKam | Media & creative | EOS, Garuda | 2 | `digikam` (cachyos-extra-v3, extra) |
| Elisa | Media & creative | EOS, Garuda | 2 | `elisa` (cachyos-extra-v3, extra) |
| Eye of GNOME | Media & creative | EOS, Manjaro | 2 | `eog` (cachyos-extra-v3, extra) |
| Flowblade | Media & creative | Bazzite, Manjaro | 2 | `flowblade` (extra) |
| gThumb | Media & creative | EOS, Manjaro | 2 | `gthumb` (cachyos-extra-v3, extra) |
| Kdenlive | Media & creative | Garuda, Manjaro | 2 | `kdenlive` (cachyos-extra-v3, extra) |
| KiCad | Media & creative | Garuda, Flathub | 2 | `kicad` (cachyos-extra-v3, extra) |
| Kodi | Media & creative | Garuda, Manjaro | 2 | `kodi` (extra) |
| KolourPaint | Media & creative | EOS, Garuda | 2 | `kolourpaint` (cachyos-extra-v3, extra) |
| Pinta | Media & creative | EOS, Manjaro | 2 | `pinta` (extra) |
| Rhythmbox | Media & creative | EOS, Manjaro | 2 | `rhythmbox` (cachyos-extra-v3, extra) |
| Ristretto | Media & creative | EOS, Manjaro | 2 | `ristretto` (cachyos-extra-v3, extra) |
| Shortwave (radio) | Media & creative | Garuda, Fedora | 2 | `shortwave` (cachyos-extra-v3, extra) |
| Shotcut | Media & creative | Garuda, Manjaro | 2 | `shotcut` (cachyos-extra-v3, extra) |
| calibre | Office & notes | Mint, Manjaro | 2 | `calibre` (cachyos-extra-v3, extra) |
| Calligra | Office & notes | EOS, Garuda | 2 | `calligra` (cachyos-extra-v3, extra) |
| Claws Mail | Office & notes | Garuda, Manjaro | 2 | `claws-mail` (cachyos-extra-v3, extra) |
| FreeOffice | Office & notes | Garuda, Manjaro | 2 | `freeoffice` (AUR, flagged out-of-date) |
| GNOME Calendar | Office & notes | Ubuntu, Fedora | 2 | `gnome-calendar` (cachyos-extra-v3, extra) |
| GnuCash | Office & notes | EOS, Garuda | 2 | `gnucash` (cachyos-extra-v3, extra) |
| Gnumeric | Office & notes | EOS, Garuda | 2 | `gnumeric` (extra) |
| HomeBank | Office & notes | EOS, Garuda | 2 | `homebank` (extra) |
| KMyMoney | Office & notes | EOS, Garuda | 2 | `kmymoney` (cachyos-extra-v3, extra) |
| Okular | Office & notes | EOS, Manjaro | 2 | `okular` (cachyos-extra-v3, extra) |
| Skrooge | Office & notes | EOS, Garuda | 2 | `skrooge` (cachyos-extra-v3, extra) |
| Todoist | Office & notes | Mint, Ubuntu | 2 | `todoist-appimage` (AUR) |
| Xreader | Office & notes | EOS, Manjaro | 2 | `xreader` (cachyos-extra-v3, extra) |
| Gufw | Passwords & security | Mint, EOS | 2 | `gufw` (extra) |
| Remmina | Sync & remote | Garuda, Ubuntu | 2 | `remmina` (cachyos-extra-v3, extra) |
| Syncthing GUI (syncthing-gtk / SyncThingy) | Sync & remote | Bazzite, Manjaro | 2 | `syncthing-gtk` (AUR); `syncthing` (cachyos-extra-v3, extra) |
| Warp | Sync & remote | Bazzite, Fedora | 2 | `warp` (cachyos-extra-v3, extra) |
| Bazaar (Flatpak store) | System | Garuda, Flathub | 2 | `bazaar` (cachyos-extra-v3, extra); `bazaar-git` (AUR) |
| GParted | System | EOS, Manjaro | 2 | `gparted` (cachyos-extra-v3, extra) |
| Timeshift | System | Mint, Manjaro | 2 | `timeshift` (cachyos-extra-v3, extra) |
| Boatswain (Stream Deck) | Utilities | Bazzite, Fedora | 2 | `boatswain` (AUR) |
| Gear Lever | Utilities | Bazzite, Flathub | 2 | `gearlever` (AUR, flagged out-of-date) |
| FireDragon | Browsers | Garuda | 1 | `firedragon` (AUR); `firedragon-bin` (AUR) |
| Firefox ESR | Browsers | Garuda | 1 | `firefox-esr` (AUR); `firefox-esr-bin` (cachyos) |
| GNOME Web (Epiphany) | Browsers | Manjaro | 1 | `epiphany` (cachyos-extra-v3, extra) |
| qutebrowser | Browsers | Garuda | 1 | `qutebrowser` (extra) |
| Ungoogled Chromium | Browsers | Garuda | 1 | `ungoogled-chromium-bin` (cachyos); `ungoogled-chromium` (AUR, flagged out-of-date) |
| Zen Browser | Browsers | Flathub | 1 | `zen-browser-bin` (cachyos); `zen-browser` (AUR) |
| Halloy (IRC) | Chat | Bazzite | 1 | `halloy` (cachyos-extra-v3, extra) |
| Jitsi Meet | Chat | Garuda | 1 | `jitsi-meet-desktop` (AUR); `jitsi-meet-desktop-bin` (AUR) |
| Konversation | Chat | EOS | 1 | `konversation` (cachyos-extra-v3, extra) |
| Mattermost | Chat | Pop | 1 | `mattermost-desktop` (extra) |
| Streamlink Twitch GUI | Chat | Garuda | 1 | `streamlink-twitch-gui-bin` (AUR) |
| TeamSpeak | Chat | Bazzite | 1 | `teamspeak` (AUR, flagged out-of-date); `teamspeak3` (extra) |
| Vesktop | Chat | Bazzite | 1 | `vesktop` (AUR); `vesktop-bin` (cachyos) |
| Whatsie (WhatsApp client) | Chat | Mint | 1 | `whatsie` (AUR, orphaned) |
| Wire | Chat | Garuda | 1 | `wire-desktop` (AUR) |
| Arduino IDE 2 | Development | Bazzite | 1 | `arduino-ide-bin` (AUR); `arduino-ide` (AUR) |
| Commit (message editor) | Development | Fedora | 1 | `commit` (extra) |
| DBeaver | Development | Pop | 1 | `dbeaver` (cachyos-extra-v3, extra) |
| Defold | Development | Ubuntu | 1 | `defold-bin` (AUR) |
| Elastic | Development | Fedora | 1 | `elastic` (cachyos-extra-v3, extra) |
| Emblem | Development | Fedora | 1 | `emblem` (cachyos-extra-v3, extra) |
| Forge Sparks | Development | Fedora | 1 | `forge-sparks` (extra) |
| Gaphor | Development | Fedora | 1 | `gaphor` (extra) |
| Geany | Development | EOS | 1 | `geany` (cachyos-extra-v3, extra) |
| GHex | Development | Bazzite | 1 | `ghex` (cachyos-extra-v3, extra) |
| GitHub Desktop | Development | Garuda | 1 | `github-desktop-bin` (AUR); `github-desktop` (cachyos) |
| GitKraken | Development | Garuda | 1 | `gitkraken` (AUR) |
| JetBrains Toolbox | Development | Bazzite | 1 | `jetbrains-toolbox` (AUR) |
| Lorem | Development | Fedora | 1 | `lorem` (cachyos-extra-v3, extra) |
| Meld | Development | Pop | 1 | `meld` (extra) |
| PhpStorm | Development | Ubuntu | 1 | `phpstorm` (AUR) |
| Share Preview | Development | Fedora | 1 | `share-preview` (cachyos-extra-v3, extra) |
| Text Pieces | Development | Fedora | 1 | `textpieces` (cachyos-extra-v3, extra) |
| Webfont Kit Generator | Development | Fedora | 1 | `webfont-kit-generator` (extra) |
| Workbench | Development | Fedora | 1 | `workbench` (AUR) |
| Apostrophe (Markdown) | Editors | Fedora | 1 | `apostrophe` (extra) |
| GNU Emacs | Editors | Garuda | 1 | `emacs` (extra) |
| Kate | Editors | EOS | 1 | `kate` (cachyos-extra-v3, extra) |
| L3afpad | Editors | EOS | 1 | `l3afpad` (cachyos-extra-v3, extra) |
| micro | Editors | Manjaro | 1 | `micro` (cachyos-extra-v3, extra) |
| Mousepad | Editors | EOS | 1 | `mousepad` (cachyos-extra-v3, extra) |
| Pluma | Editors | EOS | 1 | `pluma` (cachyos-extra-v3, extra) |
| Sublime Text | Editors | Mint | 1 | `sublime-text-4` (AUR) |
| VSCodium | Editors | Garuda | 1 | `vscodium-bin` (AUR); `vscodium` (cachyos) |
| Zed | Editors | Garuda | 1 | `zed` (extra) |
| Bottles | Gaming | Flathub | 1 | `bottles` (AUR) |
| Boxflat | Gaming | Bazzite | 1 | `boxflat-git` (AUR) |
| Boxtron | Gaming | Bazzite | 1 | `boxtron` (AUR) |
| Cartridges | Gaming | Fedora | 1 | `cartridges` (extra) |
| Cemu | Gaming | Bazzite | 1 | `cemu` (AUR) |
| Chess Clock | Gaming | Fedora | 1 | `chess-clock` (extra) |
| Decky Loader | Gaming | Bazzite | 1 | `decky-loader-bin` (AUR, flagged out-of-date); `decky-loader` (AUR) |
| Discover Overlay | Gaming | Bazzite | 1 | `discover-overlay` (AUR) |
| DOSBox Staging | Gaming | Bazzite | 1 | `dosbox-staging` (AUR) |
| doukutsu-rs | Gaming | Bazzite | 1 | `doukutsu-rs-git` (AUR) |
| Dr. Robotnik's Ring Racers | Gaming | Bazzite | 1 | `ringracers` (AUR) |
| EmuDeck | Gaming | Bazzite | 1 | `emudeck-bin` (AUR) |
| Epic Games Launcher | Gaming | Bazzite | 1 | `epic-games-launcher-bin` (cachyos) |
| ET: Legacy | Gaming | Bazzite | 1 | `etlegacy` (AUR) |
| Faugus Launcher | Gaming | Bazzite | 1 | `faugus-launcher` (cachyos) |
| Flips (patcher) | Gaming | Bazzite | 1 | `flips` (cachyos-extra-v3, extra); `flips-git` (AUR) |
| GeForce Infinity | Gaming | Bazzite | 1 | `geforce-infinity` (AUR); `geforce-infinity-bin` (AUR) |
| GNOME Mahjongg | Gaming | Ubuntu | 1 | `gnome-mahjongg` (cachyos-extra-v3, extra) |
| GNOME Mines | Gaming | Ubuntu | 1 | `gnome-mines` (cachyos-extra-v3, extra) |
| GNOME Sudoku | Gaming | Ubuntu | 1 | `gnome-sudoku` (cachyos-extra-v3, extra) |
| Hedgewars | Gaming | Garuda | 1 | `hedgewars` (extra) |
| itch | Gaming | Bazzite | 1 | `itch-setup-bin` (AUR) |
| Kapman | Gaming | Garuda | 1 | `kapman` (cachyos-extra-v3, extra) |
| KMahjongg | Gaming | Garuda | 1 | `kmahjongg` (cachyos-extra-v3, extra) |
| Knights | Gaming | Garuda | 1 | `knights` (cachyos-extra-v3, extra) |
| Limo (mod manager) | Gaming | Bazzite | 1 | `limo` (AUR) |
| lsfg-vk (Lossless Scaling frame gen) | Gaming | Bazzite | 1 | `lsfg-vk` (cachyos); `lsfg-vk-bin` (AUR) |
| Luanti | Gaming | Garuda | 1 | `luanti` (cachyos-extra-v3, extra) |
| MAME | Gaming | Bazzite | 1 | `mame` (cachyos-extra-v3, extra) |
| MangoJuice | Gaming | Bazzite | 1 | `mangojuice` (cachyos) |
| Mari0 | Gaming | Garuda | 1 | `mari0` (extra) |
| melonDS | Gaming | Bazzite | 1 | `melonds` (AUR) |
| mGBA | Gaming | Bazzite | 1 | `mgba-qt` (extra) |
| Mindustry | Gaming | Ubuntu | 1 | `mindustry` (AUR) |
| Minecraft Bedrock Launcher | Gaming | Bazzite | 1 | `mcpelauncher-ui-git` (AUR); `mcpelauncher-linux` (AUR) |
| Minecraft Launcher | Gaming | Ubuntu | 1 | `minecraft-launcher` (AUR) |
| Moonlight | Gaming | Bazzite | 1 | `moonlight-qt` (cachyos-extra-v3, extra) |
| Not Tetris 2 | Gaming | Bazzite | 1 | `nottetris2` (AUR) |
| OpenMW | Gaming | Bazzite | 1 | `openmw` (cachyos-extra-v3, extra) |
| osu!(lazer) | Gaming | Bazzite | 1 | `osu-lazer-bin` (AUR); `osu-lazer` (AUR) |
| Oversteer | Gaming | Bazzite | 1 | `oversteer` (AUR) |
| PCSX2 | Gaming | Bazzite | 1 | `pcsx2` (AUR) |
| PokeMMO | Gaming | Bazzite | 1 | `pokemmo` (AUR) |
| PrimeHack | Gaming | Bazzite | 1 | `dolphin-emu-primehack-git` (AUR) |
| ProtonUp-Qt | Gaming | Flathub | 1 | `protonup-qt` (cachyos) |
| Raze | Gaming | Bazzite | 1 | `raze` (AUR, flagged out-of-date, orphaned) |
| RetroDECK | Gaming | Bazzite | 1 | Flatpak only |
| ROTA | Gaming | Bazzite | 1 | Flatpak only |
| RPCS3 | Gaming | Bazzite | 1 | `rpcs3-bin` (AUR) |
| Ruffle | Gaming | Bazzite | 1 | `ruffle` (AUR); `ruffle-nightly-bin` (AUR) |
| ScopeBuddy | Gaming | Bazzite | 1 | `scopebuddy` (AUR); `scopebuddy-git` (AUR) |
| ScummVM | Gaming | Bazzite | 1 | `scummvm` (cachyos-extra-v3, extra) |
| Snes9x | Gaming | Bazzite | 1 | `snes9x-gtk` (cachyos-extra-v3, extra); `snes9x` (cachyos-extra-v3, extra) |
| Sonic Robo Blast 2 | Gaming | Bazzite | 1 | `srb2` (AUR) |
| SRB2Kart | Gaming | Bazzite | 1 | `srb2kart` (AUR) |
| Steam Link | Gaming | Bazzite | 1 | `steamlink` (AUR, flagged out-of-date) |
| SteamCMD | Gaming | Bazzite | 1 | `steamcmd` (AUR) |
| Stella | Gaming | Bazzite | 1 | `stella` (cachyos-extra-v3, extra) |
| Sunshine (game stream host) | Gaming | Bazzite | 1 | `sunshine` (cachyos) |
| Supermodel | Gaming | Bazzite | 1 | `supermodel` (AUR) |
| Teeworlds | Gaming | Garuda | 1 | `teeworlds` (cachyos-extra-v3, extra) |
| Threadbare | Gaming | Bazzite | 1 | Flatpak only |
| UZDoom | Gaming | Bazzite | 1 | `uzdoom` (AUR, flagged out-of-date); `gzdoom` (AUR) |
| Vintage Story | Gaming | Bazzite | 1 | `vintagestory` (AUR) |
| Viper (Titanfall mod manager) | Gaming | Bazzite | 1 | `viper-bin` (AUR) |
| WineZGUI | Gaming | Bazzite | 1 | Flatpak only |
| Wolfenstein: Blade of Agony | Gaming | Bazzite | 1 | Flatpak only |
| xemu | Gaming | Bazzite | 1 | `xemu` (AUR) |
| XIVLauncher | Gaming | Bazzite | 1 | `xivlauncher` (AUR); `xivlauncher-rb` (AUR) |
| Xonotic | Gaming | Garuda | 1 | `xonotic` (cachyos-extra-v3, extra) |
| Audio Sharing | Media & creative | Fedora | 1 | `audio-sharing` (cachyos-extra-v3, extra) |
| BirdFont | Media & creative | Garuda | 1 | `birdfont` (cachyos-extra-v3, extra) |
| Bitwig Studio | Media & creative | Garuda | 1 | `bitwig-studio` (AUR) |
| Blanket | Media & creative | Fedora | 1 | `blanket` (extra) |
| Brasero | Media & creative | Garuda | 1 | `brasero` (cachyos-extra-v3, extra) |
| Celluloid | Media & creative | EOS | 1 | `celluloid` (cachyos-extra-v3, extra) |
| Cheese (webcam) | Media & creative | Ubuntu | 1 | `cheese` (AUR) |
| Converseen | Media & creative | Garuda | 1 | `converseen` (cachyos-extra-v3, extra) |
| Curtail | Media & creative | Fedora | 1 | `curtail` (extra) |
| Decibels | Media & creative | Fedora | 1 | `decibels` (extra) |
| Dragon Player | Media & creative | Garuda | 1 | `dragon` (cachyos-extra-v3, extra) |
| Ear Tag | Media & creative | Fedora | 1 | `eartag` (extra) |
| EasyEffects | Media & creative | Bazzite | 1 | `easyeffects` (cachyos-extra-v3, extra) |
| EasyTAG | Media & creative | Garuda | 1 | `easytag` (cachyos-extra-v3, extra) |
| Exhibit (3D viewer) | Media & creative | Bazzite | 1 | `exhibit` (AUR) |
| FontForge | Media & creative | Garuda | 1 | `fontforge` (cachyos-extra-v3, extra) |
| FreeCAD | Media & creative | Garuda | 1 | `freecad` (extra) |
| FreeTube | Media & creative | Mint | 1 | `freetube-bin` (AUR); `freetube` (cachyos) |
| Fretboard | Media & creative | Fedora | 1 | `fretboard` (cachyos-extra-v3, extra) |
| Gapless (G4Music) | Media & creative | Bazzite | 1 | `gapless` (AUR) |
| Geeqie | Media & creative | EOS | 1 | `geeqie` (cachyos-extra-v3, extra) |
| GNOME Podcasts | Media & creative | Fedora | 1 | `gnome-podcasts` (cachyos-extra-v3, extra) |
| GPicView | Media & creative | Manjaro | 1 | `gpicview` (cachyos-extra-v3, extra) |
| Gwenview | Media & creative | EOS | 1 | `gwenview` (cachyos-extra-v3, extra) |
| HandBrake | Media & creative | Garuda | 1 | `handbrake` (cachyos-extra-v3, extra) |
| Haruna | Media & creative | EOS | 1 | `haruna` (cachyos-extra-v3, extra) |
| Hypnotix (IPTV) | Media & creative | Garuda | 1 | `hypnotix` (extra) |
| Identity | Media & creative | Fedora | 1 | `identity` (cachyos-extra-v3, extra) |
| JamesDSP | Media & creative | Bazzite | 1 | `jamesdsp` (AUR) |
| Jellyfin Desktop | Media & creative | Bazzite | 1 | `jellyfin-desktop` (AUR); `jellyfin-media-player` (AUR) |
| K3b | Media & creative | Garuda | 1 | `k3b` (cachyos-extra-v3, extra) |
| Kaffeine | Media & creative | EOS | 1 | `kaffeine` (cachyos-extra-v3, extra) |
| Kid3 | Media & creative | Garuda | 1 | `kid3-qt` (cachyos-extra-v3, extra); `kid3` (cachyos-extra-v3, extra) |
| Komikku | Media & creative | Fedora | 1 | `komikku` (extra) |
| Kwave | Media & creative | Garuda | 1 | `kwave` (cachyos-extra-v3, extra) |
| Letterpress | Media & creative | Fedora | 1 | `letterpress` (extra) |
| LibreCAD | Media & creative | Garuda | 1 | `librecad` (cachyos-extra-v3, extra) |
| LMMS | Media & creative | Garuda | 1 | `lmms` (extra) |
| Loupe | Media & creative | EOS | 1 | `loupe` (cachyos-extra-v3, extra) |
| Luminance HDR | Media & creative | Garuda | 1 | `luminancehdr` (cachyos-extra-v3, extra) |
| MediaElch | Media & creative | Garuda | 1 | `mediaelch` (cachyos-extra-v3, extra) |
| Mixxx | Media & creative | Garuda | 1 | `mixxx` (extra) |
| Mousai | Media & creative | Fedora | 1 | `mousai` (cachyos-extra-v3, extra) |
| mpv | Media & creative | Manjaro | 1 | `mpv` (cachyos-extra-v3, extra) |
| MuseScore | Media & creative | Garuda | 1 | `musescore` (cachyos-extra-v3, extra) |
| MyPaint | Media & creative | Garuda | 1 | `mypaint` (cachyos-extra-v3, extra) |
| MystiQ | Media & creative | Garuda | 1 | `mystiq` (AUR) |
| Nook (Animal Crossing music) | Media & creative | Bazzite | 1 | `nook-desktop-electron-bin` (AUR) |
| OpenShot | Media & creative | Manjaro | 1 | `openshot` (AUR) |
| OpenToonz | Media & creative | Garuda | 1 | `opentoonz` (cachyos-extra-v3, extra) |
| Parole | Media & creative | Manjaro | 1 | `parole` (extra) |
| Peek (GIF recorder) | Media & creative | Pop | 1 | `peek` (extra) |
| Pencil2D | Media & creative | Garuda | 1 | `pencil2d` (extra) |
| Photoflare | Media & creative | EOS | 1 | `photoflare` (cachyos-extra-v3, extra) |
| Pitivi | Media & creative | Manjaro | 1 | `pitivi` (cachyos-extra-v3, extra) |
| Plex Desktop | Media & creative | Bazzite | 1 | `plex-desktop` (AUR) |
| Plexamp | Media & creative | Bazzite | 1 | `plexamp-appimage` (AUR) |
| Qmmp | Media & creative | Manjaro | 1 | `qmmp` (cachyos-extra-v3, extra) |
| Rapid Photo Downloader | Media & creative | EOS | 1 | `rapid-photo-downloader` (extra) |
| RawTherapee | Media & creative | EOS | 1 | `rawtherapee` (cachyos-extra-v3, extra) |
| Rosegarden | Media & creative | Garuda | 1 | `rosegarden` (cachyos-extra-v3, extra) |
| Showtime | Media & creative | EOS | 1 | `showtime` (extra) |
| SoundConverter | Media & creative | Garuda | 1 | `soundconverter` (extra) |
| Stremio | Media & creative | Flathub | 1 | `stremio` (AUR) |
| Subtitle Composer | Media & creative | Garuda | 1 | `subtitlecomposer` (cachyos-extra-v3, extra) |
| Sweet Home 3D | Media & creative | Garuda | 1 | `sweethome3d` (cachyos-extra-v3, extra) |
| Switcheroo (image converter) | Media & creative | Fedora | 1 | `switcheroo` (cachyos-extra-v3, extra) |
| Synfig Studio | Media & creative | Garuda | 1 | `synfigstudio` (cachyos-extra-v3, extra) |
| TIDAL Hi-Fi | Media & creative | Bazzite | 1 | `tidal-hifi-bin` (AUR); `tidal-hifi` (AUR) |
| Transmageddon | Media & creative | Garuda | 1 | `transmageddon` (extra) |
| VacuumTube (YouTube TV) | Media & creative | Bazzite | 1 | `vacuumtube` (AUR); `vacuumtube-bin` (AUR) |
| Video Trimmer | Media & creative | Fedora | 1 | `video-trimmer` (cachyos-extra-v3, extra) |
| vokoscreenNG | Media & creative | Manjaro | 1 | `vokoscreen` (cachyos-extra-v3, extra) |
| Wings 3D | Media & creative | Garuda | 1 | `wings3d` (AUR) |
| Xfburn | Media & creative | Garuda | 1 | `xfburn` (cachyos-extra-v3, extra) |
| AbiWord | Office & notes | Garuda | 1 | `abiword` (cachyos-extra-v3, extra) |
| Atril | Office & notes | EOS | 1 | `atril` (cachyos-extra-v3, extra) |
| Bookworm | Office & notes | Manjaro | 1 | `bookworm` (cachyos-extra-v3, extra) |
| Citations | Office & notes | Fedora | 1 | `citations` (cachyos-extra-v3, extra) |
| CoolReader | Office & notes | Manjaro | 1 | `coolreader` (AUR) |
| Endeavour (GNOME To Do) | Office & notes | Fedora | 1 | `endeavour` (cachyos-extra-v3, extra) |
| Errands | Office & notes | Fedora | 1 | `errands` (cachyos-extra-v3, extra) |
| FBReader | Office & notes | Manjaro | 1 | `fbreader` (cachyos-extra-v3, extra) |
| FeatherNotes | Office & notes | Manjaro | 1 | `feathernotes` (cachyos-extra-v3, extra) |
| Foliate | Office & notes | Manjaro | 1 | `foliate` (extra) |
| GeoGebra | Office & notes | EOS | 1 | `geogebra` (extra) |
| GNOME Calculator | Office & notes | EOS | 1 | `gnome-calculator` (cachyos-extra-v3, extra) |
| GNOME Contacts | Office & notes | Fedora | 1 | `gnome-contacts` (cachyos-extra-v3, extra) |
| GNOME Dictionary | Office & notes | Fedora | 1 | `gnome-dictionary` (cachyos-extra-v3, extra) |
| GNOME Notes | Office & notes | Fedora | 1 | `gnome-notes` (cachyos-extra-v3, extra) |
| GNU Octave | Office & notes | EOS | 1 | `octave` (cachyos-extra-v3, extra) |
| Graphs | Office & notes | Fedora | 1 | `graphs` (cachyos-extra-v3, extra) |
| Joplin | Office & notes | Garuda | 1 | `joplin-desktop` (cachyos); `joplin-appimage` (AUR); `joplin-beta` (AUR) |
| KAlgebra | Office & notes | EOS | 1 | `kalgebra` (cachyos-extra-v3, extra) |
| KCalc | Office & notes | EOS | 1 | `kcalc` (cachyos-extra-v3, extra) |
| Khronos (time log) | Office & notes | Fedora | 1 | `khronos` (AUR) |
| Mailspring | Office & notes | Garuda | 1 | `mailspring-bin` (AUR); `mailspring` (cachyos) |
| NewsFlash (RSS) | Office & notes | Fedora | 1 | `newsflash` (cachyos-extra-v3, extra) |
| Papers | Office & notes | EOS | 1 | `papers` (cachyos-extra-v3, extra) |
| Paperwork | Office & notes | Manjaro | 1 | `paperwork` (extra) |
| PDF Metadata Editor | Office & notes | Fedora | 1 | `pdf-metadata-editor-bin` (AUR) |
| Plots | Office & notes | Fedora | 1 | `plots` (AUR) |
| SageMath | Office & notes | EOS | 1 | `sagemath` (cachyos-extra-v3, extra) |
| Solanum (Pomodoro) | Office & notes | Fedora | 1 | `solanum` (cachyos-extra-v3, extra) |
| Standard Notes | Office & notes | Bazzite | 1 | `standardnotes-bin` (AUR) |
| Sylpheed | Office & notes | EOS | 1 | missing |
| WPS Office | Office & notes | Garuda | 1 | `wps-office` (AUR) |
| Xournal++ | Office & notes | Manjaro | 1 | `xournalpp` (cachyos-extra-v3, extra) |
| Authenticator (2FA) | Passwords & security | Fedora | 1 | `authenticator` (cachyos-extra-v3, extra) |
| ClamUI | Passwords & security | Bazzite | 1 | `clamui` (cachyos-extra-v3, extra) |
| Enpass | Passwords & security | Manjaro | 1 | `enpass-bin` (AUR) |
| firewalld (firewall-config) | Passwords & security | EOS | 1 | `firewalld` (extra) |
| KWalletManager | Passwords & security | EOS | 1 | `kwalletmanager` (cachyos-extra-v3, extra) |
| Metadata Cleaner | Passwords & security | Fedora | 1 | `metadata-cleaner` (extra) |
| Obfuscate | Passwords & security | Fedora | 1 | `obfuscate` (cachyos-extra-v3, extra) |
| Proton VPN | Passwords & security | Flathub | 1 | `proton-vpn-gtk-app` (extra) |
| Raider (file shredder) | Passwords & security | Fedora | 1 | `raider` (cachyos-extra-v3, extra) |
| Seahorse | Passwords & security | EOS | 1 | `seahorse` (cachyos-extra-v3, extra) |
| Secrets (KeePass) | Passwords & security | Fedora | 1 | `secrets` (extra) |
| Aurynk (Android mirroring) | Sync & remote | Bazzite | 1 | `aurynk` (AUR) |
| Deskflow | Sync & remote | Bazzite | 1 | `deskflow` (cachyos-extra-v3, extra) |
| Dropbox | Sync & remote | Mint | 1 | `dropbox` (AUR) |
| Fragments | Sync & remote | Fedora | 1 | `fragments` (cachyos-extra-v3, extra) |
| Free Download Manager | Sync & remote | Garuda | 1 | `freedownloadmanager` (cachyos) |
| KTorrent | Sync & remote | EOS | 1 | `ktorrent` (cachyos-extra-v3, extra) |
| LocalSend | Sync & remote | Flathub | 1 | `localsend-bin` (AUR); `localsend` (cachyos) |
| Nextcloud client | Sync & remote | Garuda | 1 | `nextcloud-client` (extra) |
| NitroShare | Sync & remote | Garuda | 1 | `nitroshare` (AUR) |
| Parsec | Sync & remote | Bazzite | 1 | `parsec-bin` (cachyos) |
| PuTTY | Sync & remote | Garuda | 1 | `putty` (cachyos-extra-v3, extra) |
| Resilio Sync | Sync & remote | Bazzite | 1 | `rslsync` (AUR) |
| RustDesk | Sync & remote | Bazzite | 1 | `rustdesk-bin` (AUR); `rustdesk` (AUR) |
| Trayscale (Tailscale) | Sync & remote | Bazzite | 1 | `trayscale` (AUR) |
| Warpinator | Sync & remote | Garuda | 1 | `warpinator` (extra) |
| Xtreme Download Manager | Sync & remote | Garuda | 1 | `xdman-bin` (AUR) |
| AppImage Pool | System | Garuda | 1 | `appimagepool-appimage` (AUR) |
| asusctl | System | Bazzite | 1 | `asusctl` (extra) |
| Back In Time | System | Manjaro | 1 | `backintime` (AUR) |
| bauh | System | Garuda | 1 | `bauh` (AUR) |
| BorgBackup | System | Manjaro | 1 | `borg` (cachyos-extra-v3, extra) |
| CoolerControl | System | Bazzite | 1 | `coolercontrol` (cachyos-extra-v3, extra) |
| CPU-X | System | Bazzite | 1 | `cpu-x` (cachyos-extra-v3, extra) |
| Disk Usage Analyzer (Baobab) | System | EOS | 1 | `baobab` (cachyos-extra-v3, extra) |
| Fcitx5 | System | Bazzite | 1 | `fcitx5` (cachyos-extra-v3, extra) |
| Fedora Media Writer | System | Bazzite | 1 | `mediawriter` (cachyos-extra-v3, extra) |
| Filelight | System | EOS | 1 | `filelight` (cachyos-extra-v3, extra) |
| Genymotion | System | Garuda | 1 | `genymotion` (AUR) |
| GNOME Disks | System | Manjaro | 1 | `gnome-disk-utility` (cachyos-extra-v3, extra) |
| GNOME Firmware | System | Garuda | 1 | `gnome-firmware` (cachyos-extra-v3, extra) |
| GNOME Software | System | Garuda | 1 | `gnome-software` (cachyos-extra-v3, extra) |
| GPU-Viewer | System | Bazzite | 1 | `gpu-viewer` (cachyos-extra-v3, extra) |
| Grsync | System | Manjaro | 1 | `grsync` (cachyos-extra-v3, extra) |
| Ignition (autostart manager) | System | Bazzite | 1 | Flatpak only |
| Impression (USB writer) | System | Fedora | 1 | `impression` (cachyos-extra-v3, extra) |
| KDE Discover | System | Garuda | 1 | `discover` (cachyos-extra-v3, extra) |
| KDE Partition Manager | System | EOS | 1 | `partitionmanager` (cachyos-extra-v3, extra) |
| LACT (GPU control) | System | Bazzite | 1 | `lact` (cachyos-extra-v3, extra) |
| Mimic (default apps manager) | System | Bazzite | 1 | Flatpak only |
| Mintstick (USB writer) | System | Manjaro | 1 | `mintstick` (AUR) |
| Mission Center | System | Flathub | 1 | `mission-center` (cachyos-extra-v3, extra) |
| Nautilus (Files) | System | Fedora | 1 | `nautilus` (cachyos-extra-v3, extra) |
| Octopi | System | Garuda | 1 | `octopi` (cachyos) |
| OpenRazer | System | Bazzite | 1 | `openrazer-daemon` (extra) |
| OpenRGB | System | Bazzite | 1 | `openrgb` (cachyos-extra-v3, extra) |
| OpenTabletDriver | System | Bazzite | 1 | `opentabletdriver` (cachyos) |
| Pika Backup | System | Fedora | 1 | `pika-backup` (cachyos-extra-v3, extra) |
| Popsicle (USB flasher) | System | Manjaro | 1 | `popsicle` (cachyos) |
| Raspberry Pi Imager | System | Bazzite | 1 | `rpi-imager` (cachyos-extra-v3, extra) |
| Solaar (Logitech) | System | Bazzite | 1 | `solaar` (extra) |
| SysD Manager | System | Bazzite | 1 | `sysd-manager` (AUR) |
| Ventoy | System | Manjaro | 1 | `ventoy-bin` (cachyos); `ventoy` (AUR) |
| Waydroid | System | Bazzite | 1 | `waydroid` (extra) |
| Alacritty | Utilities | Pop | 1 | `alacritty` (cachyos-extra-v3, extra) |
| Catfish | Utilities | EOS | 1 | `catfish` (extra) |
| Clairvoyant | Utilities | Fedora | 1 | `clairvoyant` (cachyos-extra-v3, extra) |
| Clapgrep | Utilities | Bazzite | 1 | `clapgrep` (cachyos-extra-v3, extra) |
| Collision (hashes) | Utilities | Fedora | 1 | `collision` (extra) |
| Conky | Utilities | Garuda | 1 | `conky` (cachyos-extra-v3, extra) |
| Decoder (QR) | Utilities | Fedora | 1 | `decoder` (cachyos-extra-v3, extra) |
| Dialect (translator) | Utilities | Fedora | 1 | `dialect` (extra) |
| DroidCam | Utilities | Garuda | 1 | `droidcam` (AUR) |
| Extension Manager (GNOME) | Utilities | Flathub | 1 | `extension-manager` (cachyos-extra-v3, extra) |
| Eyedropper | Utilities | Fedora | 1 | `eyedropper` (cachyos-extra-v3, extra) |
| Flameshot | Utilities | Pop | 1 | `flameshot` (cachyos-extra-v3, extra) |
| Flatseal | Utilities | Flathub | 1 | `flatseal` (extra) |
| GNOME Clocks | Utilities | Fedora | 1 | `gnome-clocks` (cachyos-extra-v3, extra) |
| GNOME Maps | Utilities | Fedora | 1 | `gnome-maps` (extra) |
| GNOME Weather | Utilities | Fedora | 1 | `gnome-weather` (extra) |
| Google Earth Pro | Utilities | Mint | 1 | `google-earth-pro` (AUR) |
| Health | Utilities | Fedora | 1 | `health` (cachyos-extra-v3, extra) |
| Junction | Utilities | Fedora | 1 | `junction` (extra) |
| KRename | Utilities | EOS | 1 | `krename` (cachyos-extra-v3, extra) |
| Nostalgia (wallpapers) | Utilities | Fedora | 1 | `nostalgia` (AUR) |
| Railway (DieBahn) | Utilities | Fedora | 1 | `railway` (cachyos-extra-v3, extra) |
| SoundWire | Utilities | Garuda | 1 | `soundwire` (AUR) |
| Tangram (web apps) | Utilities | Fedora | 1 | `tangram` (extra) |
| Telegraph (Morse) | Utilities | Fedora | 1 | `telegraph` (AUR) |
| Tilix | Utilities | Pop | 1 | `tilix` (AUR) |
| Variety | Utilities | Garuda | 1 | `variety` (extra) |
| Waywallen | Utilities | Bazzite | 1 | `waywallen` (AUR) |
| Wike (Wikipedia) | Utilities | Fedora | 1 | `wike` (extra) |
| Yakuake | Utilities | Garuda | 1 | `yakuake` (cachyos-extra-v3, extra) |
