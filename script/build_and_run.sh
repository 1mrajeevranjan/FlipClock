#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/FlipClock-DerivedData"
APP_BUNDLE="$BUILD_DIR/Build/Products/Debug/FlipClock.app"

xcodebuild -quiet -project "$ROOT_DIR/FlipClock.xcodeproj" -scheme FlipClock \
  -configuration Debug -derivedDataPath "$BUILD_DIR" build
pkill -x FlipClock >/dev/null 2>&1 || true

case "$MODE" in
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/FlipClock" ;;
  *)
    /usr/bin/open -n "$APP_BUNDLE"
    case "$MODE" in
      --logs) /usr/bin/log stream --info --style compact --predicate 'process == "FlipClock"' ;;
      --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.rajeevranjan.flipclock"' ;;
      --verify) sleep 1; pgrep -x FlipClock >/dev/null ;;
    esac
    ;;
esac
