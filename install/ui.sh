# shellcheck shell=bash
# The installer's screen. Sourced by install/karchy-install and by the karchy
# ISO's start script.
#
# Two modes. On a terminal (KARCHY_UI=tui) the installer draws screens: the
# logo, the form's answers as they are given, a summary, a numbered step list
# with times, and a finish or error screen. Anywhere else (a pipe, a log file,
# TERM=dumb, or KARCHY_UI=plain set by the caller) it prints timestamped lines,
# one per event, as it always did. Either way everything is in the log file.
#
# The look is karchy's default theme (themes/nulifyer/colors.toml), the one a
# machine shows before any user's theme exists, and it is set here only: the 16
# console colours, and gum's colours as indexes into them. On the Linux console
# this file also loads karchy's console font and the palette itself; another
# terminal (ssh) brings its own of both.

KARCHY_UI_PALETTE=(202020 ea6962 a9b665 d8a657 7daea3 d3869b 89b482 ddc7a1
  7c6f64 ea6962 a9b665 d8a657 7daea3 d3869b 89b482 ebdbb2)

KARCHY_UI=${KARCHY_UI:-}
UI_ROWS=24
UI_COLS=80
UI_ACCENT="" UI_DIM="" UI_RED="" UI_GREEN="" UI_BOLD="" UI_RESET=""

ui_out() {
  printf '%s' "$*" >&"$KARCHY_CONSOLE"
}

ui_init() {
  if [[ -z $KARCHY_UI ]]; then
    KARCHY_UI=plain
    [[ -t $KARCHY_CONSOLE && ${TERM:-dumb} != dumb ]] && KARCHY_UI=tui
  fi
  [[ $KARCHY_UI == tui ]] || return 0

  UI_ACCENT=$'\033[33m' UI_DIM=$'\033[90m' UI_RED=$'\033[31m' UI_GREEN=$'\033[32m'
  UI_BOLD=$'\033[1m' UI_RESET=$'\033[0m'

  if [[ ${TERM:-} == linux ]]; then
    ui_console_font
    local i
    for i in "${!KARCHY_UI_PALETTE[@]}"; do
      printf '\033]P%x%s' "$i" "${KARCHY_UI_PALETTE[i]}" >&"$KARCHY_CONSOLE"
    done
  fi
  ui_size

  # gum, in the theme's colours: 3 accent, 7 text, 15 bright text, 8 muted,
  # 0 the background. Everything is indented two columns, like the rest
  # (gum confirm indents its question by one column itself).
  export GUM_INPUT_PADDING="0 2" GUM_INPUT_PROMPT="> " GUM_INPUT_PROMPT_FOREGROUND=3 \
    GUM_INPUT_CURSOR_FOREGROUND=3 GUM_INPUT_HEADER_FOREGROUND=15 GUM_INPUT_PLACEHOLDER_FOREGROUND=8
  export GUM_CHOOSE_PADDING="0 2" GUM_CHOOSE_CURSOR="> " GUM_CHOOSE_CURSOR_FOREGROUND=3 \
    GUM_CHOOSE_HEADER_FOREGROUND=15 GUM_CHOOSE_ITEM_FOREGROUND=7 GUM_CHOOSE_SELECTED_FOREGROUND=3
  export GUM_FILTER_PADDING="0 2" GUM_FILTER_INDICATOR=">" GUM_FILTER_INDICATOR_FOREGROUND=3 \
    GUM_FILTER_MATCH_FOREGROUND=3 GUM_FILTER_HEADER_FOREGROUND=15 GUM_FILTER_PROMPT_FOREGROUND=3 \
    GUM_FILTER_PLACEHOLDER_FOREGROUND=8 GUM_FILTER_TEXT_FOREGROUND=7 GUM_FILTER_CURSOR_TEXT_FOREGROUND=15 \
    GUM_FILTER_HEIGHT=10
  export GUM_CONFIRM_PADDING="0 1" GUM_CONFIRM_PROMPT_FOREGROUND=15 GUM_CONFIRM_SELECTED_FOREGROUND=0 \
    GUM_CONFIRM_SELECTED_BACKGROUND=3 GUM_CONFIRM_UNSELECTED_FOREGROUND=15 GUM_CONFIRM_UNSELECTED_BACKGROUND=8
}

# The Linux console: karchy's monospace font in the size that suits the
# screen (lib.sh's console_font), from the installer's own copy. Without it
# the console keeps its font; a high-resolution screen then shows the kernel's
# own large one.
ui_console_font() {
  local font
  font="$KARCHY_SRC/system/console/$(console_font).psfu"
  [[ -f $font ]] && command -v setfont >/dev/null && setfont "$font" 2>/dev/null <&"$KARCHY_CONSOLE"
  return 0
}

ui_size() {
  local size
  size=$(stty size <&"$KARCHY_CONSOLE" 2>/dev/null) || return 0
  [[ $size =~ ^([0-9]+)\ ([0-9]+)$ ]] || return 0
  UI_ROWS=${BASH_REMATCH[1]}
  UI_COLS=${BASH_REMATCH[2]}
}

