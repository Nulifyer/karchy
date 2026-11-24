#!/bin/bash
# karchy-agent-skills against a made-up home and skills folder: the folder
# links it makes for agents, bringing a real agent folder into
# ~/.agents/skills (karchy's old links, the user's skills, Claude's synced/
# and .trash/, a clash, an identical copy, another filesystem, an
# interrupted run) and the way back (keep, share), what it leaves alone (the
# user's own skills and links, Codex, Hermes, agents that aren't installed),
# what it removes (only its own per-skill links), the git ignore in a
# ~/.agents repository, and that a second run changes nothing. Also that
# every skill in skills/ is installed by exactly one package. Never run the
# command against a real home.
# Usage: tests/agent-skills.sh [repo root]
set -uo pipefail
root=$(realpath "${1:-.}")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
pass=0 failures=0
check() { if [[ $2 == "$3" ]]; then pass=$((pass + 1)); else failures=$((failures + 1)); echo "FAIL: $1: got [$2] want [$3]"; fi; }

export KARCHY_AGENT_SKILLS_DIR=$tmp/share/skills
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
unset XDG_STATE_HOME
export LC_ALL=C # the order of names in the messages and listings
src=$KARCHY_AGENT_SKILLS_DIR
# The folder as a person types it, with a literal ~ for the command to expand.
# shellcheck disable=SC2088
claude_typed='~/.claude/skills'

# A new home and the packaged skills: two always on, one that needs a command.
new_home() {
  rm -rf "${tmp:?}/home" "${tmp:?}/share" "${tmp:?}/bin"
  mkdir -p "$tmp/home" "$tmp/bin" "$src/karchy" "$src/karchy-troubleshoot" "$src/karchy-vms"
  echo "name: karchy" >"$src/karchy/SKILL.md"
  echo "name: karchy-troubleshoot" >"$src/karchy-troubleshoot/SKILL.md"
  echo "name: karchy-vms" >"$src/karchy-vms/SKILL.md"
  echo "fake-qemu" >"$src/karchy-vms/.requires"
  export HOME=$tmp/home
}
linker() { PATH="$tmp/bin:$PATH" "$root/bin/karchy-agent-skills" "$@" 2>&1; }
# Every file, folder and link under the home, with link targets: a run that
# changes nothing leaves this the same.
tree() {
  (cd "$HOME" && find . -mindepth 1 -not -path './.agents/.git/*' -printf '%p %y %l\n' | sort &&
    cat .agents/.gitignore .agents/.git/info/exclude 2>/dev/null)
}
git_quiet() { git -c init.defaultBranch=main -c user.name=t -c user.email=t@example.invalid "$@" >/dev/null 2>&1; }

# ---- a new home: no ~/.agents, no ~/.claude
new_home
out=$(linker)
check "new home: karchy linked" "$(readlink "$HOME/.agents/skills/karchy")" "$src/karchy"
check "new home: troubleshoot linked" "$(readlink "$HOME/.agents/skills/karchy-troubleshoot")" "$src/karchy-troubleshoot"
check "new home: skill needing a missing command is not linked" "$([[ -e $HOME/.agents/skills/karchy-vms ]] && echo there || echo absent)" "absent"
check "new home: ~/.claude/skills is a link to ~/.agents/skills" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "new home: Claude sees the skill" "$(cat "$HOME/.claude/skills/karchy/SKILL.md")" "name: karchy"
check "new home: says what it linked" "$(grep -c '^linked ' <<<"$out")" "3"
check "new home: no folder made for agents that are not installed" "$(ls -A "$HOME" | sort | tr '\n' ' ')" ".agents .claude "
before=$(tree)
check "second run prints nothing" "$(linker)" ""
check "second run changes nothing" "$(tree)" "$before"

# ---- the needed command appears, then goes
printf '#!/bin/bash\n' >"$tmp/bin/fake-qemu"
chmod +x "$tmp/bin/fake-qemu"
check "requirement met: linked" "$(linker)" "linked ~/.agents/skills/karchy-vms"
rm "$tmp/bin/fake-qemu"
check "requirement gone: link removed" "$(linker)" "removed ~/.agents/skills/karchy-vms"

