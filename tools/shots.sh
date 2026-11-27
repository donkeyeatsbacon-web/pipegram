#!/usr/bin/env bash
# Grab one screenshot per layout variant, so they can be compared side by side
# without clicking through the picker.
#
#   heavy tools/shots.sh [outdir] [puzzle] [state]
#
# state: flow (mid-chase, the default) | pressure | solved | blank
set -u
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/pipegram-shots}"
PUZZLE="${2:-6}"
STATE="${3:-flow}"
# the layout table is the only place that knows how many there are
COUNT="$(python3 - <<'PY'
import re
src = open("scripts/Main.gd").read()
tbl = src[src.index("var LAYOUTS: Array = ["):]
tbl = tbl[:tbl.index("\n]")]
print(tbl.count('"name":'))
PY
)"
mkdir -p "$OUT"
EXTRA=""
case "$STATE" in
  flow)   EXTRA="--flow" ;;
  solved) EXTRA="--solved" ;;
  pressure) EXTRA="--pressure" ;;
  blank)  EXTRA="" ;;
esac
echo "$COUNT layouts -> $OUT  (puzzle $PUZZLE, $STATE)"
for i in $(seq 0 $((COUNT - 1))); do
  f="$OUT/layout-$(printf '%02d' "$i").png"
  godot --path . -- --screenshot "$f" --puzzle "$PUZZLE" --layout "$i" $EXTRA \
      >/dev/null 2>&1
  if [[ -f "$f" ]]; then echo "  ok  $f"; else echo "  FAILED layout $i"; fi
done