# A text cut to the screen's width, less the indent.
ui_fit() {
  local text="$1" width=$((UI_COLS - 4))
  ((${#text} > width)) && text="${text:0:width-3}..."
  printf '%s' "$text"
}

UI_HEADER_ROWS=0
UI_LOGO=()
UI_LOGO_COLS=0

# Read a logo file into UI_LOGO and its width in characters into UI_LOGO_COLS.
ui_logo_read() {
  local line LC_ALL=C
  UI_LOGO=()
  UI_LOGO_COLS=0
  [[ -r $1 ]] || return 1
  mapfile -t UI_LOGO <"$1"
  for line in "${UI_LOGO[@]}"; do
    # Characters, whatever the locale: bytes without UTF-8 continuation bytes.
    line=${line//[$'\x80'-$'\xbf']/}
    ((${#line} > UI_LOGO_COLS)) && UI_LOGO_COLS=${#line}
  done
  ((${#UI_LOGO[@]} > 0))
}

# The logo that fits the screen with `need` more lines under it: the wordmark
# (logo.txt), on a narrower screen the mark alone (logo-mark.txt), else none.
# The sizes are the files' own, so a new logo needs no change here. Around the
# logo: a blank line above, one below, the title and its blank line, and two
# lines to spare.
ui_logo_pick() {
  local need="$1" file
  for file in "$KARCHY_SRC/logo.txt" "$KARCHY_SRC/logo-mark.txt"; do
    ui_logo_read "$file" || continue
    ((UI_COLS >= UI_LOGO_COLS + 2 && UI_ROWS >= need + ${#UI_LOGO[@]} + 6)) && return 0
  done
  UI_LOGO=()
  return 1
}

# Clear the screen and draw the header: the logo when the screen has room for
# it and `need` more lines, else the name alone; then the screen's title.
ui_header() {
  local title="$1" need="${2:-10}" line
  [[ $KARCHY_UI == tui ]] || return 0
  ui_size
  ui_out $'\033[0m\033[H\033[2J\n'
  UI_HEADER_ROWS=1
  if ui_logo_pick "$need"; then
    for line in "${UI_LOGO[@]}"; do
      ui_out "  $UI_ACCENT$line$UI_RESET"$'\n'
      UI_HEADER_ROWS=$((UI_HEADER_ROWS + 1))
    done
    ui_out $'\n'
    UI_HEADER_ROWS=$((UI_HEADER_ROWS + 1))
    ui_out "  $UI_BOLD$title$UI_RESET"$'\n\n'
  else
    ui_out "  $UI_ACCENT${UI_BOLD}karchy$UI_RESET  $UI_BOLD$title$UI_RESET"$'\n\n'
  fi
  UI_HEADER_ROWS=$((UI_HEADER_ROWS + 2))
}

# One line of text under the header, indented like everything else.
ui_line() {
  [[ $KARCHY_UI == tui ]] || { [[ -z ${1:-} ]] || echo "  $1" >&"$KARCHY_CONSOLE"; return 0; }
  ui_out "  ${2:-}${1:-}$UI_RESET"$'\n'
}

# A label and its value: the form's answers and the summary.
ui_field() {
  if [[ $KARCHY_UI == tui ]]; then
    ui_out "  $UI_DIM$(printf '%-16s' "$1")$UI_RESET${3:-}$2$UI_RESET"$'\n'
  else
    printf '  %-16s%s\n' "$1" "$2" >&"$KARCHY_CONSOLE"
  fi
}

# --- the step list ---------------------------------------------------------

UI_STEP_NAMES=()
UI_STEP_TIMES=()
UI_STEP_CURRENT=-1
UI_STEP_FAILED=-1
UI_LIST_ROW=0
UI_LIST_ROWS=0
UI_TICKER=""
UI_STARTED=$SECONDS

ui_duration() {
  printf '%d:%02d' $(($1 / 60)) $(($1 % 60))
}

ui_steps_begin() {
  [[ $KARCHY_UI == tui ]] || return 0
  ui_header "Installing karchy on $KARCHY_DISK" "$((${#UI_STEP_NAMES[@]} + 5))"
  UI_LIST_ROW=$((UI_HEADER_ROWS + 1))
  # Under the list: a blank line, the status line, the log's last line and
  # where the log is.
  UI_LIST_ROWS=$((UI_ROWS - UI_LIST_ROW - 5))
  ((UI_LIST_ROWS > ${#UI_STEP_NAMES[@]})) && UI_LIST_ROWS=${#UI_STEP_NAMES[@]}
  ((UI_LIST_ROWS >= 3)) || UI_LIST_ROWS=3
  ui_out $'\033[?25l'
  ui_steps_draw
}

# The list, or the part of it around the current step when the screen is
# shorter than the list.
ui_steps_draw() {
  local total=${#UI_STEP_NAMES[@]} first=0 i mark name time out=""
  if ((total > UI_LIST_ROWS)); then
    first=$((UI_STEP_CURRENT - UI_LIST_ROWS / 2))
    ((first > total - UI_LIST_ROWS)) && first=$((total - UI_LIST_ROWS))
    ((first < 0)) && first=0
  fi
  for ((i = first; i < first + UI_LIST_ROWS && i < total; i++)); do
    name=$(ui_fit "$(printf '%-46s' "${UI_STEP_NAMES[i]}")")
    time=""
    if ((i == UI_STEP_FAILED)); then
      mark="${UI_RED}✗$UI_RESET" name="$UI_RED$name$UI_RESET"
    elif [[ -n ${UI_STEP_TIMES[i]:-} ]]; then
      mark="${UI_GREEN}✓$UI_RESET" time="$UI_DIM$(ui_duration "${UI_STEP_TIMES[i]}")$UI_RESET"
    elif ((i == UI_STEP_CURRENT)); then
      mark="${UI_ACCENT}►$UI_RESET" name="$UI_BOLD$name$UI_RESET"
    else
      mark="$UI_DIM·" name="$name$UI_RESET"
    fi
    out+=$(printf '\033[%d;1H\033[K  %s%2d%s  %s  %s %s' "$((UI_LIST_ROW + i - first))" "$UI_DIM" "$((i + 1))" "$UI_RESET" "$mark" "$name" "$time")
  done
  ui_out "$out"
}

# The lines under the list: where the install is and what the log says.
ui_status_draw() {
  local row=$((UI_LIST_ROW + UI_LIST_ROWS + 1)) last
  last=$(tail -n 1 "$KARCHY_INSTALL_LOG" 2>/dev/null | tr -d '\033\r' | tr -c '[:print:]\n' ' ')
  ui_out "$(printf '\033[%d;1H\033[K  Step %d of %d    this step %s    in all %s\033[%d;1H\033[K  %s%s%s' \
    "$row" "$((UI_STEP_CURRENT + 1))" "${#UI_STEP_NAMES[@]}" "$(ui_duration $((SECONDS - UI_STEP_STARTED)))" \
    "$(ui_duration $((SECONDS - UI_STARTED)))" "$((row + 1))" "$UI_DIM" "$(ui_fit "$last")" "$UI_RESET")"
}

ui_ticker_stop() {
  [[ -n $UI_TICKER ]] || return 0
  kill "$UI_TICKER" 2>/dev/null || true
  wait "$UI_TICKER" 2>/dev/null || true
  UI_TICKER=""
}

ui_step_start() {
  UI_STEP_CURRENT=$1
  UI_STEP_STARTED=$SECONDS
  [[ $KARCHY_UI == tui ]] || return 0
  ui_steps_draw
  ui_status_draw
  ui_out "$(printf '\033[%d;1H\033[K  %sThe full log is %s%s' "$((UI_LIST_ROW + UI_LIST_ROWS + 4))" "$UI_DIM" "$KARCHY_INSTALL_LOG" "$UI_RESET")"
  # A clock for the step under way: once a second, the times and the log's
  # last line.
  (
    set +eE
    trap - ERR
    while sleep 1; do
      ui_status_draw
    done
  ) &
  UI_TICKER=$!
}

ui_step_done() {
  UI_STEP_TIMES[$1]=$((SECONDS - UI_STEP_STARTED))
  [[ $KARCHY_UI == tui ]] || return 0
  ui_ticker_stop
  ui_steps_draw
}

# Leave the step list: the cursor back, below everything drawn.
ui_steps_end() {
  [[ $KARCHY_UI == tui ]] || return 0
  ui_ticker_stop
  ui_out "$(printf '\033[%d;1H\033[J\033[?25h' "$((UI_LIST_ROW + UI_LIST_ROWS + 1))")"
}

# An error: what failed, the end of the log when a step failed, where the log
# is and what to do. `during` is the step's name, empty before the steps.
ui_error() {
  local message="$1" during="${2:-}" line
  if [[ $KARCHY_UI != tui ]]; then
    return 0
  fi
  if ((UI_STEP_CURRENT >= 0 && UI_LIST_ROW > 0)); then
    UI_STEP_FAILED=$UI_STEP_CURRENT
    ui_ticker_stop
    ui_steps_draw
    ui_steps_end
  else
    ui_out $'\n'
  fi
  # The message, wrapped to the screen with its mark in front.
  local mark="✗ "
  while IFS= read -r line; do
    ui_line "$mark$line" "$UI_RED$UI_BOLD"
    mark="  "
  done < <(fold -s -w $((UI_COLS - 6)) <<<"$message")
  if [[ -n $during ]]; then
    ui_line
    while IFS= read -r line; do
      ui_line "$(ui_fit "$line")" "$UI_DIM"
    done < <(tail -n 6 "$KARCHY_INSTALL_LOG" 2>/dev/null | tr -d '\033\r' | tr -c '[:print:]\n' ' ')
    ui_line
    ui_line "The full log: $KARCHY_INSTALL_LOG (less $KARCHY_INSTALL_LOG)"
    ui_line "To try again, fix what the log shows and run karchy-install."
    ui_line "It starts over and erases the disk again."
  fi
}
