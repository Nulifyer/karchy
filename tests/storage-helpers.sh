#!/bin/bash
# Settings › Storage's root side: what the helpers turn away, and how bees'
# status file is read.
# Usage: tests/storage-helpers.sh [folder holding the three helpers]
#   from a checkout:   tests/storage-helpers.sh system/storage
#   on an install:     tests/storage-helpers.sh            (/usr/lib/karchy)
# As a user it checks that a bad request is refused as bad (exit 64) and a
# good one only for not being root (exit 77): the request is judged before
# anything else. As root (in a test VM) it also checks that the refused
# requests left bees' config, its service and the measurement as they were.
# It never sends a good request as root.
dir=${1:-/usr/lib/karchy}
settings=$dir/storage-settings measure=$dir/storage-measure summary=$dir/bees-summary
fails=0
scratch=$(mktemp)
trap 'rm -f "$scratch"' EXIT

ok() { echo "ok   $1"; }
bad() { echo "FAIL $1"; fails=1; }

# What a refused request must leave alone.
state() {
  cat /etc/karchy/bees.conf 2>&1 | sha256sum
  systemctl is-enabled karchy-bees.service 2>&1
  systemctl is-active karchy-bees.service 2>&1
  systemctl show karchy-storage-measure.service -P ExecMainStartTimestamp 2>&1
  stat -c '%Y %s' /var/lib/karchy/storage/measurement.json 2>&1
}

# refused <name> <helper> [arguments...]: exit 64, a usage line, no output.
refused() {
  local name=$1 helper=$2 out err code=0
  shift 2
  out=$("$helper" "$@" 2>"$scratch") || code=$?
  err=$(<"$scratch")
  if ((code == 64)) && [[ -z $out && $err == *usage:* ]]; then ok "refused: $name"; else bad "$name: exit $code, stdout [$out], stderr [$err]"; fi
}

before=$(state)

refused "no request" "$settings"
refused "an unknown key" "$settings" disks=wipe
refused "an unknown value" "$settings" bees=maybe
refused "a key without a value" "$settings" bees
refused "an empty value" "$settings" bees=
refused "a value in capitals" "$settings" bees=ON
refused "a path as the value" "$settings" bees=/etc/passwd
refused "a path as the request" "$settings" /etc/karchy/bees.conf
refused "a path through the key" "$settings" ../bees=on
refused "two requests" "$settings" bees=on measure=now
refused "a good request with an extra argument" "$settings" bees=off /etc/shadow
refused "a good request twice" "$settings" measure=now measure=now
refused "a request with a space after it" "$settings" "bees=on "
refused "a request with a line break" "$settings" $'bees=on\nmeasure=now'
refused "a request with a command in it" "$settings" 'show=bees;id'
refused "a request with a substitution" "$settings" 'show=$(id)'
refused "an option" "$settings" --help
refused "a unit name" "$settings" measure=karchy-bees.service
refused "show with another target" "$settings" show=status
refused "the measurement with an argument" "$measure" /home
refused "the measurement with an option" "$measure" --now

if ((EUID == 0)); then
  if [[ $(state) == "$before" ]]; then ok "refused requests changed nothing"; else bad "a refused request changed bees' config, its service or the measurement"; fi
else
  # A good request gets as far as "are you root", and no further.
  for request in bees=on bees=off measure=now show=bees; do
    code=0
    out=$("$settings" "$request" 2>/dev/null) || code=$?
    if ((code == 77)) && [[ -z $out ]]; then ok "needs root: $request"; else bad "$request as a user: exit $code, stdout [$out]"; fi
  done
  code=0
  "$measure" >/dev/null 2>&1 || code=$?
  if ((code == 77)); then ok "needs root: the measurement"; else bad "the measurement as a user: exit $code"; fi
fi

# bees-summary: status files as bees writes them (karchy's fork 0.11, taken
# from a test VM; the counter lists are shortened).
# summary_is <name> <expected, space separated> <status file text>
summary_is() {
  local name=$1 want=$2 got
  got=$(printf '%s\n' "$3" | "$summary" 2>&1 | tr '\n' ' ')
  if [[ $got == "$want " ]]; then ok "summary: $name"; else bad "summary: $name: want [$want] got [$got]"; fi
}