# ---- a package is removed: its link goes, nothing else
mkdir -p "$HOME/.agents/skills/mine"
echo mine >"$HOME/.agents/skills/mine/SKILL.md"
ln -s /nonexistent/elsewhere "$HOME/.agents/skills/broken-but-mine"
rm -rf "$src/karchy-troubleshoot"
check "package removed: its link is removed" "$(linker)" "removed ~/.agents/skills/karchy-troubleshoot"
check "package removed: the user's skill stays" "$(cat "$HOME/.agents/skills/mine/SKILL.md")" "mine"
check "package removed: the user's broken link stays" "$(readlink "$HOME/.agents/skills/broken-but-mine")" "/nonexistent/elsewhere"
check "package removed: the other skill stays" "$(readlink "$HOME/.agents/skills/karchy")" "$src/karchy"

# ---- the user's own skill with a karchy name: a real folder, and a link elsewhere
new_home
mkdir -p "$HOME/.agents/skills/karchy" "$tmp/home/elsewhere"
echo "the user's" >"$HOME/.agents/skills/karchy/SKILL.md"
ln -s "$tmp/home/elsewhere" "$HOME/.agents/skills/karchy-troubleshoot"
out=$(linker)
check "same name, folder: kept" "$(cat "$HOME/.agents/skills/karchy/SKILL.md")" "the user's"
check "same name, link elsewhere: kept" "$(readlink "$HOME/.agents/skills/karchy-troubleshoot")" "$tmp/home/elsewhere"
check "same name: says so" "$(grep -c '^kept .*your own skill' <<<"$out")" "2"

# ---- ~/.claude/skills already a link: to ~/.agents/skills, and to somewhere else
new_home
mkdir -p "$HOME/.claude" "$HOME/.agents/skills"
ln -s "$HOME/.agents/skills" "$HOME/.claude/skills"
linker >/dev/null
check "claude link to the main folder: unchanged" "$(readlink "$HOME/.claude/skills")" "$HOME/.agents/skills"
new_home
mkdir -p "$HOME/.claude" "$HOME/dotfiles/skills"
ln -s "$HOME/dotfiles/skills" "$HOME/.claude/skills"
out=$(linker)
check "claude link elsewhere: says so" "$(head -n 1 <<<"$out")" "left ~/.claude/skills as it is: it is a link to $HOME/dotfiles/skills, your own arrangement."
check "claude link elsewhere: said once" "$(linker)" ""
check "claude link elsewhere: unchanged" "$(readlink "$HOME/.claude/skills")" "$HOME/dotfiles/skills"
check "claude link elsewhere: nothing written through it" "$(ls -A "$HOME/dotfiles/skills")" ""

# ---- starting point: karchy's old one-by-one links in a real ~/.claude/skills
new_home
mkdir -p "$HOME/.claude/skills"
ln -s "$src/karchy" "$HOME/.claude/skills/karchy"
ln -s "$src/karchy-troubleshoot" "$HOME/.claude/skills/karchy-troubleshoot"
out=$(linker)
check "old links: the folder is now the link" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "old links: says it brought the folder in" "$(head -n 1 <<<"$out")" "brought ~/.claude/skills into ~/.agents/skills; ~/.claude/skills is now a link to it."
check "old links: names karchy's removed links" "$(grep -c "^  karchy's old links removed: karchy karchy-troubleshoot$" <<<"$out")" "1"
check "old links: nothing recorded to give back" "$(cat "$HOME/.local/state/karchy/agent-skills-moved" 2>/dev/null)" ""
check "old links: Claude sees karchy's skill" "$(cat "$HOME/.claude/skills/karchy/SKILL.md")" "name: karchy"
before=$(tree)
check "old links: second run prints nothing" "$(linker)" ""
check "old links: second run changes nothing" "$(tree)" "$before"

