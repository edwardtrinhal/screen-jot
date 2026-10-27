#!/bin/bash
# Packages build/ScreenJot.app into build/ScreenJot-<version>.dmg. Runs build-app.sh first unless SKIP_BUILD=1.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
APP=build/ScreenJot.app
DMG="build/ScreenJot-$VERSION.dmg"
STAGE=build/dmg-stage

[ "${SKIP_BUILD:-0}" = "1" ] || Scripts/build-app.sh

echo "▸ Staging"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cp Scripts/dmg-readme.txt "$STAGE/READ ME - first launch.txt"

echo "▸ Creating DMG"
hdiutil create -volname "ScreenJot $VERSION" -srcfolder "$STAGE" -ov -format UDZO -quiet "$DMG"
rm -rf "$STAGE"
ls -lh "$DMG"
echo "✓ $DMG"
