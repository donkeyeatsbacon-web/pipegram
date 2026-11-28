#!/usr/bin/env bash
# Grab a still of the board in each state worth looking at.
#
#   heavy tools/shots.sh [outdir] [puzzle]
#
# There used to be a layout per shot; there is one arrangement now, so the
# states are what vary.
set -u
cd "$(dirname "$0")/.."
OUT="${1:-/tmp/pipegram-shots}"
PUZZLE="${2:-6}"
mkdir -p "$OUT"
shot() {  # name, extra flag
  local f="$OUT/$1.png"
  godot --path . -- --screenshot "$f" --puzzle "$PUZZLE" ${2:-} >/dev/null 2>&1
  if [[ -f "$f" ]]; then echo "  ok  $f"; else echo "  FAILED $1"; fi
}
echo "stills of puzzle $PUZZLE -> $OUT"
shot blank
shot flow     --flow
shot pressure --pressure
shot solved   --solved
