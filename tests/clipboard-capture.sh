#!/bin/bash

# The clipboard history's capture (shell/plugins/clipboard/capture.sh, D-167)
# against a stand-in wl-paste: which copies become entries, as what, and which
# are left out. Usage: tests/clipboard-capture.sh
#
# Needs jq and perl, as the script does. No compositor: the stand-in answers
# from files.

set -u

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
capture=$root/shell/plugins/clipboard/capture.sh
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
failures=0

mkdir -p "$t/bin" "$t/run" "$t/clip"

# wl-paste: --list-types prints $CLIP/types; --type <mime> prints the file
# named after the mime ("/" and ";" as "_"), or fails as wl-paste does.
cat >"$t/bin/wl-paste" <<'STUB'
#!/bin/bash
mime=
for arg in "$@"; do
  case "$arg" in
  --list-types) cat "$CLIP/types"; exit ;;
  --no-newline | --type) ;;
  *) mime=$arg ;;
  esac
done
file=$CLIP/$(tr '/;' '__' <<<"$mime")
[[ -r $file ]] || exit 1
[[ -n ${CLIP_STALL:-} ]] && sleep 5
cat "$file"
STUB
printf '#!/bin/bash\necho C\n' >"$t/bin/karchy-language"
chmod +x "$t/bin/wl-paste" "$t/bin/karchy-language"