tab=$'\t'
threads="THREADS (work queue 0 of 8 tasks, 1 workers, load: current 0 target 0 average 0):
${tab}tid 7516: bees: [50.001s] waiting for signals
${tab}tid 7530: extent_250_32M_16E: subvol 250 skipping forward 32M from 0x250f0a000 to 0x252f0a000
${tab}tid 7532: status_report: writing status to file '/run/karchy-bees/status'
${tab}tid 7535: crawl_transid: waiting 49.5016s for next transid RateEstimator { count = 172, raw = 0.99 / 49.5016 }"
header="extsz   datasz  point gen_min gen_max this cycle start tm_left   next cycle ETA
----- -------- ------ ------- ------- ---------------- ------- ----------------"

summary_is "just started, no table yet" "state=starting first_pass=0 percent=0 seconds_left=-1 backlog=0 dedup_bytes=0" "TOTAL:
${tab}hash_extent_in=512
${tab}open_clear=1
RATES:
${tab}hash_extent_in=511.926
$threads
PROGRESS:
[No progress estimate available]"

summary_is "first pass, nothing known yet" "state=scanning first_pass=1 percent=0 seconds_left=-1 backlog=171 dedup_bytes=483774" "TOTAL:
${tab}addr_block=169088 addr_ms=9
${tab}dedup_bytes=483774 dedup_copy=786432 dedup_hit=193
RATES:
${tab}dedup_bytes=59263 dedup_copy=15728
$threads
PROGRESS:
extsz  datasz  point gen_min gen_max this cycle start tm_left   next cycle ETA
----- ------- ------ ------- ------- ---------------- ------- ----------------
  max       - 000000       0     171 2026-11-18 09:18       -                -
  32M       - 000000       0     171 2026-11-18 09:18       -                -
   8M       - 000000       0     171 2026-11-18 09:18       -                -
   2M       - 000000       0     171 2026-11-18 09:18       -                -
 512K       - 000000       0     171 2026-11-18 09:18       -                -
 128K       - 000000       0     171 2026-11-18 09:18       -                -
total 13.008G        gen_now     171                  updated 2026-11-18 09:18"

# The counter under RATES has the same name; only TOTAL's is the total.
summary_is "first pass, well on" "state=scanning first_pass=1 percent=95 seconds_left=1 backlog=171 dedup_bytes=2963249" "TOTAL:
${tab}dedup_bytes=2963249 dedup_copy=786432 dedup_hit=193 dedup_try=193
RATES:
${tab}dedup_bytes=59263.5 dedup_copy=15728
$threads
PROGRESS:
$header
  max   9.747G 953174       0     171 2026-11-18 09:18      1s 2026-11-18 09:18
  32M   1.321G 953174       0     171 2026-11-18 09:18      1s 2026-11-18 09:18
   8M 417.807M 953174       0     171 2026-11-18 09:18      1s 2026-11-18 09:18
   2M 355.821M 953174       0     171 2026-11-18 09:18      1s 2026-11-18 09:18
 512K 575.783M 953174       0     171 2026-11-18 09:18      1s 2026-11-18 09:18
 128K 636.197M 953174       0     171 2026-11-18 09:18      1s 2026-11-18 09:18
total  13.008G        gen_now     172                  updated 2026-11-18 09:18"

# Tiers of different sizes at different points: 40 GiB at 25%, 10 GiB at
# 100% (idle), 10 GiB at 50% is (10 + 10 + 5) of 60, 41%; the longest time
# left counts, "2w 5d".
summary_is "first pass, tiers weighed by their data" "state=scanning first_pass=1 percent=41 seconds_left=1641600 backlog=571003 dedup_bytes=7" "TOTAL:
${tab}dedup_bytes=7
PROGRESS:
$header
  max      40G 250000       0  571003 2024-11-30 08:38   2w 5d 2024-12-20 03:08
  32M      10G 999999       0  571003 2024-11-30 08:38       -             idle
 128K      10G 500000       0  571003 2024-11-30 08:38  6m 31s 2024-11-30 08:45
