#!/usr/bin/env bash
# Build the app and launch it on a connected iPhone.
#
#   ./scripts/run-device.sh                    # auto-detect team and device
#   ./scripts/run-device.sh ABCDE12345         # explicit Apple Development team id
#   BUNDLE_ID=com.yourname.CatFace ./scripts/run-device.sh
#
# Requires signing in once under Xcode ▸ Settings ▸ Accounts — that is what
# creates the Apple Development certificate this reads. A free Apple ID works.
set -euo pipefail

SCHEME="CatFace"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../App" && pwd)"
BUILD_DIR="$PROJECT_DIR/.build-device"
BUNDLE_ID="${BUNDLE_ID:-com.example.CatFace}"
TEAM="${DEVELOPMENT_TEAM:-${1-}}"

if [ -z "$TEAM" ]; then
  # The Team ID is the OU field of the Apple Development certificate.
  TEAM="$(security find-certificate -c "Apple Development" -p 2>/dev/null \
    | openssl x509 -noout -subject 2>/dev/null \
    | sed -E 's/.*OU *= *([A-Z0-9]+).*/\1/' || true)"
fi

if [ -z "$TEAM" ] || [ "${#TEAM}" -ne 10 ]; then
  cat <<'MSG'
Could not find your Apple Development team id.

  1. Open Xcode ▸ Settings ▸ Accounts and sign in with your Apple ID.
  2. Open App/CatFace.xcodeproj, select the CatFace target ▸ Signing &
     Capabilities, and tick "Automatically manage signing", picking your
     name under Team. Xcode creates the certificate at that point.
  3. Re-run this script, or pass the id directly:
       ./scripts/run-device.sh ABCDE12345

Your team id is in Xcode ▸ Settings ▸ Accounts, under the team name.
MSG
  exit 1
fi
echo "==> Team $TEAM"

# Xcode 15+ lists paired physical devices here; connected ones are "available".
UDID="$(xcrun devicectl list devices 2>/dev/null \
  | grep -iE 'available \(paired\)|connected' \
  | grep -oE '[0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{40}' \
  | head -1 || true)"

if [ -z "$UDID" ]; then
  echo "No connected iPhone found. Plug it in, unlock it, and tap Trust."
  echo "Devices visible to Xcode:"
  xcrun devicectl list devices 2>/dev/null || xcrun xctrace list devices
  exit 1
fi
echo "==> Device $UDID"

echo "==> Building"
xcodebuild \
  -project "$PROJECT_DIR/$SCHEME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "id=$UDID" \
  -derivedDataPath "$BUILD_DIR" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  build

APP="$BUILD_DIR/Build/Products/Debug-iphoneos/$SCHEME.app"
[ -d "$APP" ] || { echo "Build succeeded but $APP is missing."; exit 1; }

echo "==> Installing"
xcrun devicectl device install app --device "$UDID" "$APP"

echo "==> Launching"
if ! xcrun devicectl device process launch --device "$UDID" "$BUNDLE_ID"; then
  cat <<MSG

Install worked but launch was refused — on a free Apple ID the certificate is
untrusted until you approve it on the phone:

  Settings ▸ General ▸ VPN & Device Management ▸ your Apple ID ▸ Trust

Then tap the Cat Face icon on the home screen.
MSG
fi
