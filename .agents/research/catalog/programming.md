# karchy quick-install catalog: programming tools

Date: 2026-11-14. This is research only. Nothing was installed, and nothing outside this scratchpad was written.

Rule applied: packages come from pacman (Arch and CachyOS repos, plus `[omarchy]`, which karchy enables) or from the AUR via paru. No mise, no curl|bash installers, no Flatpak. Language toolchains come from pacman. Toolchain managers that are themselves pacman or AUR packages (`rustup`, `ghcup-hs-bin`) are flagged where they apply.

## Sources

**Read first**
- `~/Projects/karchy/.agents/research/catalog-research.md`, sections 1.3, 1.4, 1.5, 2.6 and 3.7 (Omarchy's and CachyOS's dev entries, plus the rustup setup). This file builds on it, and the "O" and "C" marks below come from there.
- `~/Projects/karchy/.agents/research/audit-usage.md`, the user's actual usage ("Audit" below).
- karchy's own package lists: `packaging/pkgbuilds/karchy{,-desktop}/PKGBUILD` and `system/fish/karchy.fish`. I used them to mark what karchy already ships ("in base").

**Popularity**
- **SO25**: Stack Overflow Developer Survey 2025, Technology section, all respondents (survey.stackoverflow.co/2025/technology). It covers languages, databases, cloud platforms, "other tools", IDEs and AI coding tools. Percentages are copied as given.
- **JB25**: JetBrains State of Developer Ecosystem 2025 (devecosystem-2025.jetbrains.com; 24,534 respondents, April to June 2025). The web pages give these numbers:
  - Primary languages: Python 35%, Java 33%, JavaScript 26%, TypeScript 22%. These came from secondary write-ups; the charts are images.
  - Trends: PostgreSQL has overtaken MySQL; TypeScript, Rust and Go are rising; PHP and Ruby are declining.
  - Cloud: AWS leads, and Azure and GCP each have about 25%.
  - The site gives no IDE percentages, and JetBrains warns that its own users are over-represented.
- **JB-AI26**: JetBrains AI Pulse survey, January 2026 (10,000+ professional developers). It reports work adoption of AI tools: Copilot 29%, ChatGPT 28%, Cursor 18%, Claude Code 18%, Codex 3%. A later JetBrains wave (May to July 2026) puts Claude Code at about 39%. The JetBrains blog returned HTTP 403, so these figures come from secondary write-ups of it (atmarkit.itmedia.co.jp, danilchenko.dev and others).
- **pkgstats**: Arch pkgstats, October 2026, giving the percentage of about 34,500 reporting Arch systems that have the package installed (`pkgstats.archlinux.de/api/packages/<name>`). This count **includes dependencies**, so libraries and runtimes that other packages pull in are inflated: lua 95%, gdb 91%, clang 75%, deno 59%, ruby 45%. Read it as a relative signal within a category.
- **AUR votes**: from the AUR RPC v5 (`/rpc/v5/info`), queried today.

**Package checks**
- Every repo package was checked with `pacman -Si` on this host. The host has `[cachyos]`, `[cachyos-v3]`, `[cachyos-core-v3]`, `[cachyos-extra-v3]`, `[core]`, `[extra]` and `[multilib]`.
- Everything the repos lack was checked with the AUR RPC.
- `[omarchy]` membership comes from `pkgs.omarchy.org/stable/x86_64/omarchy.db`, downloaded today (258 packages).
- Units, sysusers files and udev rules come from the archlinux.org file-list JSON.

## Notation

- **Repo** is the repo **as karchy resolves it**. karchy has only the generic `[cachyos]` repo, listed before `[core]`, and no `-v3` repos. A package this host shows in `cachyos-extra-v3,extra` therefore appears as **[extra]**.
  - `[cachyos]` means the package is in the generic CachyOS repo, which wins over `[extra]` when both carry it.
  - `[omarchy]` sits after `[extra]`/`[multilib]`, so it only matters for packages that are not in the official repos.
  - For AUR packages, the votes are given and the build type is marked: **-bin** (repackaged upstream binary), **src** (built from source), or **repack** (upstream binary tarball without a -bin name).
- **Pick**: **Yes** = offer it; **Maybe** = niche or weak package, offer under "more"; **Skip** = don't offer, with the reason.
- **Setup**: what a ⚙ feature script would have to do. "none" means a plain package entry.
- **in base**: karchy already installs it (`karchy` or `karchy-desktop` depends, or `base.txt`).

## Cross-cutting setup findings

1. **No user bin directories on PATH.** karchy's `system/fish/karchy.fish` adds only `$KARCHY_PATH/bin`. Nothing in the karchy tree adds `~/.local/bin`, `~/.cargo/bin`, `~/go/bin`, `~/.dotnet/tools`, the gem user bin, or composer's global bin. This affects every per-user install: `pipx`, `uv tool`, `cargo install`, `go install`, `npm -g` with a user prefix, `gem`, `dotnet tool -g`, `composer global`. One base fix would cover most catalog entries: `fish_add_path ~/.local/bin` in karchy.fish, plus a per-language path when that entry is installed.
2. **`/etc/profile.d` is sh-only.** Fish does not read it. The AUR Android SDK packages set `ANDROID_HOME` and their PATH entries there, so under karchy's fish session they need a fish snippet or `~/.config/environment.d`.
3. **Databases vs containers.** The user runs test databases as Podman containers (audit). A database server entry should therefore be optional, and the catalog could point to Podman for databases instead.
4. **Group memberships need a relogin.** Packages that create groups through sysusers: `docker` (docker), `wireshark-cli` (wireshark), `android-udev` (adbusers), `ollama` (an ollama system user only).

