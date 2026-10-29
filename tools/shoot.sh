#!/bin/bash
# tools/shoot.sh <out.png> [file-to-open] [command-id]
# Launches the app, captures only its own window (screencapture -l), quits.
set -e
out="$1"; open_file="${2:-}"; cmd="${3:-}"
idfile="$(mktemp -t quincyid)"; rm -f "$idfile"
QUINCY_WINDOW_ID="$idfile" QUINCY_OPEN="$open_file" QUINCY_SNAPSHOT_COMMAND="$cmd" \
  "$(dirname "$0")/../build/Quincy 2005.app/Contents/MacOS/Quincy 2005" >/dev/null 2>&1 &
pid=$!
for i in $(seq 1 50); do [[ -s "$idfile" ]] && break; sleep 0.1; done
sleep 0.8
read main key < "$idfile"
screencapture -x -o -l "${WINDOW:-$key}" "$out"
kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null || true
rm -f "$idfile"
