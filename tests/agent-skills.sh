#!/bin/bash
# karchy-agent-skills against a made-up home and skills folder: the folder
# links it makes for agents, what it leaves alone (the user's own skills and
# folders, Codex, agents that aren't installed), what it removes (only its
# own per-skill links), --adopt, the git ignore in a ~/.agents repository,
# and that a second run changes nothing. Also that
# every skill in skills/ is installed by exactly one package.
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
src=$KARCHY_AGENT_SKILLS_DIR

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

# ---- ~/.claude/skills as a real folder with the user's links in it
new_home
mkdir -p "$HOME/.claude/skills" "$HOME/.agents/skills/mine"
ln -s ../../.agents/skills/mine "$HOME/.claude/skills/mine"
echo synced >"$HOME/.claude/skills/synced"
out=$(linker)
check "claude folder: says how to share it, once" "$(grep -c 'karchy agent skills --adopt$' <<<"$out")" "1"
check "claude folder: stays a folder" "$([[ -d $HOME/.claude/skills && ! -L $HOME/.claude/skills ]] && echo folder)" "folder"
check "claude folder: status says how to share it" "$(linker status | head -n 1)" "folder   ~/.claude/skills (its own folder; share it with: karchy agent skills --adopt)"
check "claude folder: karchy skill linked into it" "$(readlink "$HOME/.claude/skills/karchy")" "$src/karchy"
check "claude folder: the user's link untouched" "$(readlink "$HOME/.claude/skills/mine")" "../../.agents/skills/mine"
check "claude folder: the user's file untouched" "$(cat "$HOME/.claude/skills/synced")" "synced"
before=$(tree)
check "claude folder: second run prints nothing" "$(linker)" ""
check "claude folder: second run changes nothing" "$(tree)" "$before"
rm -rf "$src/karchy-troubleshoot"
linker >/dev/null
check "claude folder: stale link removed there too" "$([[ -L $HOME/.claude/skills/karchy-troubleshoot ]] && echo there || echo gone)" "gone"

# ---- ~/.claude/skills already a link: to ~/.agents/skills, and to somewhere else
new_home
mkdir -p "$HOME/.claude" "$HOME/.agents/skills"
ln -s "$HOME/.agents/skills" "$HOME/.claude/skills"
linker >/dev/null
check "claude link to the main folder: unchanged" "$(readlink "$HOME/.claude/skills")" "$HOME/.agents/skills"
new_home
mkdir -p "$HOME/.claude" "$HOME/dotfiles/skills"
ln -s "$HOME/dotfiles/skills" "$HOME/.claude/skills"
linker >/dev/null
check "claude link elsewhere: unchanged" "$(readlink "$HOME/.claude/skills")" "$HOME/dotfiles/skills"
check "claude link elsewhere: nothing written through it" "$(ls -A "$HOME/dotfiles/skills")" ""

# ---- --adopt: the folder's contents move to ~/.agents/skills, then it is the link
new_home
mkdir -p "$HOME/.claude/skills/only-here" "$HOME/.claude/skills/synced" "$HOME/.agents/skills/mine" "$HOME/.agents/skills/same"
echo only >"$HOME/.claude/skills/only-here/SKILL.md"
echo account >"$HOME/.claude/skills/synced/list"
echo hidden >"$HOME/.claude/skills/.hidden"
echo mine >"$HOME/.agents/skills/mine/SKILL.md"
echo same >"$HOME/.agents/skills/same/SKILL.md"
cp -r "$HOME/.agents/skills/same" "$HOME/.claude/skills/same"          # an identical copy
ln -s ../../.agents/skills/mine "$HOME/.claude/skills/mine"            # a link into the main folder
mkdir -p "$HOME/work/skill-x"
echo x >"$HOME/work/skill-x/SKILL.md"
(cd "$HOME/.claude/skills" && ln -s ../../work/skill-x skill-x)        # a relative link elsewhere
linker >/dev/null
out=$(linker --adopt)
check "adopt: exit status" "$?" "0"
check "adopt: the folder is now the link" "$(readlink "$HOME/.claude/skills")" "../.agents/skills"
check "adopt: a skill only there moved" "$(cat "$HOME/.agents/skills/only-here/SKILL.md")" "only"
check "adopt: a folder that is not a skill moved" "$(cat "$HOME/.agents/skills/synced/list")" "account"
check "adopt: a hidden file moved" "$(cat "$HOME/.agents/skills/.hidden")" "hidden"
check "adopt: a relative link still reaches its skill" "$(cat "$HOME/.agents/skills/skill-x/SKILL.md")" "x"
check "adopt: the user's skill in the main folder untouched" "$(cat "$HOME/.agents/skills/mine/SKILL.md")" "mine"
check "adopt: karchy's skill still a link" "$(readlink "$HOME/.agents/skills/karchy")" "$src/karchy"
check "adopt: says what moved" "$(grep -c '^moved ' <<<"$out")" "4"
check "adopt: Claude sees everything" "$(ls -A "$HOME/.claude/skills/" | tr '\n' ' ')" ".hidden karchy karchy-troubleshoot mine only-here same skill-x synced "
before=$(tree)
check "adopt: again, nothing to adopt" "$(linker --adopt)" "Nothing to adopt: no agent's skills folder is a folder of its own."
check "adopt: again changes nothing" "$(tree)" "$before"

# ...and with a name taken by something different: nothing moves
new_home
mkdir -p "$HOME/.claude/skills/clash" "$HOME/.claude/skills/fine" "$HOME/.agents/skills/clash"
echo theirs >"$HOME/.claude/skills/clash/SKILL.md"
echo other >"$HOME/.agents/skills/clash/SKILL.md"
linker >/dev/null
before=$(tree)
out=$(linker --adopt)
check "adopt with a clash: fails" "$?" "1"
check "adopt with a clash: names it" "$(grep -c 'something different named clash' <<<"$out")" "1"
check "adopt with a clash: nothing changed" "$(tree)" "$before"

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
linker --adopt >/dev/null
check "hermes: --adopt leaves it a folder" "$(cat "$HOME/.hermes/skills/.bundled_manifest")" "bundled"
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
