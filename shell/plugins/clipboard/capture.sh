#!/bin/bash

# Records the clipboard as one history entry (D-167): a file in the history's
# session folder and a line of JSON on stdout for the clipboard service
# (Service.qml). `wl-paste --watch` runs it on every copy; run by hand it
# records the clipboard as it is now.
#
# One copy is one entry, taken as the app pasting it would take it:
#   files  the copy lists files (a file manager's Copy or Cut): the list
#   text   it has plain text
#   image  it has an image and no plain text (a screenshot, Copy image)
#
# Not recorded: a password manager's copy (it carries x-kde-passwordManagerHint,
# as KeePassXC's and others' do), an empty or blank copy, and one over the size
# limit. They still paste as usual: the history is only a record.
#
# The folder is $XDG_RUNTIME_DIR/karchy/clipboard: memory, readable by this
# user only, and gone at logout or power-off. Pinning an entry is what moves
# it to the home folder (Service.qml).

set -o pipefail
umask 077

# The largest copy that is recorded, in bytes.
LIMIT=${KARCHY_CLIPBOARD_ITEM_LIMIT:-16777216}
# How much of a text or a file list the picker searches and draws.
PREVIEW_CHARS=8192

[[ -n ${XDG_RUNTIME_DIR:-} ]] || exit 0
DIR="$XDG_RUNTIME_DIR/karchy/clipboard"

# `wl-paste --watch` runs this once when it starts, for whatever is on the
# clipboard already. The service leaves this mark when that run is not to
# count: the history was just switched on, and what was copied while it was
# off stays out.
if [[ -e $DIR/.skip-next ]]; then
  rm -f -- "$DIR/.skip-next"
  exit 0
fi

# wl-paste says what kind of change this is; only a copy with content counts.
case "${CLIPBOARD_STATE:-data}" in
sensitive | clear | nil) exit 0 ;;
esac

# Under --watch stdin is the copy in whichever type wl-paste picked. The type
# is chosen below instead, so let go of it.
exec </dev/null

types=$(timeout 2s wl-paste --list-types 2>/dev/null) || exit 0

has() {
  grep -qxF -- "$1" <<<"$types"
}

has x-kde-passwordManagerHint && exit 0

mkdir -p "$DIR" || exit 0
tmp=$(mktemp --tmpdir="$DIR" .incoming.XXXXXX) || exit 0
trap 'rm -f -- "$tmp"' EXIT

# The app that copied streams the copy and can stall without closing its end,
# so the read is bounded; a copy cut off at the deadline or at the size limit
# is dropped, not kept in part.
fetch() {
  local status size

  timeout 2s wl-paste --no-newline --type "$1" 2>/dev/null | head -c "$((LIMIT + 1))" >"$tmp"
  status=${PIPESTATUS[0]}
  size=$(stat -c %s -- "$tmp" 2>/dev/null || echo 0)
  ((size > 0 && size <= LIMIT && status == 0))
}

# Moves the fetched copy to its place, named by its content, and sets $file,
# $hash and $size.
keep() {
  hash=$(sha256sum <"$tmp" | cut -c1-32)
  size=$(stat -c %s -- "$tmp")
  file="$DIR/$hash.$1"
  mv -f -- "$tmp" "$file"
}

emit_files() {
  local count preview

  # Comments and blank lines out; the file: lines stay as the app wrote them.
  tr -d '\r' <"$tmp" | grep -v -e '^#' -e '^[[:space:]]*$' >"$tmp.list"
  mv -f -- "$tmp.list" "$tmp"
  count=$(wc -l <"$tmp")
  ((count > 0)) || return 1
  # A list with anything but files in it (a dragged link) is not a file copy.
  if grep -qv '^file://' "$tmp"; then
    return 1
  fi

  # Whole lines only, so a long list never ends in half a path.
  preview=$(awk -v max="$PREVIEW_CHARS" '{ used += length($0) + 1; if (used > max) exit; print }' "$tmp")
  keep uris
  jq -cn --arg id "files:$hash" --arg path "$file" --argjson size "$size" --argjson count "$count" --arg preview "$preview" \
    '{type:"files", id:$id, mime:"text/uri-list", path:$path, size:$size, count:$count, preview:$preview}'
}

