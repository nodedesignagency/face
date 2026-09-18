#!/usr/bin/env bash
# Build the app and launch it on an iOS simulator.
#
#   ./scripts/run-ios.sh              # newest available iPhone, or one already booted
#   ./scripts/run-ios.sh "iPhone 16"  # a named device
set -euo pipefail

SCHEME="CatFace"
BUNDLE_ID="com.example.CatFace"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build-ios"
WANTED="${1-}"

udid_of_name() {
  xcrun simctl list devices available \
    | grep -E "^[[:space:]]+${1} \(" \
    | head -1 \
    | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/'
}

if [ -n "$WANTED" ]; then
  UDID="$(udid_of_name "$WANTED")"
  [ -n "$UDID" ] || { echo "No simulator named '$WANTED'. Available:"; \
    xcrun simctl list devices available | grep -E '^[[:space:]]+iPhone'; exit 1; }
else
  # Reuse a booted simulator so repeat runs land in the window already open.
  UDID="$(xcrun simctl list devices | grep '(Booted)' | head -1 \
    | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*\(Booted\).*/\1/' || true)"
  if [ -z "$UDID" ]; then
    # Last iPhone listed is under the newest installed runtime.
    UDID="$(xcrun simctl list devices available \
      | grep -E '^[[:space:]]+iPhone' | tail -1 \
      | sed -E 's/.*\(([0-9A-Fa-f-]{36})\).*/\1/')"
  fi
fi

[ -n "$UDID" ] || { echo "No iOS simulator found. Install one in Xcode ▸ Settings ▸ Components."; exit 1; }
echo "==> Simulator $UDID"

echo "==> Building"
xcodebuild \
  -project "$PROJECT_DIR/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$BUILD_DIR" \
  build

APP="$BUILD_DIR/Build/Products/Debug-iphonesimulator/$SCHEME.app"
[ -d "$APP" ] || { echo "Build succeeded but $APP is missing."; exit 1; }

echo "==> Launching"
open -a Simulator
xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID"