# ---- starting point: a real folder with the user's own skills, Claude's
# synced/ and .trash/, links into ~/.agents/skills, and ~/.agents a git
# repository (the user's own machine)
new_home
mkdir -p "$HOME/.agents/skills/caveman" "$HOME/.claude/skills/only-here" "$HOME/.claude/skills/synced/acct" "$HOME/.claude/skills/.trash/old"
echo caveman >"$HOME/.agents/skills/caveman/SKILL.md"
printf 'node_modules\n' >"$HOME/.agents/.gitignore"
git_quiet -C "$HOME/.agents" init
git_quiet -C "$HOME/.agents" add -A
git_quiet -C "$HOME/.agents" commit -m first
head_before=$(git -C "$HOME/.agents" rev-parse HEAD)
echo only >"$HOME/.claude/skills/only-here/SKILL.md"
echo account >"$HOME/.claude/skills/synced/acct/SKILL.md"
echo gone >"$HOME/.claude/skills/.trash/old/SKILL.md"
ln -s "$HOME/.agents/skills/caveman" "$HOME/.claude/skills/caveman"   # absolute, as the user's machine has
ln -s "$src/karchy" "$HOME/.claude/skills/karchy"                     # karchy's old link
mkdir -p "$HOME/work/skill-x"
echo x >"$HOME/work/skill-x/SKILL.md"
(cd "$HOME/.claude/skills" && ln -s ../../work/skill-x skill-x)       # a relative link elsewhere
out=$(linker)
check "user's folder: the folder is now the link" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "user's folder: what moved" "$(grep '^  moved: ' <<<"$out")" "  moved: .trash only-here skill-x synced"
check "user's folder: already there" "$(grep '^  already there' <<<"$out")" "  already there, so removed from ~/.claude/skills: caveman"
check "user's folder: a skill only there moved" "$(cat "$HOME/.agents/skills/only-here/SKILL.md")" "only"
check "user's folder: synced/ moved" "$(cat "$HOME/.agents/skills/synced/acct/SKILL.md")" "account"
check "user's folder: .trash/ moved" "$(cat "$HOME/.agents/skills/.trash/old/SKILL.md")" "gone"
check "user's folder: a relative link still reaches its skill" "$(cat "$HOME/.agents/skills/skill-x/SKILL.md")" "x"
check "user's folder: the relative link is now absolute" "$(readlink "$HOME/.agents/skills/skill-x")" "$HOME/work/skill-x"
check "user's folder: the user's skill in the main folder untouched" "$(cat "$HOME/.agents/skills/caveman/SKILL.md")" "caveman"
check "user's folder: Claude sees everything" "$(ls -A "$HOME/.claude/skills/" | tr '\n' ' ')" ".trash caveman karchy karchy-troubleshoot only-here skill-x synced "
check "user's folder: says the repository has new files" "$(grep -c '^  ~/.agents is a git repository: what moved is new there' <<<"$out")" "1"
check "user's folder: says how to undo" "$(grep '^  to undo' <<<"$out")" "  to undo: karchy agent skills keep ~/.claude/skills"
check "user's folder: nothing committed" "$(git -C "$HOME/.agents" rev-parse HEAD)" "$head_before"
check "user's folder: nothing staged" "$(git -C "$HOME/.agents" diff --cached --name-only)" ""
check "user's folder: git sees the moved files as new" "$(git -C "$HOME/.agents" status --porcelain | tr '\n' ' ')" " M .gitignore ?? skills/.trash/ ?? skills/only-here/ ?? skills/skill-x ?? skills/synced/ "
before=$(tree)
check "user's folder: second run prints nothing" "$(linker)" ""
check "user's folder: second run changes nothing" "$(tree)" "$before"
check "user's folder: status" "$(linker status | head -n 1)" "shared   ~/.claude/skills -> ~/.agents/skills"

