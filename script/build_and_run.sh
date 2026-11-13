#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
case "$MODE" in
  run|--debug|--logs|--telemetry|--verify) ;;
  *) echo "Usage: $0 [--debug|--logs|--telemetry|--verify]" >&2; exit 2 ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/ClackClock-DerivedData"
APP_BUNDLE="$BUILD_DIR/Build/Products/Debug/ClackClock.app"

xcodebuild -quiet -project "$ROOT_DIR/ClackClock.xcodeproj" -scheme ClackClock \
  -configuration Debug -derivedDataPath "$BUILD_DIR" build
pkill -x ClackClock >/dev/null 2>&1 || true

case "$MODE" in
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/ClackClock" ;;
  *)
    /usr/bin/open -n "$APP_BUNDLE"
    case "$MODE" in
      --logs) /usr/bin/log stream --info --style compact --predicate 'process == "ClackClock"' ;;
      --telemetry) /usr/bin/log stream --info --style compact --predicate 'subsystem == "com.rajeevranjan.clackclock"' ;;
      --verify) sleep 1; pgrep -x ClackClock >/dev/null ;;
    esac
    ;;
esac
