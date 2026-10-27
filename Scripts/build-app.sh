#!/bin/bash
# Builds build/ScreenJot.app (universal, release).
# Env: CODESIGN_IDENTITY="Developer ID Application: ..." to sign with a real certificate
#      (default is ad-hoc). NOTARY_PROFILE=<keychain profile> to notarize after signing.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(tr -d '[:space:]' < VERSION)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
APP=build/ScreenJot.app
ARCH_FLAGS=(--arch arm64 --arch x86_64)

echo "▸ Building ScreenJot $VERSION ($BUILD_NUMBER)"
if ! swift build -c release "${ARCH_FLAGS[@]}" --product ScreenJot 2>&1 | grep -v "ld: warning: search path"; then
    echo "▸ Universal build failed, falling back to native architecture"
    ARCH_FLAGS=()
    swift build -c release --product ScreenJot 2>&1 | grep -v "ld: warning: search path"
fi
BIN="$(swift build -c release "${ARCH_FLAGS[@]}" --product ScreenJot --show-bin-path)/ScreenJot"

echo "▸ Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/ScreenJot"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD_NUMBER/g" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [ ! -f build/AppIcon.icns ]; then
    echo "▸ Rendering icon"
    rm -rf build/AppIcon.iconset
    swift Scripts/make-icon.swift build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

IDENTITY="${CODESIGN_IDENTITY:--}"
echo "▸ Signing with identity: $IDENTITY"
if [ "$IDENTITY" = "-" ]; then
    codesign --force --deep --sign - --identifier app.screenjot.ScreenJot "$APP"
else
    codesign --force --deep --options runtime --timestamp --sign "$IDENTITY" --identifier app.screenjot.ScreenJot "$APP"
fi
codesign --verify --verbose=1 "$APP"

if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo "▸ Notarizing"
    ditto -c -k --keepParent "$APP" build/ScreenJot-notarize.zip
    xcrun notarytool submit build/ScreenJot-notarize.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    rm -f build/ScreenJot-notarize.zip
fi

lipo -info "$APP/Contents/MacOS/ScreenJot" || true
echo "✓ $APP"