# ...and the way back: keep gives the folder back as it was
out=$(linker keep "$claude_typed")
check "keep: a real folder again" "$([[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] && echo folder)" "folder"
check "keep: says what moved back" "$(grep '^  moved back' <<<"$out")" "  moved back: .trash only-here skill-x synced"
check "keep: says what was put back as before" "$(grep '^  copied back' <<<"$out")" "  copied back (still in ~/.agents/skills too): caveman"
check "keep: its skill is back" "$(cat "$HOME/.claude/skills/only-here/SKILL.md")" "only"
check "keep: synced/ is back" "$(cat "$HOME/.claude/skills/synced/acct/SKILL.md")" "account"
check "keep: the link into the main folder is a link again" "$(readlink "$HOME/.claude/skills/caveman")" "$HOME/.agents/skills/caveman"
check "keep: the main folder keeps its own" "$(cat "$HOME/.agents/skills/caveman/SKILL.md")" "caveman"
check "keep: gone from the main folder" "$(ls -A "$HOME/.agents/skills" | tr '\n' ' ')" "caveman karchy karchy-troubleshoot "
check "keep: karchy's skills linked into it" "$(readlink "$HOME/.claude/skills/karchy")" "$src/karchy"
check "keep: status" "$(linker status | head -n 1)" "kept     ~/.claude/skills (a folder of its own, as asked; share it with: karchy agent skills share ~/.claude/skills)"
check "keep: the record is cleared" "$([[ -e $HOME/.local/state/karchy/agent-skills-moved ]] && echo there || echo gone)" "gone"
before=$(tree)
check "keep: a run leaves it a folder" "$(linker)" ""
check "keep: a run changes nothing" "$(tree)" "$before"
linker keep "$HOME/.claude/skills" >/dev/null
check "keep: again changes nothing" "$(tree)" "$before"
out=$(linker share "$claude_typed")
check "share: brought in again" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "share: everything in the main folder" "$(ls -A "$HOME/.agents/skills" | tr '\n' ' ')" ".trash caveman karchy karchy-troubleshoot only-here skill-x synced "

# ---- a name clash: both kept, neither overwritten
new_home
mkdir -p "$HOME/.claude/skills/clash" "$HOME/.claude/skills/fine" "$HOME/.agents/skills/clash" "$HOME/.agents/skill-clashes/claude/clash"
echo theirs >"$HOME/.claude/skills/clash/SKILL.md"
echo fine >"$HOME/.claude/skills/fine/SKILL.md"
echo other >"$HOME/.agents/skills/clash/SKILL.md"
echo earlier >"$HOME/.agents/skill-clashes/claude/clash/SKILL.md"   # an earlier clash of the same name
mkdir -p "$HOME/.claude/skills/same"
echo same >"$HOME/.claude/skills/same/SKILL.md"
cp -r "$HOME/.claude/skills/same" "$HOME/.agents/skills/same"          # an identical copy
out=$(linker)
check "clash: the folder is the link" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "clash: the main folder's one stays" "$(cat "$HOME/.agents/skills/clash/SKILL.md")" "other"
check "clash: the folder's one is kept beside it" "$(cat "$HOME/.agents/skill-clashes/claude/clash.2/SKILL.md")" "theirs"
check "clash: the earlier clash untouched" "$(cat "$HOME/.agents/skill-clashes/claude/clash/SKILL.md")" "earlier"
check "clash: says so" "$(grep -c '^  kept both of clash: ~/.agents/skills/clash stays, and the one from ~/.claude/skills is now ~/.agents/skill-clashes/claude/clash.2' <<<"$out")" "1"
check "clash: the other skill moved" "$(cat "$HOME/.agents/skills/fine/SKILL.md")" "fine"
check "clash: identical copy removed from the folder" "$(grep '^  already there' <<<"$out")" "  already there, so removed from ~/.claude/skills: same"
check "clash: identical copy kept in the main folder" "$(cat "$HOME/.agents/skills/same/SKILL.md")" "same"
linker keep "$claude_typed" >/dev/null
check "clash, keep: the folder's one back" "$(cat "$HOME/.claude/skills/clash/SKILL.md")" "theirs"
check "clash, keep: the identical copy back" "$(cat "$HOME/.claude/skills/same/SKILL.md")" "same"
check "clash, keep: the main folder's one untouched" "$(cat "$HOME/.agents/skills/clash/SKILL.md")" "other"