total      60G        gen_now  573016                  updated 2024-12-01 03:04"

# A tier that is already past its first pass counts as done during one.
summary_is "first pass, one tier already on new data" "state=scanning first_pass=1 percent=75 seconds_left=3600 backlog=171 dedup_bytes=0" "PROGRESS:
$header
  max       - 500000       0     171 2026-11-18 09:18      1h 2026-11-18 10:18
 128K       - 100000     171     180 2026-11-18 09:20      5m 2026-11-18 09:25"

summary_is "keeping up with new data" "state=scanning first_pass=0 percent=95 seconds_left=391 backlog=1 dedup_bytes=113675" "TOTAL:
${tab}dedup_bytes=113675
PROGRESS:
extsz  datasz  point gen_min gen_max this cycle start tm_left   next cycle ETA
----- ------- ------ ------- ------- ---------------- ------- ----------------
  max       - 951873     131     132 2026-11-18 06:53  6m 31s 2026-11-18 09:08
  32M       - 951873     131     132 2026-11-18 06:53  6m 31s 2026-11-18 09:08
 128K       - 951873     131     132 2026-11-18 06:53  6m 31s 2026-11-18 09:08
total 13.008G        gen_now     145                  updated 2026-11-18 09:02"

summary_is "back after a night off: many transactions to catch up on" "state=scanning first_pass=0 percent=30 seconds_left=720 backlog=2880 dedup_bytes=0" "PROGRESS:
$header
  max   9.747G 300000    4120    7000 2026-11-18 09:18     12m 2026-11-18 09:30
 128K 636.197M 300000    4120    7000 2026-11-18 09:18      5m 2026-11-18 09:23"

summary_is "everything checked" "state=idle first_pass=0 percent=100 seconds_left=-1 backlog=0 dedup_bytes=5120000" "TOTAL:
${tab}dedup_bytes=5120000
PROGRESS:
$header
  max   9.747G 000000     171     172 2026-11-18 09:18       -             idle
  32M   1.321G 000000     171     172 2026-11-18 09:18       -             idle
 128K 636.197M 000000     171     172 2026-11-18 09:18    idle             idle
total  13.008G        gen_now     172                  updated 2026-11-18 09:30"

summary_is "a table in a form it doesn't know" "state=unknown first_pass=0 percent=0 seconds_left=-1 backlog=0 dedup_bytes=9" "TOTAL:
${tab}dedup_bytes=9
PROGRESS:
extsz  size  where  first  last  eta
----- ----- ------ ------ ----- ----
  max   10G    50%      0   171  1h"

summary_is "an empty file" "state=starting first_pass=0 percent=0 seconds_left=-1 backlog=0 dedup_bytes=0" ""

# Nothing of a thread's note, where file names can appear, ever comes out,
# and no line that is not a counter or a tier is taken for one.
hostile="TOTAL:
${tab}dedup_bytes=12x dedup_bytes=-5 dedup_bytes= dedup_bytes=44
$threads
${tab}tid 7600: reading /home/me/secret plans.txt dedup_bytes=999 state=idle
PROGRESS:
$header
  max      1G 500000       0     171 2026-11-18 09:18      1h 2026-11-18 10:18
  evil     1G 999999       0     171 2026-11-18 09:18      9y 2026-11-18 10:18
  32M      1G xxxxxx       0     171 2026-11-18 09:18      9y 2026-11-18 10:18
\$(id) ; rm -rf / 128K"
summary_is "odd lines are skipped" "state=scanning first_pass=1 percent=50 seconds_left=3600 backlog=171 dedup_bytes=44" "$hostile"
got=$(printf '%s\n' "$hostile" | "$summary" 2>&1)
if grep -Evq '^[a-z_]+=[a-z0-9-]+$' <<<"$got" || grep -q 'secret' <<<"$got"; then bad "summary printed something other than name=number lines: [$got]"; else ok "summary: only name=number lines come out"; fi

