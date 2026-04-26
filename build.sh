#!/usr/bin/env bash
# Build a versioned (but unsigned) Puzzles.app from local source.
# Output: build/cmake/Puzzles.app
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_ROOT/build/cmake"

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