# ---- a skill of the user's named like karchy's wins over karchy's link
new_home
mkdir -p "$HOME/.claude/skills/karchy"
echo "the user's" >"$HOME/.claude/skills/karchy/SKILL.md"
linker --no-move >/dev/null # karchy's link in ~/.agents/skills is made first
linker >/dev/null
check "user's karchy: moved over karchy's link" "$(cat "$HOME/.agents/skills/karchy/SKILL.md")" "the user's"
check "user's karchy: folder is the link" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"

# ---- an empty real folder is replaced by the link, even with --no-move
new_home
mkdir -p "$HOME/.claude/skills"
check "empty folder: linked" "$(linker --no-move | head -n 1)" "linked ~/.claude/skills -> ~/.agents/skills"
check "empty folder: is the link" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"

# ---- --no-move (the session's run): a folder with content waits for an update
new_home
mkdir -p "$HOME/.claude/skills/mine"
echo mine >"$HOME/.claude/skills/mine/SKILL.md"
out=$(linker --no-move)
check "no-move: stays a folder" "$([[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] && echo folder)" "folder"
check "no-move: says it waits" "$(grep -c '^~/.claude/skills holds files of its own; karchy update brings them into ~/.agents/skills' <<<"$out")" "1"
check "no-move: karchy's skills linked into it meanwhile" "$(readlink "$HOME/.claude/skills/karchy")" "$src/karchy"
check "no-move: the user's skill untouched" "$(cat "$HOME/.claude/skills/mine/SKILL.md")" "mine"
check "no-move: status" "$(linker status | head -n 1)" "folder   ~/.claude/skills (not brought in yet: karchy agent skills)"
out=$(linker)
check "no-move, then a plain run: brought in" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "no-move, then a plain run: the skill moved" "$(cat "$HOME/.agents/skills/mine/SKILL.md")" "mine"
check "no-move, then a plain run: karchy's links dropped" "$(grep "^  karchy's old links removed" <<<"$out")" "  karchy's old links removed: karchy karchy-troubleshoot"

# ---- another filesystem: the folder, or one entry in it, is left as it is
fake_device() { # stat reporting another device for paths matching $1
  cat >"$tmp/bin/stat" <<STAT
#!/bin/bash
for a in "\$@"; do [[ \$a == $1 ]] && { echo 4242; exit 0; }; done
exec /usr/bin/stat "\$@"
STAT
  chmod +x "$tmp/bin/stat"
}
new_home
mkdir -p "$HOME/.claude/skills/mine"
echo mine >"$HOME/.claude/skills/mine/SKILL.md"
fake_device '*/.claude/skills'
out=$(linker)
check "other filesystem: says why it is left" "$(grep -c '^left ~/.claude/skills as it is: mine would have to cross to another filesystem' <<<"$out")" "1"
check "other filesystem: still a folder" "$([[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] && echo folder)" "folder"
check "other filesystem: the skill untouched" "$(cat "$HOME/.claude/skills/mine/SKILL.md")" "mine"
check "other filesystem: karchy's skills linked into it" "$(readlink "$HOME/.claude/skills/karchy")" "$src/karchy"
check "other filesystem: said once" "$(linker)" ""
new_home
mkdir -p "$HOME/.claude/skills/mine" "$HOME/.claude/skills/mounted"
echo mine >"$HOME/.claude/skills/mine/SKILL.md"
fake_device '*/.claude/skills/mounted'
linker >/dev/null
check "an entry on another filesystem: nothing moved" "$(ls -A "$HOME/.claude/skills" | tr '\n' ' ')" "karchy karchy-troubleshoot mine mounted "
check "an entry on another filesystem: main folder has none of it" "$(ls -A "$HOME/.agents/skills" | tr '\n' ' ')" "karchy karchy-troubleshoot "
rm -f "$tmp/bin/stat"
# The guarantee the moves rest on: mv --no-copy refuses to cross filesystems.
if mv --help | grep -q -- --no-copy && [[ -d /dev/shm && $(stat -c %d /dev/shm) != "$(stat -c %d "$tmp")" ]]; then
  mkdir -p "$tmp/cross"
  echo x >"$tmp/cross/f"
  mv --no-copy -nT -- "$tmp/cross/f" "/dev/shm/karchy-agent-skills-test.$$" 2>/dev/null
  check "mv --no-copy across filesystems: refused" "$([[ -e $tmp/cross/f && ! -e /dev/shm/karchy-agent-skills-test.$$ ]] && echo refused)" "refused"
  rm -f "/dev/shm/karchy-agent-skills-test.$$"
