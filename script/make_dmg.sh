#!/usr/bin/env bash
# Builds a Release ClackClock.app and packages it as dist/ClackClock-<version>.dmg
# with the usual drag-to-install layout: the app on the left, an Applications
# shortcut on the right.
#
# Signing: by default the app keeps the project's own signature (Apple
# Development), which installs and runs on this Mac. Other Macs' Gatekeeper
# blocks it unless it's signed with a Developer ID and notarized:
#
#   DEVELOPER_ID="Developer ID Application: Your Name (SG8NYPLMNY)" \
#   NOTARY_PROFILE=clackclock-notary script/make_dmg.sh
#
# Create the notary profile once with `xcrun notarytool store-credentials`.
#
# Or package an app Xcode's Organizer already exported (Distribute App >
# Direct Distribution: Developer ID signed, notarized and stapled) as is:
#
#   APP="/path/to/exported/ClackClock.app" script/make_dmg.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="${TMPDIR:-/tmp}/ClackClock-DMG"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="ClackClock"

die() { echo "error: $*" >&2; exit 1; }

# A DMG signed with anything but a Developer ID, or signed and never notarized,
# is assessed and rejected outright on other Macs ("Apple could not verify ...
# is free of malware") even when the app inside is notarized. Unsigned, it isn't
# assessed at all and Gatekeeper judges the app alone.
if [[ -n "${DEVELOPER_ID:-}" ]]; then
  [[ "$DEVELOPER_ID" == "Developer ID Application:"* ]] \
    || die "DEVELOPER_ID must be a \"Developer ID Application: ...\" identity, not \"$DEVELOPER_ID\""
  [[ -n "${NOTARY_PROFILE:-}" ]] \
    || die "DEVELOPER_ID needs NOTARY_PROFILE too: a signed but unnotarized DMG is blocked on other Macs"
fi

if [[ -n "${APP:-}" ]]; then
  [[ -d "$APP" ]] || die "APP=$APP doesn't exist"
  # Re-signing here would void the export's notarization ticket.
else
  xcodebuild -quiet -project "$ROOT_DIR/ClackClock.xcodeproj" -scheme ClackClock \
    -configuration Release -derivedDataPath "$BUILD_DIR/DerivedData" build
  APP="$BUILD_DIR/DerivedData/Build/Products/Release/$APP_NAME.app"

  if [[ -n "${DEVELOPER_ID:-}" ]]; then
    # Re-signing with only the project's entitlements also drops the
    # development-only get-task-allow.
    codesign --force --options runtime --timestamp \
      --entitlements "$ROOT_DIR/ClackClock/ClackClock.entitlements" --sign "$DEVELOPER_ID" "$APP"
  fi
fi

STAGE="$BUILD_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")"
RW_DMG="$BUILD_DIR/$APP_NAME-rw.dmg"
OUT="$DIST_DIR/$APP_NAME-$VERSION.dmg"
mkdir -p "$DIST_DIR"
rm -f "$RW_DMG" "$OUT"
# Laid out under a unique name: Finder finds disks by volume name, and an
# already-mounted "ClackClock" (an earlier DMG left open) would take the layout
# instead. Renamed to "ClackClock" before it's sealed.
LAYOUT_NAME="$APP_NAME-layout-$$"
hdiutil create -quiet -volname "$LAYOUT_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -ov "$RW_DMG"

# Lay the window out while the image is still writable. Finder saves the
# layout into the volume's .DS_Store, so every Mac that opens the DMG sees it.
ATTACHED="$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG" 2>/dev/null)"
DEVICE="$(awk '/\/Volumes\// { print $1; exit }' <<<"$ATTACHED")"
MOUNT="$(awk -F'\t' '/\/Volumes\// { print $NF; exit }' <<<"$ATTACHED")"
# Finder registers a new mount a moment after hdiutil returns.
for _ in $(seq 1 20); do
  [[ "$(osascript -e "tell application \"Finder\" to exists disk \"$LAYOUT_NAME\"" 2>/dev/null)" == "true" ]] && break
  sleep 0.5
done
osascript <<EOF || echo "warning: couldn't arrange the DMG window (Finder automation denied?); the DMG still installs fine" >&2
tell application "Finder"
  tell disk "$LAYOUT_NAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 740, 460}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 112
    set text size of viewOptions to 13
    set position of item "$APP_NAME.app" of container window to {140, 150}
    set position of item "Applications" of container window to {400, 150}
    update without registering applications
    delay 1
    close
  end tell
end tell
EOF
diskutil rename "$MOUNT" "$APP_NAME" >/dev/null
sync
hdiutil detach -quiet "$DEVICE" 2>/dev/null || hdiutil detach -force -quiet "$DEVICE"
hdiutil convert -quiet "$RW_DMG" -format UDZO -imagekey zlib-level=9 -o "$OUT"
rm -f "$RW_DMG"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  codesign --sign "$DEVELOPER_ID" --timestamp "$OUT"
  xcrun notarytool submit "$OUT" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUT"
  spctl --assess --type open --context context:primary-signature "$OUT" \
    || die "Gatekeeper rejects $OUT"
fi

# The same verdict a downloading Mac's Gatekeeper reaches on first launch.
spctl --assess --type execute "$STAGE/$APP_NAME.app" 2>/dev/null \
  || echo "warning: Gatekeeper rejects $APP_NAME.app; this DMG only works on this Mac" >&2

echo "$OUT"