---

## Languages

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| Node.js (current) | Languages | `nodejs` 26.13 + `npm` | [cachyos] (nodejs), [extra] (npm) | Optional: a user prefix for `npm -g` (`npm config set prefix ~/.local`), which then needs `~/.local/bin` on PATH | SO25 JavaScript 66%, TypeScript 43.6%, Node.js 48.7%, npm 56.8%; JB25 JS 26% / TS 22% primary; pkgstats nodejs 58%, npm 63%; O, Audit | Yes |
| Node.js LTS | Languages | `nodejs-lts-krypton` (24) or `nodejs-lts-jod` (22) | [extra] | Conflicts with `nodejs`; pick one | pkgstats jod 8.9%, krypton 3.2% | Yes (as a choice in the Node entry) |
| pnpm | Languages | `pnpm` | [extra] | none | SO25 pnpm 13.4%; pkgstats 21%; O | Yes |
| Yarn | Languages | `yarn` (1.22 classic); Berry via `corepack` | [extra] | For Yarn 2+: `corepack enable` (writes shims; needs a writable prefix) | SO25 Yarn 21.1%; pkgstats 21% | Maybe |
| Bun | Languages | `bun` 1.4.4 (also `bun-bin` 1.4.3 in [omarchy]) | [extra] | none (`~/.bun/bin` for `bun add -g`) | pkgstats 8.3%; O, Audit | Yes |
| Deno | Languages | `deno` | [extra] | none | pkgstats 59% (inflated: dependency of other packages); O, Audit | Yes |
| Python tooling | Languages | `python` (in base) + `uv`, `python-pipx`; optional `python-poetry` | [extra] (python in [cachyos]) | `~/.local/bin` on PATH for `pipx` / `uv tool`. Policy option: `UV_PYTHON_DOWNLOADS=never`, so that uv uses pacman's Pythons instead of downloading its own | SO25 Python 57.9%, pip 40.9%; JB25 Python 35% primary (top); pkgstats uv 34%, pipx 25%, poetry 14.5%; O, Audit | Yes |
| Older Pythons | Languages | `python311`, `python313` | [cachyos] | none (uv and pipx find them as `python3.11`/`python3.13`) | pkgstats 3.5% / 1.3% | Maybe |
| PyPy | Languages | `pypy3` | [extra] | none | pkgstats 2.6%; O, Audit | Maybe |
| pyenv | Languages | `pyenv` | [extra] | Builds interpreters into `~/.pyenv`, outside pacman | pkgstats 9.4% | Skip (against the rule; uv + `python3xx` covers it) |
| Jupyter | Languages | `jupyterlab` (or `jupyter-notebook`) | [extra] | none | SO25 Jupyter 14.1% (IDE list); pkgstats 10.3% | Maybe |
| Go | Languages | `go`, `gopls`; optional `delve`, `golangci-lint`, `go-tools` | [extra] | `~/go/bin` on PATH for `go install` | SO25 Go 16.4%; JB25 "rising"; pkgstats go 59%, gopls 4.9%; O, Audit | Yes |
| Rust ⚙ | Languages | `rustup` + `clang` (alternative: `rust`, which conflicts with rustup) | [extra] | `rustup default stable` as the user; optional `rustup component add rust-analyzer rust-src`; `~/.cargo/bin` on PATH (catalog-research 3.7) | SO25 Rust 14.8%, Cargo 14.4%; JB25 "rising"; pkgstats rustup 27.6%, rust 36.9%; O, Audit | Yes |
| Rust extras | Languages | `sccache`, `cargo-nextest`, `bacon`, `cargo-watch` | [extra] | none | pkgstats sccache 4.5%, nextest 1%, bacon 1% | Maybe |
| Java (JDK) ⚙ | Languages | `jdk25-openjdk` (current LTS) / `jdk21-openjdk` / `jdk17-openjdk` / `jdk11-openjdk` / `jdk8-openjdk`, or `jdk-openjdk` (27, non-LTS); `maven`, `gradle` | [extra] | `archlinux-java set <version>` when several are installed | SO25 Java 29.4%, Maven 16.4%, Gradle 14.4%; JB25 Java 33% primary; pkgstats jdk-openjdk 44%, jdk21 21%, jdk17 19%, jdk25 5.6%; O, Audit | Yes (offer a version choice; default jdk25) |
| Kotlin | Languages | `kotlin`; optional `kotlin-language-server` (AUR src, 15 votes, pins java-runtime=11) | [extra] / AUR | none | SO25 Kotlin 10.8%; JB25 "growing"; pkgstats 3.1%; O, Audit | Yes |
| .NET SDK | Languages | `dotnet-sdk` (10.0.14, 1xx band) plus optional `dotnet-sdk-9.0` and `dotnet-sdk-8.0` side by side; or `dotnet-sdk-bin` (10.0.15, 4xx band; conflicts with dotnet-sdk) | [extra] / [cachyos] | `~/.dotnet/tools` on PATH for `dotnet tool -g`; optional `DOTNET_CLI_TELEMETRY_OPTOUT=1` | SO25 C# 27.8%, NuGet 18.9%, ASP.NET Core 19.7%; pkgstats dotnet-sdk 16.9%, -8.0 5.7%; O, Audit (dotnet-sdk installed) | Yes |
| Ruby | Languages | `ruby`, `rubygems`, `ruby-bundler` | [extra] | Arch installs gems into the user dir by default; add `~/.local/share/gem/ruby/3.4.0/bin` to PATH. Rails: `gem install rails` | SO25 Ruby 6.4%; JB25 "declining"; pkgstats ruby 45% (inflated); O | Yes |
| PHP | Languages | `php`, `composer`; optional `php-fpm`, `xdebug`; `symfony-cli` | [cachyos] (php, php-fpm), [extra] (composer, xdebug), [omarchy] (symfony-cli) | Enable the needed extensions in `/etc/php/php.ini` (pdo_mysql, iconv and others are commented out by default); composer's global bin dir on PATH | SO25 PHP 18.9%; JB25 "stable/declining"; pkgstats php 22%, composer 6.4%; O | Yes |
| C/C++ toolchain | Languages | `base-devel` (gcc, make; in base) + `clang` (includes clangd and clang-tidy; provides clang-tools-extra), `llvm`, `lld`, `lldb`, `gdb`, `cmake`, `ninja`, `meson`; optional `ccache`, `mold`, `valgrind`, `bear` | [core] / [extra] | none | SO25 C++ 23.5%, C 22%, Make 23.2%; pkgstats cmake 74%, ninja 70%, meson 55%, lldb 13.6%; Audit (cmake kept in `~/.local/bin`) | Yes |
| Zig | Languages | `zig` 0.17.1 + `zls-bin` 0.17.0 (AUR -bin, 5 votes) | [extra] / AUR | none. Repo `zls` is 0.15.1 and does not match zig 0.17; use `zls-bin` until the repo catches up | pkgstats zig 8.4%, zls 2.2%; O, Audit | Yes |
| Elixir | Languages | `elixir`, `erlang`; optional `elixir-ls` (AUR src, 9 votes) | [extra] | `mix local.hex`, `mix local.rebar` as the user; Phoenix via `mix archive.install hex phx_new` | not in SO25 top 20; pkgstats elixir 2.1%; O | Maybe |
| Haskell ⚙ | Languages | Repo: `ghc` 9.6.7, `cabal-install`, `stack`, `haskell-language-server`. Alternative: `ghcup-hs-bin` (AUR -bin, 33 votes) | [extra] / AUR | Repo GHC is old and dynamically linked. From memory of the Arch wiki (unverified, the wiki was unreadable): cabal needs dynamic linking set in `~/.cabal/config`. ghcup instead puts GHC and HLS in `~/.ghcup`, the way rustup does | not in SO25 top 20; pkgstats ghc 7.1%, ghcup 1.1% | Maybe (decide: repo ghc or ghcup) |
| Lua | Languages | `lua`, `luajit`, `luarocks`, `lua-language-server` | [extra] | `~/.luarocks/bin` for `luarocks --local` | SO25 Lua 9.2%; pkgstats luarocks 15%, lua-language-server 7.2% | Yes |
| Dart | Languages | `dart` 3.13.7 | [extra] | none | SO25 Dart 5.9%; pkgstats 2.6% | Maybe (Flutter bundles its own) |
| Flutter | Languages | `flutter-bin` 3.50 (AUR repack of Google's tarball, 10 votes; overlays `/opt/flutter` with unionfs-fuse; provides and conflicts with `dart`) | AUR | `flutter doctor`; the Android SDK for mobile targets. The AUR `flutter` (src, 152 votes) is flagged out of date since 2026-04-29 and requires `dart<3.12`, while the repo has 3.13.7, so it does not resolve | SO25 Dart 5.9%; pkgstats flutter-bin 0.85%, flutter 0.11% | Maybe |
| Android SDK ⚙ | Languages | `android-tools` + `android-udev` (adb/fastboot), `android-sdk-cmdline-tools-latest`, `android-sdk-platform-tools`, `android-sdk-build-tools`, `android-platform`, optional `android-emulator` | [extra] (tools, udev) / AUR -bin-style repacks (votes: cmdline 37, platform-tools 1311, build-tools 501, platform 190) | `/opt/android-sdk` is root-owned, so `sdkmanager` needs a group with write access to it, or the SDK lives in `~/Android/Sdk` instead. `ANDROID_HOME` is set only in `/etc/profile.d` (finding 2). `sdkmanager --licenses`. Add the user to `adbusers` | SO25 Kotlin 10.8% / Android Studio 15%; pkgstats android-tools 39%, android-udev 36%; Audit (cmdline-tools installed) | Yes |
| OCaml | Languages | `opam`, `ocaml` | [extra] | `opam init` as the user | pkgstats ocaml 6.6%, opam 2.3%; O | Maybe |
| Clojure | Languages | `clojure`, `leiningen` (+ `rlwrap`) | [extra] | none | pkgstats 1.8%; O | Maybe |
| Scala | Languages | `scala3` (AUR, 17 votes) or `scala-cli` (AUR, 5 votes); AUR `scala` 2.13 is flagged out of date | AUR | none | O | Skip (weak packages) |
| Swift | Languages | `swift-bin` (AUR -bin, 95 votes) | AUR | none | SO25 Swift 5.4%; pkgstats 0.4% | Maybe |
| Julia | Languages | `julia` | [extra] | none | pkgstats 3.2% | Maybe |
| R | Languages | `r` | [extra] | none | pkgstats 10% | Maybe |
| Gleam / Nim / Crystal / Odin | Languages | `gleam`, `nim`, `crystal`, `odin` | [extra] | none | pkgstats nim 2.5%, crystal 1.2%, odin 1.2%, gleam 0.7%; Audit (odin) | Maybe (Odin: Yes for the user) |

## Editors & IDEs

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| VS Code (Microsoft build) | Editors & IDEs | `visual-studio-code-bin` | [omarchy] (also AUR -bin, 1714 votes) | **in base** (karchy-desktop) | SO25 75.9% (top IDE); pkgstats 19.4%; Audit (28 extensions) | in base |
| Code - OSS | Editors & IDEs | `code` | [extra] | none. It uses Open VSX, so Microsoft-only extensions (C# Dev Kit, Pylance, Remote/Dev Containers) are missing | pkgstats 15.3%; C | Skip (the MS build is base) |
| VSCodium | Editors & IDEs | `vscodium` (or `vscodium-bin`, AUR 399 votes) | [cachyos] | none (Open VSX) | SO25 6.2%; pkgstats -bin 5.1%, repo 2.4% | Maybe |
| Cursor | Editors & IDEs | `cursor-bin` | [cachyos] (also [omarchy]) | none | SO25 17.9%; JB-AI26 18% work use; pkgstats 2.5%; O | Yes |
| Zed | Editors & IDEs | `zed` | [extra] | none (pulls nodejs and npm) | SO25 7.3%; pkgstats 11.6%; O, Audit | Yes |
| Neovim | Editors & IDEs | `neovim`; optional `tree-sitter-cli`, `ripgrep`, `fd`, `lazygit` for LazyVim-style configs | [extra] | none | SO25 14%; pkgstats 44%; O | Yes |
| Vim | Editors & IDEs | `vim` | [extra] | none | SO25 24.3%; pkgstats 66%; O, C | Yes |
| Helix | Editors & IDEs | `helix` | [extra] | none. Arch installs the binary as `helix`, not `hx` (checked in the file list) | pkgstats 8.3%; O | Yes |
| Emacs | Editors & IDEs | `emacs-wayland` (pgtk, the right one under Hyprland) or `emacs` | [extra] | none | pkgstats emacs 8.7%, emacs-wayland 3.2%; O, C | Yes |
| Kakoune | Editors & IDEs | `kakoune` | [extra] | none | pkgstats 1.3% | Maybe |
| micro | Editors & IDEs | `micro` | [extra] | **in base** | SO25 Nano 12.2% (closest analogue); pkgstats 13.2% | in base |
| Sublime Text 4 | Editors & IDEs | `sublime-text-4` | [omarchy] (also AUR -bin-style, 92 votes) | none (paid licence, unlimited evaluation) | SO25 10.5%; pkgstats 2.5%; O | Yes |
| Kate | Editors & IDEs | `kate` | [extra] | none (pulls KDE Frameworks) | pkgstats 36%; Audit (text/plain default on the old machine) | Maybe |
| JetBrains Toolbox | Editors & IDEs | `jetbrains-toolbox` | AUR repack, 222 votes | none. It downloads and self-updates IDEs into `~/.local/share/JetBrains`, outside pacman | JB25 (JetBrains IDEs pair with every top language); pkgstats 4.3%; N | Yes (the simplest JetBrains route) |
| IntelliJ IDEA | Editors & IDEs | `intellij-idea-oss` (open-source build; provides intellij-idea-community-edition) or `intellij-idea-ultimate-edition` (JetBrains binary) | [extra] / AUR repack, 453 votes | none | SO25 27.1%; JB25; pkgstats community 2.9%, ultimate 1.5% | Yes |
| PyCharm | Editors & IDEs | `pycharm-community-edition` or `pycharm` (JetBrains binary) | [extra] / AUR repack, 313 votes | none | SO25 15%; pkgstats repo 2.9%, AUR 0.9%; C | Yes |
| WebStorm | Editors & IDEs | `webstorm` | AUR repack, 189 votes | none (free for non-commercial use) | SO25 7.6%; pkgstats 0.8% | Maybe |
| Rider | Editors & IDEs | `rider` | AUR repack, 111 votes | none (free for non-commercial use). It is the Linux answer to Visual Studio (SO25 29%, Windows only) | SO25 7.1%; pkgstats 0.95% | Yes (the user does .NET) |
| CLion | Editors & IDEs | `clion` | AUR repack, 251 votes | none (free for non-commercial use) | JB25; pkgstats 1.35% | Maybe |
| GoLand | Editors & IDEs | `goland` | AUR repack, 62 votes | none | pkgstats 0.3% | Maybe |
| RustRover | Editors & IDEs | `rustrover` | AUR repack, 39 votes | none (free for non-commercial use) | pkgstats 0.8% | Maybe |
| PhpStorm | Editors & IDEs | `phpstorm` | AUR repack, 234 votes | none | SO25 5.8%; pkgstats 0.4% | Maybe |
| DataGrip | Editors & IDEs | `datagrip` | AUR repack, 73 votes | none | pkgstats 0.4% | Maybe |
| Android Studio | Editors & IDEs | `android-studio` | AUR repack, 1147 votes | none. It bundles its own JBR, and its setup wizard downloads an SDK into `~/Android/Sdk` (an alternative to the AUR SDK packages) | SO25 15%; pkgstats 6.9%; Audit | Yes |
| Qt Creator | Editors & IDEs | `qtcreator` | [extra] | none | pkgstats 7%; C | Maybe |
| Eclipse | Editors & IDEs | `eclipse-java-bin` | AUR -bin, 50 votes | none | SO25 7.1%; pkgstats 0.65% | Maybe |
| NetBeans | Editors & IDEs | `netbeans` | [extra] | none | pkgstats 0.9% | Skip (low use) |
| Lapce | Editors & IDEs | `lapce` | [extra] (0.4.6) | none | pkgstats 1.6% | Skip (stalled upstream) |
| Windsurf | Editors & IDEs | **missing** (not in the repos; no AUR package by that name) | missing | n/a | SO25 4.9% | Skip (unavailable) |

## Git

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| git | Git | `git` | [extra] | **in base** | SO25 GitHub 81.1% | in base |
| GitHub CLI ⚙ | Git | `github-cli` | [extra] | `gh auth login`, then `gh auth setup-git` (on the old machine git's credential helper points at gh; HTTPS pushes fail without it) | SO25 GitHub 81.1%; pkgstats 23.7%; O, Audit ("day one") | Yes |
| GitLab CLI | Git | `glab` | [extra] | `glab auth login` | SO25 GitLab 35.6%; pkgstats 3.7% | Yes |
| lazygit | Git | `lazygit` | [extra] | none | pkgstats 17.5%; Audit | Yes |
| gitui | Git | `gitui` | [extra] | none | pkgstats 3.2% | Maybe |
| tig | Git | `tig` | [extra] | none | pkgstats 5.9% | Maybe |
| delta | Git | `git-delta` | [extra] | Optional git config: `core.pager delta`, `interactive.diffFilter "delta --color-only"` | pkgstats 17.2% | Yes |
| difftastic | Git | `difftastic` | [extra] | Optional: `git config diff.external difft` | pkgstats 4.5% | Maybe |
| Git LFS | Git | `git-lfs` | [extra] | `git lfs install` as the user | pkgstats 20.8% | Yes |
| pre-commit | Git | `pre-commit` | [extra] | none (per repo: `pre-commit install`) | pkgstats 4% | Maybe |
| GitKraken | Git | `gitkraken` | AUR repack, 310 votes | none (account; private repos need a paid plan) | pkgstats 0.8% | Maybe |
| GitHub Desktop | Git | `github-desktop` (or `github-desktop-bin`, AUR 61 votes) | [cachyos] | none | pkgstats -bin 1.35%, repo 0.9% | Maybe |
| gitg | Git | `gitg` | [extra] | none | pkgstats 4.7% | Maybe |
| Meld | Git | `meld` | [extra] | Optional: `git config merge.tool meld` | pkgstats 27.9%; Audit | Yes |
| Beyond Compare | Git | `bcompare` | AUR repack (Qt6), 108 votes | Paid licence; optional `git config diff.tool bc` | pkgstats 0.7%; Audit | Yes (the user uses it) |
| SourceGit | Git | `sourcegit-bin` | AUR -bin, 15 votes | none | pkgstats 0.2% | Skip (niche) |
| GitButler | Git | `gitbutler-bin` | AUR -bin, 14 votes | none | pkgstats 0.2% | Skip (niche) |

## APIs & databases

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| Bruno | APIs & databases | `bruno-bin` (the source `bruno` builds with nvm, 18 votes) | AUR -bin, 57 votes | none | pkgstats -bin 1.2% | Yes |
| Postman | APIs & databases | `postman-bin` | AUR -bin, 314 votes | none (account) | pkgstats 3.4% | Yes |
| Insomnia | APIs & databases | `insomnia-bin` (the source `insomnia` is flagged out of date 2026-11-13) | AUR -bin, 162 votes | none | pkgstats 0.6% | Maybe |
| Yaak | APIs & databases | `yaak` (+ `yaak-cli`) | [extra] | none | pkgstats 0.2% | Maybe (the only GUI API client in the official repos) |
| Hoppscotch | APIs & databases | `hoppscotch-bin` | AUR -bin, 11 votes, flagged out of date | none | n/a | Skip |
| DBeaver | APIs & databases | `dbeaver` | [extra] | none (pulls java-runtime>=21) | pkgstats 7.5% | Yes |
| Beekeeper Studio | APIs & databases | `beekeeper-studio-bin` | AUR -bin, 33 votes | none | pkgstats 0.5% | Maybe |
| pgAdmin 4 | APIs & databases | `pgadmin4-desktop` | AUR, 22 votes | none | pkgstats 0.3% | Maybe |
| DbGate | APIs & databases | `dbgate-bin` | AUR -bin, 13 votes | none | pkgstats 0.1% | Skip (niche) |
| DB Browser for SQLite | APIs & databases | `sqlitebrowser` | [extra] | none | SO25 SQLite 37.5%; pkgstats 13.7% | Yes |
| MongoDB Compass | APIs & databases | `mongodb-compass` (or `mongodb-compass-bin`, AUR 10 votes) | [cachyos] | none | SO25 MongoDB 24%; pkgstats 0.5% | Maybe |
| MySQL Workbench | APIs & databases | `mysql-workbench` | [extra] | none | SO25 MySQL 40.5%; pkgstats 2.8% | Maybe |
| PostgreSQL ⚙ | APIs & databases | `postgresql` 18.6 | [extra] | `sudo -iu postgres initdb -D /var/lib/postgres/data`; `systemctl enable --now postgresql.service`; `sudo -iu postgres createuser -s $USER`. karchy is btrfs with snapper, so consider `chattr +C` on the data dir before initdb. Major upgrades need `pg_upgrade` | SO25 55.6% (top DB); JB25 "overtook MySQL"; pkgstats 16.3% | Yes |
| MariaDB ⚙ | APIs & databases | `mariadb` 13.0 or `mariadb-lts` 12.3 (provides `mysql`) | [extra] | `mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql`; `systemctl enable --now mariadb.service`; `mariadb-secure-installation` | SO25 MariaDB 22.5% (MySQL 40.5%); pkgstats 22% | Yes |
| MySQL (Oracle) | APIs & databases | `mysql` | AUR src, 83 votes (a long build) | Same as MariaDB | SO25 40.5%; AUR popularity 0.002 | Skip (MariaDB covers it; or use a container) |
| Valkey (Redis) ⚙ | APIs & databases | `valkey` (provides and conflicts with `redis`; ships `valkey.service` and a `redis.service` alias) | [extra] | `systemctl enable --now valkey.service`; the sysusers file creates the valkey user | SO25 Redis 28%; pkgstats valkey 5.4%, redis (AUR src 8.10, 8 votes) 2.1% | Yes |
| MongoDB server ⚙ | APIs & databases | `mongodb-bin`, `mongosh-bin` | AUR -bin, 98 / 34 votes | `systemctl enable --now mongodb.service` (unit name not verified) | SO25 24%; pkgstats 1.1% / 1.7% | Maybe (or a container) |
| SQLite | APIs & databases | `sqlite` (includes the `sqlite3` CLI) | [core] | none (already a dependency of the system) | SO25 37.5% | in base (dependency) |
| SQL Server | APIs & databases | `mssql-server`, `mssql-tools` | AUR, 31 / 29 votes | `mssql-conf setup` | SO25 30.1%; pkgstats 0.2% | Skip (container instead) |
| Elasticsearch / OpenSearch | APIs & databases | `opensearch` [extra]; `elasticsearch` AUR (11 votes) | [extra] / AUR | service + JVM heap configuration | SO25 Elasticsearch 16.7%; pkgstats es 0.15% | Skip (container instead) |
| pgcli | APIs & databases | `pgcli` | [extra] | none | pkgstats 1.6% | Yes |
| usql | APIs & databases | `usql` | AUR src, 12 votes | none | pkgstats 0.16% | Skip (niche) |
| lazysql | APIs & databases | `lazysql` | AUR, 4 votes | none | pkgstats 0.2% | Skip (niche) |

## Cloud & containers

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| Podman ⚙ | Cloud & containers | `podman`, `podman-compose` (+ `nvidia-container-toolkit` for GPUs) | [extra] | See catalog-research 3.3 (karchy's primary engine); `nvidia-ctk cdi generate` on NVIDIA | SO25 Podman 11.1%; pkgstats 19.1%; Audit (111 GB of containers) | Yes |
| Docker ⚙ | Cloud & containers | `docker`, `docker-compose`, `docker-buildx` | [extra] | `systemctl enable --now docker.socket`; the `docker` group (sysusers) plus a relogin; ufw interplay (catalog-research 3.3) | SO25 Docker 71.1% (top tool); pkgstats docker 45%, compose 36%, buildx 18% | Yes |
| Buildah / Skopeo | Cloud & containers | `buildah`, `skopeo` | [extra] | none | pkgstats 2.7% / 4.1% | Maybe |
| lazydocker | Cloud & containers | `lazydocker` | [extra] | For Podman: `DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock` + `systemctl --user enable --now podman.socket` | pkgstats 4.7% | Maybe |
| dive | Cloud & containers | `dive` | [extra] | none | pkgstats 2.9% | Maybe |
| Dev Containers CLI | Cloud & containers | `devcontainer-cli` | AUR (npm build), 9 votes | Needs Docker, or Podman via `--docker-path podman`. In VS Code, the Microsoft Dev Containers extension (base VS Code) is the usual route | pkgstats 0.3% | Maybe |
| kubectl | Cloud & containers | `kubectl` | [extra] | `~/.kube/config` from the cluster | SO25 Kubernetes 28.5%; pkgstats 8.1% | Yes |
| k9s | Cloud & containers | `k9s` | [extra] | none | pkgstats 2.7% | Yes |
| Helm | Cloud & containers | `helm` | [extra] | none | pkgstats 4.5% | Yes |
| kubectx / stern / kustomize | Cloud & containers | `kubectx`, `stern`, `kustomize` | [extra] | none | pkgstats 1.3% / 0.4% / 1.1% | Maybe |
| Local clusters | Cloud & containers | `kind`, `minikube` | [extra] | They need Docker or Podman (rootless Podman needs cgroup delegation for kind) | pkgstats minikube 3%, kind 0.6% | Maybe |
| k3d | Cloud & containers | `k3d-bin` | AUR -bin, 0 votes, flagged out of date 2026-06-11 | n/a | pkgstats 0% | Skip |
| Argo CD CLI | Cloud & containers | `argocd` | [extra] | none | pkgstats 0.7% | Skip (niche) |
| Terraform | Cloud & containers | `terraform` (BUSL licence) | [extra] | none | SO25 Terraform 17.8%; pkgstats 4% | Yes |
| OpenTofu | Cloud & containers | `opentofu` | [extra] | none | pkgstats 1.6% | Yes |
| Packer / Pulumi | Cloud & containers | `packer`, `pulumi` | [extra] | none | pkgstats 2.2% / 0.3% | Maybe |
| Ansible | Cloud & containers | `ansible` | [extra] | none | SO25 Ansible 11.7%; pkgstats 8.5%; C | Yes |
| AWS CLI | Cloud & containers | `aws-cli-v2` (conflicts with v1 `aws-cli`); optional `aws-session-manager-plugin` (AUR, 22 votes) | [extra] | `aws configure` or `aws configure sso` | SO25 AWS 43.3%; JB25 AWS leads; pkgstats v2 2.7%, v1 3.2% | Yes |
| Azure CLI | Cloud & containers | `azure-cli` | [extra] | `az login` | SO25 Azure 26.3%; pkgstats 1.5% | Yes |
| Google Cloud CLI | Cloud & containers | `google-cloud-cli` | AUR repack of Google's tarball, 207 votes | `gcloud init` (large; it updates components only through the package) | SO25 Google Cloud 24.6%; pkgstats 2.3% | Yes |
| Cloudflare | Cloud & containers | `wrangler`, `cloudflared` | [extra] | `wrangler login`; cloudflared tunnels | SO25 Cloudflare 20.1%; pkgstats cloudflared 4.1%, wrangler 0.75% | Maybe |
| DigitalOcean CLI | Cloud & containers | `doctl` | [extra] | `doctl auth init` | SO25 DigitalOcean 10.7%; pkgstats 0.65% | Maybe |
| Fly.io CLI | Cloud & containers | `flyctl-bin` | AUR -bin, 14 votes | `fly auth login` | pkgstats 0.3% | Skip (niche) |
| Vercel / Firebase / Supabase CLIs | Cloud & containers | `vercel`, `firebase-tools`, `supabase-bin` | AUR, 5 / 10 / 3 votes | login | SO25 Vercel 10.6%, Firebase 13.1%, Supabase 5.4%; pkgstats near 0 | Skip (weak packages; these CLIs normally come via npm) |
| ngrok | Cloud & containers | `ngrok` | AUR repack, 122 votes | `ngrok config add-authtoken` | pkgstats 2.4% | Maybe |

## AI coding

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| Claude Code | AI coding | `claude-code` | [cachyos] (also [omarchy], AUR 102 votes) | none (login on first run) | SO25 9.7%; JB-AI26 18% in Jan 2026, about 39% by mid-2026; pkgstats 7.9%; O, Audit | Yes |
| Codex CLI | AI coding | `openai-codex` 0.169 (or `openai-codex-bin` 0.162 in [omarchy]) | [extra] | none | JB-AI26 3% (before the desktop app relaunch); pkgstats 5.8%; O, Audit | Yes |
| Gemini CLI | AI coding | `gemini-cli` | [extra] | none (Google login) | pkgstats 2.8% | Yes |
| GitHub Copilot CLI | AI coding | `github-copilot-cli` (binary `copilot`) | [cachyos] (also [omarchy]) | none (GitHub login) | JB-AI26 Copilot 29% (the top tool at work); pkgstats 1% | Yes |
| OpenCode | AI coding | `opencode` (or `opencode-bin`, AUR 53 votes) | [extra] | none | pkgstats 11.9%; O, Audit | Yes |
| Cursor CLI | AI coding | `cursor-cli` | [omarchy] (also AUR) | none | SO25 Cursor 17.9%; pkgstats 0.2% | Maybe |
| Pi | AI coding | `pi-coding-agent-bin` | AUR -bin, 24 votes | none | pkgstats 0.4%; O, Audit | Yes (the user uses it) |
| T3 Code | AI coding | `t3code-bin` | [omarchy] (also AUR -bin, 12 votes) | none | pkgstats 0.5%; O, Audit | Yes (the user uses it) |
| Crush | AI coding | `crush-bin` [omarchy] or `crush` (AUR src, 4 votes) | [omarchy] / AUR | none | pkgstats 0.2% | Maybe |
| Amp | AI coding | `ampcode` (CLI, AUR, 2 votes); `amp-desktop-bin` | AUR / [omarchy] | none | pkgstats 0.03% | Maybe |
| Aider | AI coding | `aider-chat` | AUR src, 6 votes | none | SO25 1.9%; pkgstats 0.05% | Maybe |
| Goose | AI coding | `goose-cli` | AUR, 0 votes | none | pkgstats 0.02% | Skip |
| Qwen Code | AI coding | `qwen-code-bin` | AUR -bin, 3 votes | none | pkgstats 0.05% | Skip |
| Google Antigravity | AI coding | `antigravity` (2.0 platform, 25 votes), `antigravity-ide` (84), `antigravity-cli` (35) | AUR | none | pkgstats 3.3% / 1.5% / 2% | Maybe |
| Kiro | AI coding | `kiro-ide` (14 votes), `kiro-cli` (8) | AUR | none | pkgstats 0.2% / 0.07% | Maybe |
| Claude Desktop | AI coding | `claude-desktop` | [cachyos] (also [omarchy]) | none | pkgstats 2.8%; O | Yes |
| Codex Desktop | AI coding | `openai-codex-desktop` | [omarchy] | none | pkgstats 0.3%; O | Maybe |
| Ollama ⚙ | AI coding | `ollama` + `ollama-cuda` (NVIDIA) / `ollama-vulkan` / `ollama-rocm` (AMD) | [extra] | `systemctl enable --now ollama.service` (the sysusers file creates the ollama user) | pkgstats ollama 15.2%, cuda 3.7%; O, C | Yes |
| llama.cpp | AI coding | `llama-cpp` + backend `ggml-cuda` / `ggml-vulkan` / `ggml-hip` | [extra] | none | pkgstats 3.1% | Maybe |
| LM Studio | AI coding | `lmstudio-bin` | [omarchy] (also AUR -bin, 71 votes) | none | pkgstats 2%; O | Yes |
| Jan | AI coding | `jan-bin` | AUR -bin, 14 votes | none | pkgstats 0.3% | Maybe |
| Open WebUI | AI coding | `open-webui` | AUR, orphaned, flagged out of date 2026-10-26 | n/a | pkgstats n/a | Skip (run it as a Podman container) |
| Windsurf | AI coding | **missing** | missing | n/a | SO25 4.9% | Skip |

## Terminal tools

| Entry | Category | Arch package(s) | Repo | Setup needed | Popularity evidence | Pick |
|---|---|---|---|---|---|---|
| ripgrep | Terminal tools | `ripgrep` | [extra] | none | pkgstats 80% | Yes |
| fd | Terminal tools | `fd` | [extra] | none | pkgstats 51% | Yes |
| jq | Terminal tools | `jq` | [extra] | **in base** | pkgstats 77% | in base |
| yq | Terminal tools | `go-yq` (mikefarah's yq) **or** `yq` (Python jq wrapper); they conflict | [extra] | none | pkgstats go-yq 3.9%, yq 8.4% | Yes (`go-yq`; it is the one most docs mean) |
| jaq | Terminal tools | `jaq` | [extra] | none | pkgstats 0.8% | Skip (jq is base) |
| HTTPie | Terminal tools | `httpie` | [extra] | none | pkgstats 4.3% | Yes |
| xh | Terminal tools | `xh` | [extra] | none | pkgstats 1.7% | Maybe |
| Hurl | Terminal tools | `hurl` | [extra] | none | pkgstats 0.5% | Maybe |
| just | Terminal tools | `just` | [extra] | none | pkgstats 8.6% | Yes |
| direnv ⚙ | Terminal tools | `direnv` | [extra] | Add `direnv hook fish \| source` to the fish config | pkgstats 5.5% | Yes |
| hyperfine | Terminal tools | `hyperfine` | [extra] | none | pkgstats 6.7% | Yes |
| tokei | Terminal tools | `tokei` (alternative `scc`, AUR, 16 votes) | [extra] | none | pkgstats tokei 5.3%, scc 0.9% | Yes |
| ShellCheck | Terminal tools | `shellcheck` | [extra] | none (pulls about 6 Haskell library packages) | pkgstats 19.7%; Audit | Yes |
| shfmt | Terminal tools | `shfmt` | [extra] | none | pkgstats 13.2% | Yes |
| actionlint | Terminal tools | `actionlint` | [extra] | none | pkgstats 0.8%; Audit | Maybe (Yes for the user) |
| fzf | Terminal tools | `fzf` | [extra] | **in base** | pkgstats 58% | in base |
| bat | Terminal tools | `bat` | [extra] | none | pkgstats 47% | Yes |
| eza | Terminal tools | `eza` | [extra] | none | pkgstats 35% | Yes |
| zoxide ⚙ | Terminal tools | `zoxide` | [extra] | `zoxide init fish \| source` in the fish config | pkgstats 23% | Yes |
| entr / watchexec | Terminal tools | `entr`, `watchexec` | [extra] | none | pkgstats 3.8% / 1.6% | Maybe |
| tldr pages | Terminal tools | `tealdeer` (conflicts with Python `tldr`) | [extra] | `tldr --update` as the user | pkgstats tealdeer 13.4%, tldr 16.7% | Yes |
| strace / ltrace | Terminal tools | `strace`, `ltrace` | [extra] | none | pkgstats 41% / 5.7% | Yes (strace) |
| tmux | Terminal tools | `tmux` | [extra] | none | pkgstats 46% | Yes |
| Zellij | Terminal tools | `zellij` | [extra] | none | pkgstats 7.8% | Maybe |
| ast-grep | Terminal tools | `ast-grep` | [extra] | none | pkgstats 2% | Maybe |
| glow | Terminal tools | `glow` | [extra] | none | pkgstats 27.7% | Maybe |
| lnav | Terminal tools | `lnav` | [extra] | none | pkgstats 2.6% | Maybe |
| mitmproxy | Terminal tools | `mitmproxy` | [extra] | Trust its CA for HTTPS interception | pkgstats 4.6% | Maybe |
| Wireshark ⚙ | Terminal tools | `wireshark-qt` | [extra] | Add the user to the `wireshark` group (created by wireshark-cli's sysusers file) for non-root capture; relogin | pkgstats 25% | Yes |
| age / sops | Terminal tools | `age`, `sops` | [extra] | none | pkgstats 4.4% / 1.6% | Maybe |
| atuin | Terminal tools | `atuin` | [extra] | `atuin init fish \| source`; optional sync account | pkgstats 4.7% | Maybe |
| hexyl / dust | Terminal tools | `hexyl`, `dust` | [extra] | none | pkgstats 3.6% / 14.7% | Maybe |
| btop / gum | Terminal tools | `btop`, `gum` | [extra] | **in base** | — | in base |

## Not verified

- **JetBrains 2025 percentages.** Only the headline language shares and qualitative trends were readable. The IDE, database and AI-tool charts are images, and blog.jetbrains.com returned HTTP 403. The JB-AI26 numbers come from secondary write-ups of JetBrains' AI Pulse survey, not from JetBrains directly.
- **Setup steps quoted from memory of upstream docs** (the Arch wiki is bot-walled): PostgreSQL `chattr +C` on btrfs, the cabal dynamic-linking config for repo GHC, PHP's default-disabled extensions, the Ruby gem user path version (`3.4.0`), and the `mongodb.service` unit name from `mongodb-bin`. The unit and sysusers files listed for postgresql, mariadb, valkey, docker, ollama, wireshark-cli and android-udev *were* checked in archlinux.org's file lists.
- **AUR packages were not built.** Votes, popularity, out-of-date flags and dependencies come from the RPC only. Flutter-bin's unionfs overlay and the Android SDK profile.d script were read from their PKGBUILDs.
- **Windsurf, `cline`, `google-cloud-sdk`, `pulumi-bin` and `llama.cpp(-cuda/-vulkan)` were not found under those names.** Windsurf has no package anywhere. The others exist under different names (`google-cloud-cli`, `pulumi`, `llama-cpp`) or only as `-git` builds.
- **Free tiers of JetBrains IDEs.** JetBrains made several IDEs free for non-commercial use (The Register), but which of the unified IDEA and PyCharm builds carry free tiers was not re-checked.
- **pkgstats** counts dependencies, so popular runtimes pulled in by other packages read high.
