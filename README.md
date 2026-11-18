# Project picker for Omarchy

A Quickshell overlay hosted by the existing Omarchy shell. The plugin needs
Omarchy 4 with its plugin host and Hyprland Lua configuration, plus Python 3.
The default editor is VS Code. Terminals use Omarchy's default terminal through
`xdg-terminal-exec`. No build step or third-party Python packages are required.

![Project picker searching for its own source repository](docs/preview.png)

## Install

Install the plugin from GitHub:

```sh
omarchy plugin add https://github.com/Nulifyer/omarchy-project-picker --enable
```

Then set up Ctrl+Alt+P using the included installer:

```sh
python3 ~/.config/omarchy/plugins/nulifyer.project-picker/install.py
```

On [karchy](https://github.com/Nulifyer/karchy), use `karchy plugin add` with
the same URL; the plugin lands in `~/.config/karchy/plugins/` and the installer
below works the same way, using `karchy` and `karchy-shell`.

This enables the plugin and adds the shortcut to `~/.config/hypr/bindings.lua`.
It backs up previous configuration under
`~/.local/state/nulifyer.project-picker/backups/` and validates Hyprland after
updating the shortcut. Running it again does not duplicate the binding. An
existing global Ctrl+Alt+P binding is explicitly unbound, and the installer
reports its previous action. If your desktop configuration already binds
Ctrl+Alt+P to the picker, the installer leaves your bindings alone.

Omarchy does not execute the included installer automatically. To configure the
shortcut by hand instead, add the following to `~/.config/hypr/bindings.lua`,
unbinding the combination first if it is already in use:

```lua
o.bind("CTRL + ALT + P", "Project picker",
  "omarchy-shell shell toggle nulifyer.project-picker '{}'")
```

After a manual binding edit, run `hyprctl reload` and `hyprctl configerrors`.

## Update

```sh
omarchy plugin update nulifyer.project-picker
```

If the running shell retains the previous QML component, run
`omarchy restart shell` to load the updated code.

## Develop locally

```sh
git clone https://github.com/Nulifyer/omarchy-project-picker ~/Projects/omarchy-project-picker
cd ~/Projects/omarchy-project-picker
python3 install.py
```

The installer copies changed files into the installed plugin directory. It
preserves that directory's Git metadata if it was installed through Omarchy.
When QML or search code changes, it restarts the Omarchy shell to load the
updated files. Runtime dependencies are Python 3 and the Quickshell, Hyprland,
`uwsm-app`, and `xdg-terminal-exec` commands supplied by Omarchy. Testing also
requires Node.js. CI tests Python 3.10 and 3.14 with Node.js 24.

## Use

- Ctrl+Alt+P opens or closes the picker.
- Type to match project names or paths. Separate terms can match different
  parts of the path. Matching favors exact names, prefixes, word boundaries,
  and consecutive characters. This is a path-aware fuzzy matcher, not an
  exact implementation of fzf's scoring or query operators.
- Up/Down or Ctrl+P/Ctrl+N selects a project. Page Up/Down moves seven results.
- Enter opens the selected project in the editor. Clicking a result does the same.
- Ctrl+E opens a terminal in the selected project.
- Ctrl+R refreshes the list. Escape or clicking outside closes the picker.
- **New project** is the last row: Up from the first result reaches it, and
  it is the only row when nothing matches. Enter on it, or Ctrl+Shift+N from
  anywhere, asks for a name (the search text, if any). Enter then creates the
  folder in the projects root (`~/Projects`; created if missing) and opens it
  in the editor. Escape goes back to the list. The name must be one folder
  name, not `.`, `..` or a path, and the folder must not exist yet.

Every direct child directory of `~/Projects` appears first when there is no
search query, including hidden directories and symlinked projects. The home
scan finds outermost folders with `.git`, `.jj`, `.hg`, `.svn`, `.vscode`,
`.idea`, or `.devcontainer` entries. A `.git` file also qualifies, except a
linked worktree's, whose `.git` file points into another repository's
`.git/worktrees/`; secondary jj workspaces are skipped the same way, so the
copies that `git worktree add` and coding agents create don't crowd the list.
It skips dependency, cache, application-state (including `~/.t3`), and build
folders, does not descend into
detected projects, and does not follow directory symlinks during the home scan.
Canonical paths are deduplicated while preserving the first alias.

Discovery runs outside the UI process. Results stream in, remain in memory
between openings, and refresh on each opening. A failed scan restores the
previous results. The picker shows the focused monitor and follows the active
Omarchy menu theme. Paths are displayed as plain text and passed to launchers
as separate arguments, without shell evaluation. Launching checks that the
directory still exists. Application startup after handing off to `uwsm-app`
is managed by the desktop session.

## Theme integration

The picker uses the same `[menu]` surface roles as Omarchy's menu, clipboard,
and emoji plugins. Background, text, scrim, selected-row colors, and border
specifications come from `qs.Commons.Color` and `Border`. The plugin reads
colors as `Commons.Color` (imported `as Commons`): a bare `Color` resolves to
Qt Quick's own `Color` type, which has none of the shell's roles. On karchy,
secondary text and errors use its derived `secondaryText` and `status.error`
roles. Selected rows support
the menu's border widths, gradients, and per-side overrides. Secondary text
uses the menu foreground with reduced opacity, matching the built-in menu.

The search field is Omarchy's shared `qs.Ui.TextField`, so focus borders,
text selection, padding, and control fills follow the shell's `[style]`
settings. Fonts use `Style.font.menuFamily` and the shared size tokens. Input,
header, and row heights grow with their text. Theme changes update the bound
colors and geometry without restarting the plugin.

## Configure

Edit the plugin's entry inside the existing `plugins` array in
`~/.config/omarchy/shell.json` (`~/.config/karchy/shell.json` on karchy). Preserve the surrounding configuration:

```json
{
  "id": "nulifyer.project-picker",
  "projectsRoot": "~/Projects",
  "editor": ["code"]
}
```

`projectsRoot` is also where New project creates folders. It defaults to the shell process's `Z_PROJECTS_ROOT` environment
variable, or `~/Projects`. `editor` is an argument array, so
`["code", "--new-window"]` is valid. Use a graphical editor command or an
explicit terminal wrapper for a terminal editor. Settings reload on save.

Inspect discovery without opening the UI:

```sh
python3 projects.py scan --home "$HOME" --root "$HOME/Projects"
omarchy-shell shell call nulifyer.project-picker status '{}'
```

The summon payload accepts an optional `query` string for opening a filtered
picker from another command. For example:

```sh
omarchy-shell shell summon nulifyer.project-picker '{"query":"dotfiles"}'
```

## Validate

```sh
omarchy plugin validate .
python3 -m unittest discover -s tests -p 'test_*.py'
node tests/search.test.cjs
```

Node is needed only for the search tests. Automated tests cover discovery,
symlinks, path transport, launch arguments, missing editors, and fuzzy ranking.
Popup focus, keyboard navigation, editor launch, terminal working directory,
repeated toggles, and theme changes require an Omarchy desktop. Source changes
in the installed plugin directory trigger Omarchy's plugin watcher. If the shell
retains a previous QML component, run `omarchy restart shell` after updating files
by hand.

## Remove

Run `omarchy plugin disable nulifyer.project-picker`, remove the block between
`-- BEGIN nulifyer.project-picker` and `-- END nulifyer.project-picker` from
`~/.config/hypr/bindings.lua`, then remove the installed plugin folder when
you no longer need it. Run `hyprctl reload` and `hyprctl configerrors` after
editing bindings.

## License

MIT. See [LICENSE](LICENSE).