fi

# ---- an interrupted run: killed after its first move, the next run finishes
new_home
mkdir -p "$HOME/.claude/skills/a" "$HOME/.claude/skills/b" "$HOME/.claude/skills/c"
for n in a b c; do echo "$n" >"$HOME/.claude/skills/$n/SKILL.md"; done
(cd "$HOME/.claude/skills" && ln -s ../../work d)
cat >"$tmp/bin/mv" <<'MV'
#!/bin/bash
/usr/bin/mv "$@" || exit
kill -9 "$PPID"
MV
chmod +x "$tmp/bin/mv"
(linker >/dev/null) 2>/dev/null # the shell's "Killed"
rm -f "$tmp/bin/mv"
check "interrupted: stopped part way" "$([[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] && echo folder)" "folder"
check "interrupted: every skill in one place or the other" \
  "$(for n in a b c; do cat "$HOME/.claude/skills/$n/SKILL.md" 2>/dev/null || cat "$HOME/.agents/skills/$n/SKILL.md"; done | tr '\n' ' ')" "a b c "
out=$(linker)
check "interrupted: the next run finishes" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "interrupted: all moved" "$(ls -A "$HOME/.agents/skills" | tr '\n' ' ')" "a b c d karchy karchy-troubleshoot "
check "interrupted: the link still points where it did" "$(readlink "$HOME/.agents/skills/d")" "$HOME/work"
before=$(tree)
check "interrupted: then a run prints nothing" "$(linker)" ""
check "interrupted: then a run changes nothing" "$(tree)" "$before"
linker keep "$claude_typed" >/dev/null
check "interrupted, keep: everything back" "$(ls -A "$HOME/.claude/skills" | tr '\n' ' ')" "a b c d karchy karchy-troubleshoot "
# ...and stopped between removing the folder and making the link
new_home
mkdir -p "$HOME/.claude"
linker >/dev/null
rm "$HOME/.claude/skills"
check "stopped before the link: the next run makes it" "$(linker)" "linked ~/.claude/skills -> ~/.agents/skills"

# ---- every folder agent is brought in, not only Claude Code's
new_home
mkdir -p "$HOME/.kiro/skills/k"
echo k >"$HOME/.kiro/skills/k/SKILL.md"
linker >/dev/null
check "kiro: brought in" "$(readlink "$HOME/.kiro/skills")" "../.agents/skills"
check "kiro: its skill moved" "$(cat "$HOME/.agents/skills/k/SKILL.md")" "k"

# ---- ~/.agents/skills a link to ~/.claude/skills (the other way round): nothing moves
new_home
mkdir -p "$HOME/.claude/skills/mine" "$HOME/.agents"
echo mine >"$HOME/.claude/skills/mine/SKILL.md"
ln -s ../.claude/skills "$HOME/.agents/skills"
linker >/dev/null
check "reverse link: the user's folder stays a folder" "$([[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] && echo folder)" "folder"
check "reverse link: the skill untouched" "$(cat "$HOME/.claude/skills/mine/SKILL.md")" "mine"

