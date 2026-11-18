#!/bin/bash
# Run karchy-share-picker against stand-ins for the menu, hyprctl and slurp.
# Usage: tests/share-picker.sh [path to karchy-share-picker]   (from a checkout: PATH="$PWD/bin:$PATH" KARCHY_PATH="$PWD" tests/share-picker.sh bin/karchy-share-picker)
# The stand-in menu records the rows and answers with the row number in $PICK
# (0 = Escape), the way karchy-menu-select returns "<label><TAB><subtext>".
picker=${1:-/usr/share/karchy/bin/karchy-share-picker}
stub=$(mktemp -d); trap 'rm -rf "$stub"' EXIT
cat > "$stub/karchy-menu-select" <<'S'
#!/bin/bash
shift; rows=()
while (($#)) && [[ $1 != "--" ]]; do rows+=("$1"); shift; done
printf '%s\n' "${rows[@]}" > "$STUB_ROWS"
[[ ${MENU_FAILS:-} == 1 ]] && exit 2
((PICK > 0)) || exit 1
row=${rows[PICK-1]}; printf '%s\n' "${row#*$'\t'}"
S
cat > "$stub/hyprctl" <<'S'
#!/bin/bash
case "$*" in
  "-j monitors") cat "$STUB_MONITORS" ;;
  "-j clients") cat "$STUB_CLIENTS" ;;
esac
S
cat > "$stub/slurp" <<'S'
#!/bin/bash
[[ -n ${SLURP_SAYS:-} ]] || exit 1
echo "$SLURP_SAYS"
S
# The picker declines unless karchy's shell runs, and watches that process:
# this script stands in for it.
cat > "$stub/pgrep" <<'S'
#!/bin/bash
echo "$STUB_SHELL_PID"
S
export STUB_SHELL_PID=$$
chmod +x "$stub"/*
export STUB_ROWS=$stub/rows STUB_MONITORS=$stub/monitors STUB_CLIENTS=$stub/clients
mon() { printf '{"name":"%s","width":%s,"height":%s,"scale":%s,"transform":0,"focused":%s,"mirrorOf":"%s","specialWorkspace":{"name":"%s"}}' "$@"; }
echo "[$(mon eDP-1 2256 1504 1.6 false none ""),$(mon DP-2 3840 2160 1.5 true none "special:shown"),$(mon HDMI-A-1 1920 1080 1 false DP-2 "")]" > "$STUB_MONITORS"
# 0x10 normal, 0x20 on a hidden special workspace, 0x30 on a shown special workspace
echo '[{"address":"0x10","workspace":{"name":"1"}},{"address":"0x20","workspace":{"name":"special:minimized"}},{"address":"0x30","workspace":{"name":"special:shown"}}]' > "$STUB_CLIENTS"
tab=$'\t'; nl=$'\n'
export XDPH_WINDOW_SHARING_LIST="101[HC>]foot[HT>]same title[HE>]16[HA>]102[HC>]foot[HT>]same title[HE>]0[HA>]103[HC>]brave[HT>]hidden one[HE>]32[HA>]104[HC>]mpv[HT>]shown special[HE>]48[HA>]105[HC>]ed${tab}itor[HT>]a${tab}b${nl}c [HT> x[HC> [HE> | \\ %s * — 日本[HE>]16[HA>]106[HC>]noclass[HT>][HE>]16[HA>]107[HC>][HT>][HE>]16[HA>]bad[HC>]x[HT>]y[HE>]1[HA>]garbage[HA>]"
check() { # <name> <expected> <pick> [env...]
  local name=$1 want=$2 pick=$3 got; shift 3
  got=$(env PATH="$stub:$PATH" PICK="$pick" "$@" "$picker" "${ARGS[@]}" 2>/dev/null); rc=$?
  if [[ $got == "$want" ]]; then echo "ok   $name -> ${got:-(nothing, exit $rc)}"; else echo "FAIL $name: want [$want] got [$got] exit $rc"; fails=1; fi
}
fails=0; ARGS=(--allow-token)
check "first row is the screen in use" "[SELECTION]r/screen:DP-2" 1
check "second screen" "[SELECTION]r/screen:eDP-1" 2
check "first of two same-titled windows" "[SELECTION]r/window:101" 3
check "second of two same-titled windows" "[SELECTION]r/window:102" 4
check "window on a shown special workspace" "[SELECTION]r/window:104" 5
check "title with tabs, a line break and separator look-alikes" "[SELECTION]r/window:105" 6
check "window with no title" "[SELECTION]r/window:106" 7
check "window with no title and no app name" "[SELECTION]r/window:107" 8
check "region" "[SELECTION]r/region:eDP-1@10,20,300,200" 9 SLURP_SAYS="eDP-1@10,20,300,200"
check "region cancelled in slurp" "" 9
check "region with an answer that is not a region" "" 9 SLURP_SAYS="eDP-1@-5,20,300,200"
check "Escape" "" 0
check "menu could not open" "" 1 MENU_FAILS=1
ARGS=()
check "no --allow-token, no r flag" "[SELECTION]/screen:DP-2" 1
echo "--- rows shown:"; cat -A "$STUB_ROWS" | cut -c1-110
echo "rows: $(wc -l < "$STUB_ROWS") (2 screens, 6 windows, 1 region; the mirror, the hidden window and 2 malformed entries left out)"
exit $fails
