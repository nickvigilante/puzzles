#!/usr/bin/env bash
# Build a versioned (but unsigned) Puzzles.app from local source.
# Output: build/cmake/Puzzles.app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_ROOT/build/cmake"

GIT_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
VERSION="${VERSION:-$(date -u +%Y.%m.%d)-${GIT_SHA}}"

if ! command -v halibut >/dev/null 2>&1; then
  echo "error: halibut not found. install with: brew install halibut" >&2
  exit 1
fi

echo "==> Configuring CMake (Release)"
cmake -S "$REPO_ROOT" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -Wno-dev

echo "==> Building Puzzles.app"
cmake --build "$BUILD_DIR" -j "$(sysctl -n hw.ncpu)" --target puzzles osx_help

# Stamp version into the bundle's Info.plist after build, before signing.
# Doing this here (rather than sed-ing the source plist) keeps the working
# tree clean and makes incremental rebuilds idempotent.
echo "==> Stamping version: $VERSION"
sed -i '' "s/Unidentified build/$VERSION/g" "$BUILD_DIR/Puzzles.app/Contents/Info.plist"

echo
echo "==> Build complete"
echo "  App:     $BUILD_DIR/Puzzles.app"
echo "  Version: $VERSION"