# ---- agents that aren't installed get no folder; installed ones get the link
new_home
linker >/dev/null
check "not installed: no folders made" "$(ls -A "$HOME" | sort | tr '\n' ' ')" ".agents .claude "
mkdir -p "$HOME/.gemini" "$HOME/.kiro"   # Gemini CLI alone reads ~/.agents/skills itself
out=$(linker)
check "Gemini CLI without Antigravity: nothing made in ~/.gemini" "$(ls -A "$HOME/.gemini")" ""
check "Kiro installed: its folder is the link" "$(readlink "$HOME/.kiro/skills")" "../.agents/skills"
check "Kiro installed: says so" "$out" "linked ~/.kiro/skills -> ~/.agents/skills"
mkdir -p "$HOME/.gemini/config"
linker >/dev/null
check "Antigravity installed: its folder is the link" "$(readlink "$HOME/.gemini/config/skills")" "../../.agents/skills"
check "Antigravity: sees the skill" "$(cat "$HOME/.gemini/config/skills/karchy/SKILL.md")" "name: karchy"

# ---- Codex reads ~/.agents/skills itself: its folder, with its built-in skills, is left alone
new_home
mkdir -p "$HOME/.codex/skills/.system"
echo builtin >"$HOME/.codex/skills/.system/marker"
linker >/dev/null
check "codex: skills folder untouched" "$(cd "$HOME/.codex" && find . -mindepth 1 -printf '%p %y\n' | sort | tr '\n' ' ')" "./skills d ./skills/.system d ./skills/.system/marker f "
new_home
mkdir -p "$HOME/.codex"
linker >/dev/null
check "codex without a skills folder: none made" "$(ls -A "$HOME/.codex")" ""

# ---- Hermes keeps its own files in its skills folder: per-skill links, never the folder link
new_home
mkdir -p "$HOME/.hermes/profiles/coder"
linker >/dev/null
check "hermes: a real folder" "$([[ -d $HOME/.hermes/skills && ! -L $HOME/.hermes/skills ]] && echo folder)" "folder"
check "hermes: skill linked" "$(readlink "$HOME/.hermes/skills/karchy")" "$src/karchy"
check "hermes profile: skill linked" "$(readlink "$HOME/.hermes/profiles/coder/skills/karchy")" "$src/karchy"
echo bundled >"$HOME/.hermes/skills/.bundled_manifest"
linker >/dev/null
check "hermes: never brought in" "$(cat "$HOME/.hermes/skills/.bundled_manifest")" "bundled"
rm -rf "$src/karchy-troubleshoot"
linker >/dev/null
check "hermes: stale link removed" "$([[ -L $HOME/.hermes/skills/karchy-troubleshoot ]] && echo there || echo gone)" "gone"

# ---- ~/.agents is a git repository with a .gitignore
new_home
mkdir -p "$HOME/.agents/skills/mine"
echo mine >"$HOME/.agents/skills/mine/SKILL.md"
printf 'node_modules' >"$HOME/.agents/.gitignore" # no newline at the end
git_quiet -C "$HOME/.agents" init
git_quiet -C "$HOME/.agents" add -A
git_quiet -C "$HOME/.agents" commit -m first
out=$(linker)
check "repo with .gitignore: line added after the user's" "$(cat "$HOME/.agents/.gitignore")" \
  $'node_modules\n# karchy\'s agent skills: links into /usr/share/karchy (karchy-agent-skills)\nskills/karchy*'
check "repo with .gitignore: says so" "$(grep -c "^ignored karchy's skills in ~/.agents/.gitignore" <<<"$out")" "1"
check "repo with .gitignore: only .gitignore shows as changed" "$(git -C "$HOME/.agents" status --porcelain)" " M .gitignore"
check "repo with .gitignore: nothing committed" "$(git -C "$HOME/.agents" rev-list --count HEAD)" "1"
before=$(tree)
check "repo with .gitignore: second run prints nothing" "$(linker)" ""
check "repo with .gitignore: second run changes nothing" "$(tree)" "$before"
# The user takes the line out again: it is not put back.
git_quiet -C "$HOME/.agents" checkout .gitignore
linker >/dev/null
check "repo with .gitignore: added once only" "$(cat "$HOME/.agents/.gitignore")" "node_modules"

