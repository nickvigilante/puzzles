#!/usr/bin/env bash
# Build, sign, notarize, and package Puzzles.app into a notarized DMG.
# Output: dist/Puzzles-$VERSION.dmg
#
# Required env (one of two notarization auth modes):
#   DEVELOPER_ID_APPLICATION  e.g. 'Developer ID Application: Your Name (TEAMID)'
#   Either:
#     NOTARYTOOL_PROFILE      keychain profile name from `notarytool store-credentials`
#   Or:
#     APPLE_ID, APPLE_TEAM_ID, APPLE_ID_PASSWORD (app-specific password)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
VERSION="${VERSION:-$(date -u +%Y.%m.%d)-${GIT_SHA}}"
export VERSION

: "${DEVELOPER_ID_APPLICATION:?must be set, e.g. 'Developer ID Application: Your Name (TEAMID)'}"

# Build first (sources VERSION from env)
"$REPO_ROOT/build.sh"

APP_DIR="$REPO_ROOT/build/cmake/Puzzles.app"
DIST_DIR="$REPO_ROOT/dist"
DMG_PATH="$DIST_DIR/Puzzles-$VERSION.dmg"
DMG_STAGING="$REPO_ROOT/build/dmg-staging"

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$DIST_DIR"/*.zip

notarytool_auth=()
if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  notarytool_auth=(--keychain-profile "$NOTARYTOOL_PROFILE")
else
  : "${APPLE_ID:?}"; : "${APPLE_TEAM_ID:?}"; : "${APPLE_ID_PASSWORD:?}"
  notarytool_auth=(--apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_ID_PASSWORD")
fi

echo "==> Codesigning Puzzles.app"
codesign --force --deep --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

echo "==> Notarizing app"
APP_ZIP="$DIST_DIR/Puzzles.zip"
ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --wait "${notarytool_auth[@]}"
xcrun stapler staple "$APP_DIR"
rm -f "$APP_ZIP"

echo "==> Building DMG"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$APP_DIR" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname "Simon Tatham's Puzzle Collection" \
  -srcfolder "$DMG_STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

echo "==> Codesigning DMG"
codesign --force --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$DMG_PATH"

echo "==> Notarizing DMG"
xcrun notarytool submit "$DMG_PATH" --wait "${notarytool_auth[@]}"
xcrun stapler staple "$DMG_PATH"

sha=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo
echo "==> Done"
echo "  DMG:     $DMG_PATH"
echo "  Version: $VERSION"
echo "  SHA-256: $sha"
