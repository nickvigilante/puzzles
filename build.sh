#!/usr/bin/env bash
# Build a versioned (but unsigned) Puzzles.app from pinned upstream source.
# Output: build/cmake/Puzzles.app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UPSTREAM_URL="${UPSTREAM_URL:-https://git.tartarus.org/simon/puzzles.git}"
UPSTREAM_PIN="$(tr -d '[:space:]' < "$REPO_ROOT/UPSTREAM_PIN")"
WORK_DIR="$REPO_ROOT/build"
SRC_DIR="$WORK_DIR/upstream"
BUILD_DIR="$WORK_DIR/cmake"

VERSION="${VERSION:-$(date -u +%Y.%m.%d)-${UPSTREAM_PIN:0:7}}"

if ! command -v halibut >/dev/null 2>&1; then
  echo "error: halibut not found. install with: brew install halibut" >&2
  exit 1
fi

rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

echo "==> Cloning upstream"
git clone --quiet "$UPSTREAM_URL" "$SRC_DIR"
echo "==> Checking out pin: $UPSTREAM_PIN"
git -C "$SRC_DIR" checkout --quiet "$UPSTREAM_PIN"

echo "==> Stamping version: $VERSION"
sed -i '' "s/Unidentified build/$VERSION/g" "$SRC_DIR/osx/Info.plist"

echo "==> Configuring CMake (Release)"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE=Release -Wno-dev

echo "==> Building Puzzles.app"
cmake --build "$BUILD_DIR" -j "$(sysctl -n hw.ncpu)" --target puzzles osx_help

echo
echo "==> Build complete"
echo "  App:     $BUILD_DIR/Puzzles.app"
echo "  Version: $VERSION"