# ...one that already ignores them
new_home
mkdir -p "$HOME/.agents"
printf 'skills/karchy*\n' >"$HOME/.agents/.gitignore"
git_quiet -C "$HOME/.agents" init
linker >/dev/null
check "repo already ignoring: untouched" "$(cat "$HOME/.agents/.gitignore")" "skills/karchy*"

# ---- a git repository without a .gitignore: .git/info/exclude, no tracked file
new_home
mkdir -p "$HOME/.agents"
git_quiet -C "$HOME/.agents" init
linker >/dev/null
check "repo without .gitignore: none made" "$([[ -e $HOME/.agents/.gitignore ]] && echo made || echo none)" "none"
check "repo without .gitignore: excluded" "$(grep -cxF 'skills/karchy*' "$HOME/.agents/.git/info/exclude")" "1"
check "repo without .gitignore: git sees nothing new" "$(git -C "$HOME/.agents" status --porcelain)" ""
linker >/dev/null
check "repo without .gitignore: excluded once" "$(grep -cxF 'skills/karchy*' "$HOME/.agents/.git/info/exclude")" "1"

# ---- a new machine: karchy linked first, then the user brings their repository
new_home
mkdir -p "$tmp/origin-work/skills/mine"
echo mine >"$tmp/origin-work/skills/mine/SKILL.md"
echo '*.log' >"$tmp/origin-work/.gitignore"
git_quiet -C "$tmp/origin-work" init
git_quiet -C "$tmp/origin-work" add -A
git_quiet -C "$tmp/origin-work" commit -m first
linker >/dev/null
git_quiet -C "$HOME/.agents" init
git_quiet -C "$HOME/.agents" remote add origin "$tmp/origin-work"
git_quiet -C "$HOME/.agents" fetch origin
git_quiet -C "$HOME/.agents" checkout -t origin/main
check "repo brought in later: checkout works" "$(cat "$HOME/.agents/skills/mine/SKILL.md" 2>/dev/null)" "mine"
check "repo brought in later: karchy's link survives" "$(readlink "$HOME/.agents/skills/karchy")" "$src/karchy"
linker >/dev/null
check "repo brought in later: then ignored" "$(git -C "$HOME/.agents" status --porcelain)" " M .gitignore"
check "repo brought in later: Claude sees both" "$(ls "$HOME/.claude/skills/" | tr '\n' ' ')" "karchy karchy-troubleshoot mine "
rm -rf "$tmp/origin-work"

# ---- status and usage
new_home
linker >/dev/null
check "status" "$(linker status)" $'shared   ~/.claude/skills -> ~/.agents/skills\nlinked   ~/.agents/skills/karchy\nlinked   ~/.agents/skills/karchy-troubleshoot\nnot installed here  karchy-vms (needs: fake-qemu)'
check "usage" "$(linker bogus >/dev/null; echo $?)" "2"
check "usage: --adopt is gone" "$(linker --adopt >/dev/null 2>&1; echo $?)" "2"
check "usage: keep needs a folder" "$(linker keep >/dev/null 2>&1; echo $?)" "2"
check "usage: keep takes only an agent's skills folder" "$(linker keep "$HOME/.codex/skills" >/dev/null 2>&1; echo $?)" "2"
check "usage: keep says which folders" "$(linker keep /tmp 2>&1)" "karchy-agent-skills keep: name one of: ~/.claude/skills ~/.gemini/config/skills ~/.kiro/skills"

# ---- packaging: each skill in skills/ has a SKILL.md named after its folder
# and is installed by exactly one PKGBUILD
for dir in "$root"/skills/*/; do
  name=${dir%/} name=${name##*/}
  check "skills/$name: SKILL.md name" "$(sed -n 's/^name: *//p' "$dir/SKILL.md" 2>/dev/null | head -n 1)" "$name"
  check "skills/$name: installed by one package" \
    "$(grep -lE "skills/$name( |\"|$)" "$root"/packaging/pkgbuilds/*/PKGBUILD 2>/dev/null | wc -l)" "1"
done

echo "agent-skills: $pass passed, $failures failed"
((failures == 0))
