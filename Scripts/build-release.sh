#!/bin/bash
# Builds Drafter.app in Release configuration, ad-hoc codesigns it, and zips it for
# distribution (local use or a GitHub Release attachment). No Apple Developer account
# needed — ad-hoc signing is the same signature required just to run any arm64 binary.
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --always 2>/dev/null || echo dev)}"
BUILD_DIR="build"
DERIVED_DATA="$BUILD_DIR/DerivedData"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building Drafter.app (Release, version $VERSION)"
xcodebuild \
  -project Drafter.xcodeproj \
  -scheme Drafter \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  MARKETING_VERSION="$VERSION" \
  build

APP_SRC="$DERIVED_DATA/Build/Products/Release/Drafter.app"
APP_DST="$BUILD_DIR/Drafter.app"
cp -R "$APP_SRC" "$APP_DST"

echo "==> Ad-hoc codesigning"
codesign --force --deep --sign - "$APP_DST"
codesign -dv "$APP_DST"

ZIP_NAME="Drafter-${VERSION}-macOS.zip"
echo "==> Zipping to $BUILD_DIR/$ZIP_NAME"
(cd "$BUILD_DIR" && ditto -c -k --sequesterRsrc --keepParent Drafter.app "$ZIP_NAME")

echo "==> Done: $BUILD_DIR/$ZIP_NAME"
