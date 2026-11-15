.pragma library

// Plain words for failures the shell sees often, matched on a command's
// stderr. InlineMessage adds the sentence after the caller's own summary
// ("Couldn't change the display.") and keeps the raw output behind Details.
// Unknown output returns "": the summary stands alone then.

var KNOWN = [
  { re: /request dismissed|dismissed by user|authentication (was )?cancel|not authorized|polkit.*cancel/i,
    text: "The password prompt was closed, so nothing changed." },
  { re: /authentication failure|incorrect password|sorry, try again/i,
    text: "The password wasn't accepted." },
  { re: /permission denied|operation not permitted|EACCES/,
    text: "karchy isn't allowed to change this." },
  { re: /command not found|no such file or directory.*(bin|exec)|not installed/i,
    text: "A program this needs isn't installed." },
  { re: /could not resolve|temporary failure in name resolution|network is unreachable|no route to host|connection refused|timed out/i,
    text: "The network couldn't be reached." },
  { re: /no space left on device|disk quota/i,
    text: "The disk is full." },
  { re: /hyprland.*(not running|couldn't connect)|HYPRLAND_INSTANCE_SIGNATURE/i,
    text: "Hyprland didn't answer." },
  { re: /cannot connect to (the )?(podman|docker)|is the docker daemon running/i,
    text: "The container engine isn't running." },
  { re: /\b(busy|in use|locked)\b/i,
    text: "Something else is using it right now; try again in a moment." }
]

function explain(stderr) {
  var text = String(stderr || "")
  if (text.trim() === "") return ""
  for (var i = 0; i < KNOWN.length; i++)
    if (KNOWN[i].re.test(text)) return KNOWN[i].text
  return ""
}

// The last non-empty line, without a "command: " prefix: the part of raw
// output most likely to say what went wrong, for a one-line notice.
function lastLine(stderr) {
  var lines = String(stderr || "").split("\n").map(function(l) { return l.trim() }).filter(function(l) { return l !== "" })
  if (lines.length === 0) return ""
  return lines[lines.length - 1].replace(/^[a-z0-9_.-]+: /i, "")
}
