#!/usr/bin/env bash
# Background screenshots (plan Task 14): renders Dolly's views with ImageRenderer in a process that
# has no window and no NSApplication run loop.
#
# Usage: scripts/shots.sh [scenario ...]
#        default: every scenario in SCENARIOS below, each in light and dark
#        -> build/shots/<scenario>-<light|dark>.png (2880x1800)
# Env:   DOLLY_APP  bundle to run (default build/bundle/Dolly.app, from scripts/bundle.sh)
#        OUT        where the PNGs go (default build/shots)
#
# Safety: each shot is a direct exec of the bundle binary (never `open`, never LaunchServices)
# with a fresh DOLLY_HOME from mktemp. The frontmost app is read with `lsappinfo front` before and
# after every launch (exit 3 if it changed). While the process runs, scripts/winlist.swift is
# polled every 100 ms (exit 4 if the process ever owns an on-screen window), and so is
# `lsappinfo find pid=` (exit 5 if it registers as an application). Only that PID is ever
# stopped, and the only thing deleted is the exact mktemp directory.
set -euo pipefail
# Shot mode never starts Sparkle; this keeps it off even if that ever changes.
export DOLLY_NO_UPDATES=1

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP="${DOLLY_APP:-$REPO/build/bundle/Dolly.app}"
BIN="$APP/Contents/MacOS/Dolly"
OUT="${OUT:-$REPO/build/shots}"
LOG="$OUT/shots.log"
TOOLS="$REPO/build/shots/bin"
TMP_ROOT="${TMPDIR:-/tmp}"
TMP_ROOT="${TMP_ROOT%/}"
SIZE=1440x900
TIMEOUT_SECONDS=60
SCENARIOS=("$@")
[ ${#SCENARIOS[@]} -gt 0 ] || SCENARIOS=(editor-empty editor stage-play record-bar countdown permission settings export export-progress export-done)

[ -x "$BIN" ] || { echo "no binary at $BIN (run scripts/bundle.sh --release)" >&2; exit 1; }
if pgrep -if -- "$BIN" >/dev/null 2>&1; then
  echo "$APP is already running; quit it first (this script never touches it)" >&2
  exit 1
fi

mkdir -p "$OUT" "$TOOLS"
if [ ! -x "$TOOLS/winlist" ] || [ "$REPO/scripts/winlist.swift" -nt "$TOOLS/winlist" ]; then
  swiftc -O "$REPO/scripts/winlist.swift" -o "$TOOLS/winlist"
fi
# accept.sh measures the PNGs with this.
: >"$LOG"

# The frontmost app as "asn name" on one line.
front() {
  local asn name
  asn="$(lsappinfo front 2>/dev/null || true)"
  name="$(lsappinfo info -only name "$asn" 2>/dev/null | head -1 || true)"
  echo "$asn $name"
}

PID=""
HOME_DIR=""

pid_running() {
  local state
  state="$(ps -o stat= -p "$1" 2>/dev/null | cut -c1 || true)"
  [ -n "$state" ] && [ "$state" != Z ]
}

stop_app() {
  if [ -n "$PID" ]; then
    if pid_running "$PID"; then
      kill -TERM "$PID" 2>/dev/null || true
      for _ in $(seq 1 25); do
        pid_running "$PID" || break
        sleep 0.2
      done
      if pid_running "$PID"; then kill -KILL "$PID" 2>/dev/null || true; fi
    fi
    wait "$PID" 2>/dev/null || true
    PID=""
  fi
}

remove_home() {
  case "$HOME_DIR" in
    "$TMP_ROOT"/dolly-shots.?*) [ -d "$HOME_DIR" ] && rm -rf -- "$HOME_DIR" ;;
  esac
  HOME_DIR=""
}

cleanup() {
  stop_app
  remove_home
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

shoot() { # scenario appearance
  local scn="$1" mode="$2" before after rc=0 windows="" registered="" asn deadline out="$OUT/$1-$2.png"
  local args=(--shot "$scn" --appearance "$mode" --size "$SIZE" --out "$out")
  HOME_DIR="$(mktemp -d "$TMP_ROOT/dolly-shots.XXXXXX")"
  mkdir "$HOME_DIR/fixtures"
  cp "$REPO/Tests/DollyCoreTests/Fixtures/shelf-demo.csv" "$REPO/docs/mockup/assets/footage-light.png" \
    "$REPO/docs/mockup/assets/footage-dark.png" "$HOME_DIR/fixtures/"
  args+=(--fixtures "$HOME_DIR/fixtures")
  rm -f -- "$out"
  before="$(front)"

  DOLLY_HOME="$HOME_DIR" "$BIN" "${args[@]}" >>"$LOG" 2>&1 &
  PID=$!
  local launched_pid="$PID"
  deadline=$(($(date +%s) + TIMEOUT_SECONDS))
  while pid_running "$PID"; do
    if ! "$TOOLS/winlist" "$PID" >"$HOME_DIR/windows.txt" 2>/dev/null; then
      windows="$(cat "$HOME_DIR/windows.txt")"
      break
    fi
    asn="$(lsappinfo find "pid=$PID" 2>/dev/null || true)"
    if [ -n "$asn" ]; then
      registered="$asn"
      break
    fi
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "timeout after ${TIMEOUT_SECONDS} s for $scn/$mode" >&2
      break
    fi
    sleep 0.1
  done
  if [ -z "$windows" ] && [ -z "$registered" ] && ! pid_running "$PID"; then
    wait "$PID" || rc=$?
  else
    rc=1
  fi
  stop_app
  after="$(front)"
  echo "$scn $mode pid=$launched_pid rc=$rc app=[${registered:-none}] before=[$before] after=[$after]" >>"$LOG"
  remove_home

  if [ -n "$windows" ]; then
    echo "an on-screen window appeared for $scn/$mode (pid $launched_pid): $windows" >&2
    exit 4
  fi
  if [ -n "$registered" ]; then
    echo "$scn/$mode registered as an application (pid $launched_pid, $registered)" >&2
    exit 5
  fi
  if [ "$before" != "$after" ]; then
    echo "frontmost app changed during $scn/$mode: [$before] -> [$after] (pid $launched_pid)" >&2
    exit 3
  fi
  if [ "$rc" -ne 0 ] || [ ! -s "$out" ]; then
    echo "shot failed for $scn/$mode (exit $rc), see $LOG" >&2
    exit 1
  fi
  echo "ok $scn-$mode $(sips -g pixelWidth -g pixelHeight "$out" | awk '/pixelWidth/{w=$2} /pixelHeight/{h=$2} END{print w "x" h}')"
}

for s in "${SCENARIOS[@]}"; do
  for a in light dark; do
    shoot "$s" "$a"
  done
done
echo "log: $LOG"