# The measurement's reading of smartctl's JSON report: the jq filter, taken
# from the helper as it is and run on reports of the shapes smartctl 7 prints.
# health_is <name> <expected JSON> <report>
eval "$(sed -n "/^SMART_FILTER='\$/,/^    }'\$/p" "$measure")"
health_is() {
  local name=$1 want=$2 got
  got=$(jq -c --arg name sdx "$SMART_FILTER" <<<"$3" 2>&1)
  if [[ $got == "$want" ]]; then ok "health: $name"; else bad "health: $name: want [$want] got [$got]"; fi
}

health_is "a healthy NVMe drive" '{"name":"sdx","serial":"S4EWNX0N123456","health":"good","problems":[],"wear":3,"temperature":41}' '
  {"model_name": "Samsung SSD 970 EVO Plus 1TB", "serial_number": "S4EWNX0N123456", "smart_status": {"passed": true, "nvme": {"value": 0}},
   "nvme_smart_health_information_log": {"critical_warning": 0, "temperature": 41, "available_spare": 100, "available_spare_threshold": 10, "percentage_used": 3, "media_errors": 0},
   "temperature": {"current": 41}}'
health_is "an NVMe drive out of spare blocks, with errors" '{"name":"sdx","serial":"X","health":"warning","problems":["critical","media-errors","spare-low","worn"],"wear":100,"temperature":55}' '
  {"serial_number": "X", "smart_status": {"passed": true},
   "nvme_smart_health_information_log": {"critical_warning": 1, "available_spare": 4, "available_spare_threshold": 10, "percentage_used": 113, "media_errors": 7},
   "temperature": {"current": 55}}'
health_is "a healthy SATA SSD (wear from attribute 177)" '{"name":"sdx","serial":"S3YPNB0K","health":"good","problems":[],"wear":1,"temperature":34}' '
  {"model_name": "Samsung SSD 860 EVO 4TB", "serial_number": "S3YPNB0K", "rotation_rate": 0, "smart_status": {"passed": true},
   "ata_smart_attributes": {"table": [
     {"id": 5, "name": "Reallocated_Sector_Ct", "value": 100, "raw": {"value": 0}},
     {"id": 177, "name": "Wear_Leveling_Count", "value": 99, "raw": {"value": 14}},
     {"id": 190, "name": "Airflow_Temperature_Cel", "value": 66, "raw": {"value": 34}}]},
   "temperature": {"current": 34}}'
health_is "a hard disk with damaged blocks, which has no wear" '{"name":"sdx","serial":"WD-1","health":"warning","problems":["reallocated","pending","unreadable"],"wear":null,"temperature":38}' '
  {"serial_number": "WD-1", "rotation_rate": 5400, "smart_status": {"passed": true},
   "ata_smart_attributes": {"table": [
     {"id": 5, "value": 99, "raw": {"value": 8}}, {"id": 197, "value": 100, "raw": {"value": 2}},
     {"id": 198, "value": 100, "raw": {"value": 2}}, {"id": 177, "value": 50, "raw": {"value": 1}}]},
   "temperature": {"current": 38}}'
health_is "a disk that says it is failing" '{"name":"sdx","serial":"","health":"warning","problems":["failing"],"wear":null,"temperature":null}' '
  {"smart_status": {"passed": false}}'
health_is "a sleeping hard disk, left asleep" '{"name":"sdx","serial":"","health":"asleep","problems":[],"wear":null,"temperature":null}' '
  {"smartctl": {"messages": [{"string": "Device is in STANDBY mode, exit(2)", "severity": "information"}], "exit_status": 2}}'
health_is "a disk with no SMART (a virtual one, a USB stick)" '{"name":"sdx","serial":"","health":"unknown","problems":[],"wear":null,"temperature":null}' '
  {"smartctl": {"messages": [{"string": "/dev/vda: Unable to detect device type", "severity": "error"}], "exit_status": 1}}'
health_is "values of the wrong kind are not passed on" '{"name":"sdx","serial":"12345","health":"good","problems":[],"wear":null,"temperature":null}' '
  {"serial_number": 12345, "rotation_rate": 0, "smart_status": {"passed": true},
   "ata_smart_attributes": {"table": [{"id": 231, "value": "full", "raw": {"value": 0}}]}, "temperature": {"current": "hot"}}'

((fails == 0)) && echo "storage helpers ok"
exit "$fails"