# offer <mime> <content>...: what the stand-in clipboard holds.
offer() {
  rm -f "$t/clip"/*
  while (($# > 1)); do
    echo "$1" >>"$t/clip/types"
    printf '%b' "$2" >"$t/clip/$(tr '/;' '__' <<<"$1")"
    shift 2
  done
  # wl-paste --type text takes the plain text, whatever its exact name.
  if [[ -r $t/clip/text_plain_charset=utf-8 ]]; then
    cp "$t/clip/text_plain_charset=utf-8" "$t/clip/text"
  elif [[ -r $t/clip/text_plain ]]; then
    cp "$t/clip/text_plain" "$t/clip/text"
  fi
}

run() {
  env PATH="$t/bin:$PATH" XDG_RUNTIME_DIR="$t/run" CLIP="$t/clip" "$@" "$capture" </dev/null
}

is() {
  if [[ $2 == "$3" ]]; then
    echo "ok   $1"
  else
    echo "FAIL $1"
    echo "       got:      $2"
    echo "       expected: $3"
    failures=$((failures + 1))
  fi
}

stored() {
  find "$t/run/karchy/clipboard" -type f ! -name '.*' 2>/dev/null | wc -l
}

# ---- text
offer 'text/plain;charset=utf-8' 'hello world\n' 'text/html' '<b>hello world</b>'
out=$(run env)
is "text: recorded as text" "$(jq -r '.type + " " + .mime + " " + .preview' <<<"$out")" "text text/plain hello world"
is "text: the entry's file holds the text" "$(cat "$(jq -r .path <<<"$out")")" "hello world"
is "text: the id is the type and the content's hash" "$(jq -r .id <<<"$out")" "text:$(printf 'hello world\n' | sha256sum | cut -c1-32)"
is "text: the size is the file's" "$(jq -r .size <<<"$out")" "12"
is "text: the file is private" "$(stat -c %a "$(jq -r .path <<<"$out")")" "600"
is "text: so is the folder" "$(stat -c %a "$t/run/karchy/clipboard")" "700"
again=$(run env)
is "text: the same copy again is the same entry and file" "$(jq -r .id <<<"$again") $(stored)" "$(jq -r .id <<<"$out") 1"

offer 'text/plain' '  \n\t\n'
is "text: a blank copy is not recorded" "$(run env)$(stored)" "1"

offer "text/plain;charset=utf-8" "$(printf 'h\\0i\\0!\\0\\n\\0')"
out=$(run env)
is "text: UTF-16 without a mark is kept as UTF-8" "$(jq -r .preview <<<"$out")" "hi!"

long=$(head -c 20000 /dev/zero | tr '\0' 'x')
offer "text/plain" "$long"
out=$(run env)
is "text: the preview is the start, the file is all of it" "$(jq -r '.preview | length' <<<"$out") $(stat -c %s "$(jq -r .path <<<"$out")")" "8192 20000"

# ---- the size limit and a stalled app
offer "text/plain" "$long"
before=$(stored)
is "limit: a copy over the limit is not recorded, nor kept in part" "$(run env KARCHY_CLIPBOARD_ITEM_LIMIT=19999)$(stored)" "$before"
is "limit: one of exactly the limit is" "$(run env KARCHY_CLIPBOARD_ITEM_LIMIT=20000 | jq -r .size)" "20000"
offer 'text/plain' 'slow'
is "stall: an app that does not answer in time is not recorded" "$(run env CLIP_STALL=1)$(stored)" "$before"

# ---- images
offer 'image/png' '\x89PNG fake' 'text/html' '<img src="x">'
out=$(run env)
is "image: an image without plain text is an image" "$(jq -r '.type + " " + .mime' <<<"$out")" "image image/png"
is "image: named by its content, with its extension" "$(basename "$(jq -r .path <<<"$out")")" "$(printf '\x89PNG fake' | sha256sum | cut -c1-32).png"
offer 'image/jpeg' 'JFIF fake'
is "image: a JPEG is kept as one" "$(run env | jq -r '.mime + " " + (.path | split(".") | last)')" "image/jpeg jpg"
offer 'image/png' '\x89PNG cells' 'text/plain' 'A1\tB1\n'
is "image: with plain text beside it (spreadsheet cells) the copy is text" "$(run env | jq -r .type)" "text"
offer 'text/html' '<b>only html</b>'
before=$(stored)
is "other: a copy with neither text, image nor files is not recorded" "$(run env)$(stored)" "$before"

# ---- files
offer 'text/uri-list' 'file:///home/me/a%20b.txt\r\nfile:///home/me/c.png\r\n' 'x-special/gnome-copied-files' 'copy\nfile:///home/me/a%20b.txt\nfile:///home/me/c.png' 'text/plain;charset=utf-8' '/home/me/a b.txt\n/home/me/c.png\n'
out=$(run env)
is "files: a file manager's copy is a files entry" "$(jq -r '.type + " " + .mime + " " + (.count | tostring)' <<<"$out")" "files text/uri-list 2"
is "files: the preview and the file are the list" "$(jq -r .preview <<<"$out")|$(cat "$(jq -r .path <<<"$out")")" $'file:///home/me/a%20b.txt\nfile:///home/me/c.png|file:///home/me/a%20b.txt\nfile:///home/me/c.png'
offer 'text/uri-list' '# a comment\r\nhttps://example.org/\r\n' 'text/plain' 'https://example.org/'
is "files: a list with a link in it is text, not files" "$(run env | jq -r '.type + " " + .preview')" "text https://example.org/"

# ---- what is never recorded
offer 'text/plain' 'hunter2' 'x-kde-passwordManagerHint' 'secret'
before=$(stored)
is "password manager: its copy is not recorded" "$(run env)$(stored)" "$before"
is "password manager: nor one wl-paste calls sensitive" "$(offer 'text/plain' 'hunter2'; run env CLIPBOARD_STATE=sensitive)$(stored)" "$before"
offer 'text/plain' 'cleared'
is "an emptied clipboard is not a copy" "$(run env CLIPBOARD_STATE=clear)$(run env CLIPBOARD_STATE=nil)$(stored)" "$before"
is "nothing is left half-written" "$(find "$t/run/karchy/clipboard" -name '.incoming*' | wc -l)" "0"
# ---- the copy that was there when the history was switched on
offer 'text/plain' 'copied while the history was off'
: >"$t/run/karchy/clipboard/.skip-next"
before=$(stored)
is "switched on: the copy already on the clipboard is left out" "$(run env)$(stored)" "$before"
is "switched on: the next copy is recorded" "$(run env | jq -r .preview)" "copied while the history was off"

offer 'text/plain' 'no session'
is "without a session folder nothing is recorded" "$(env PATH="$t/bin:$PATH" CLIP="$t/clip" XDG_RUNTIME_DIR= "$capture" </dev/null)" ""

if ((failures > 0)); then
  echo "clipboard-capture: $failures failed"
  exit 1
fi
echo "clipboard-capture: ok"