emit_image() {
  local mime="$1"
  local ext=${mime#image/}

  [[ $ext == jpeg ]] && ext=jpg
  keep "$ext"
  jq -cn --arg id "image:$hash" --arg mime "$mime" --arg path "$file" --argjson size "$size" \
    --arg captured_at "$(LC_TIME="$(karchy-language locale 2>/dev/null)" date +'%A %H:%M')" \
    '{type:"image", id:$id, mime:$mime, path:$path, size:$size, capturedAt:$captured_at}'
}

# Text is kept as UTF-8 whatever the app sent, and named by that.
emit_text() {
  perl -MEncode=decode,encode,FB_CROAK,LEAVE_SRC -MJSON::PP -MDigest::SHA=sha256_hex -0777 -e '
    my ($tmp, $dir, $preview_chars) = @ARGV;
    open(my $in, "<:raw", $tmp) or exit;
    my $raw = <$in>;
    close($in);
    exit unless defined $raw && length $raw;

    my $encoding;
    my $heuristic_encoding = 0;
    if ($raw =~ /^(?:\xFF\xFE|\xFE\xFF)/) {
      $encoding = "UTF-16";
    } elsif (length($raw) % 2 == 0 && index($raw, "\0") >= 0) {
      my $units = length($raw) / 2;
      my $nuls = $raw =~ tr/\0/\0/;

      # Neither byte lane can reach the padding threshold when the entire
      # payload contains fewer NULs than that, so avoid two full string passes.
      if ($nuls * 4 >= $units * 3) {
        my $even_bytes = $raw;
        $even_bytes =~ s/(.)./$1/sg;
        my $even_nuls = $even_bytes =~ tr/\0/\0/;
        undef $even_bytes;

        my $odd_bytes = $raw;
        $odd_bytes =~ s/.(.)/$1/sg;
        my $odd_nuls = $odd_bytes =~ tr/\0/\0/;

        # BOM-less UTF-16 is indistinguishable from NUL-separated bytes. Decode
        # only when at least three quarters of the code units have consistent
        # padding and fewer than one quarter have NULs in the opposite byte.
        if ($odd_nuls * 4 >= $units * 3 && $even_nuls * 4 < $units) {
          $encoding = "UTF-16LE";
          $heuristic_encoding = 1;
        } elsif ($even_nuls * 4 >= $units * 3 && $odd_nuls * 4 < $units) {
          $encoding = "UTF-16BE";
          $heuristic_encoding = 1;
        }
      }
    }

    my $text = $encoding ? eval { decode($encoding, $raw, FB_CROAK | LEAVE_SRC) } : undef;
    if ($heuristic_encoding && defined($text) && $text =~ /[\x00-\x08\x0E-\x1A\x1C-\x1F]/) {
      $text = undef;
    }
    $text = decode("UTF-8", $raw) unless defined $text;
    # Nothing to paste back from a copy of only spaces and line breaks.
    exit unless $text =~ /\S/;

    my $bytes = encode("UTF-8", $text);
    my $hash = substr(sha256_hex($bytes), 0, 32);
    my $file = "$dir/$hash.txt";
    open(my $out, ">:raw", $tmp) or exit;
    print $out $bytes;
    close($out) or exit;
    rename($tmp, $file) or exit;

    print JSON::PP->new->utf8->canonical->encode({
      type => "text", id => "text:$hash", mime => "text/plain", path => $file,
      size => length($bytes), preview => substr($text, 0, $preview_chars),
    }), "\n";
  ' "$tmp" "$DIR" "$PREVIEW_CHARS"
}

if has text/uri-list && fetch text/uri-list && emit_files; then
  exit 0
fi

if has 'text/plain;charset=utf-8' || has text/plain || has UTF8_STRING || has STRING || has TEXT; then
  fetch text && emit_text
  exit 0
fi

for mime in image/png image/jpeg image/webp image/gif image/bmp image/tiff; do
  if has "$mime"; then
    fetch "$mime" && emit_image "$mime"
    exit 0
  fi
done
