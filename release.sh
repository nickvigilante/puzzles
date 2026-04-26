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
if [[ -z "${VERSION:-}" ]]; then
  if ! git -C "$REPO_ROOT" rev-parse --verify upstream/main >/dev/null 2>&1; then
    echo "error: upstream/main ref not found. add the upstream remote and fetch:" >&2
    echo "  git remote add upstream https://git.tartarus.org/simon/puzzles.git" >&2
    echo "  git fetch upstream" >&2
    exit 1
  fi
  upstream_base=$(git -C "$REPO_ROOT" merge-base HEAD upstream/main)
  upstream_date=$(git -C "$REPO_ROOT" log -1 --format=%cd --date=format:%Y%m%d "$upstream_base")
  patch_count=$(git -C "$REPO_ROOT" rev-list --count "$upstream_base..HEAD")
  VERSION="0.${upstream_date}.${patch_count}"
fi
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

# Submit an artifact to notarization and poll until accepted, rejected, or
# the deadline elapses. Survives transient `notarytool info` failures, which
# `notarytool submit --wait` does not — a single network blip during a
# multi-hour Apple stall killed our first release attempt.
NOTARIZE_TIMEOUT="${NOTARIZE_TIMEOUT:-3600}"
notarize() {
  local artifact="$1" kind="$2"

  echo "==> Submitting $kind for notarization"
  local submit_out submission_id
  submit_out=$(xcrun notarytool submit "$artifact" "${notarytool_auth[@]}" 2>&1) || {
    echo "$submit_out" >&2
    return 1
  }
  echo "$submit_out"
  submission_id=$(echo "$submit_out" | sed -n 's/^  id: //p' | head -1)
  if [[ -z "$submission_id" ]]; then
    echo "error: could not extract submission id from notarytool output" >&2
    return 1
  fi

  echo "==> Polling notarization (id: $submission_id, timeout: ${NOTARIZE_TIMEOUT}s)"
  local deadline=$(( $(date +%s) + NOTARIZE_TIMEOUT ))
  local status info_out
  while (( $(date +%s) < deadline )); do
    if info_out=$(xcrun notarytool info "$submission_id" "${notarytool_auth[@]}" 2>&1); then
      status=$(echo "$info_out" | sed -n 's/^  status: //p' | head -1)
      case "$status" in
        Accepted)
          echo "  status: Accepted"
          return 0
          ;;
        Invalid|Rejected)
          echo "  status: $status — fetching log"
          xcrun notarytool log "$submission_id" "${notarytool_auth[@]}" || true
          return 1
          ;;
        "")
          echo "  (could not parse status, retrying)"
          ;;
        *)
          echo "  status: $status"
          ;;
      esac
    else
      echo "  notarytool info failed (transient, retrying)"
    fi
    sleep 30
  done

  echo "error: notarization timed out after ${NOTARIZE_TIMEOUT}s (id: $submission_id)" >&2
  echo "       resume manually with: xcrun notarytool info $submission_id ..." >&2
  return 1
}

echo "==> Codesigning Puzzles.app"
codesign --force --deep --options runtime --timestamp \
  --sign "$DEVELOPER_ID_APPLICATION" "$APP_DIR"
codesign --verify --strict --verbose=2 "$APP_DIR"

APP_ZIP="$DIST_DIR/Puzzles.zip"
ditto -c -k --keepParent "$APP_DIR" "$APP_ZIP"
notarize "$APP_ZIP" "app"
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

notarize "$DMG_PATH" "DMG"
xcrun stapler staple "$DMG_PATH"

sha=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo
echo "==> Done"
echo "  DMG:     $DMG_PATH"
echo "  Version: $VERSION"
echo "  SHA-256: $sha"
