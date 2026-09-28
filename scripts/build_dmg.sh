#!/bin/bash
# Builds DuckMD.app (Release) and packages it into a drag-and-drop DMG
# ("DuckMD.dmg") at the repo root.
#
# The DMG contains the app next to an /Applications symlink, styled with
# custom background, icon positioning, and branding.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="DuckMD"
DMG_TITLE="$APP_NAME"
DMG_PATH="$ROOT/$APP_NAME.dmg"
BUILD_DIR="$ROOT/build/DerivedData"
APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
STAGING="$ROOT/build/dmg-staging"
STAGED_APP_PATH="$STAGING/$APP_NAME.app"
SIGN_IDENTITY="Apple Development"

echo "==> Regenerating DMG background and preview mockup…"
swift "$ROOT/scripts/generate_dmg_assets.swift"

echo "==> Regenerating Xcode project with XcodeGen…"
xcodegen generate

echo "==> Building Release configuration…"
xcodebuild build \
    -project "$ROOT/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$BUILD_DIR" \
    -quiet

if [ ! -d "$APP_PATH" ]; then
    echo "ERROR: $APP_PATH not found after build" >&2
    exit 1
fi

echo "==> Cleaning extended attributes (codesign detritus guard)…"
xattr -cr "$APP_PATH" 2>/dev/null || true

echo "==> Preparing drag-and-drop staging folder…"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGED_APP_PATH"

echo "==> Re-signing bundle (Apple Development identity, hardened runtime)…"
xattr -cr "$STAGED_APP_PATH" 2>/dev/null || true
codesign --force --deep --sign "$SIGN_IDENTITY" --entitlements "$ROOT/security/DuckMD.entitlements" --options runtime --timestamp=none "$STAGED_APP_PATH"

echo "==> Verifying signature…"
codesign --verify --deep --strict "$STAGED_APP_PATH" || {
    echo "ERROR: codesign verification failed" >&2
    exit 1
}
codesign -dv "$STAGED_APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier" || true

echo "==> Staged app size:"
du -sh "$STAGED_APP_PATH"

echo "==> Removing stale DMG…"
rm -f "$DMG_PATH"

echo "==> Creating DMG via dmgbuild…"
/opt/anaconda3/bin/dmgbuild -s "$ROOT/dmg_settings.py" \
    -D app="$STAGED_APP_PATH" \
    -D background="$ROOT/dmg_background.png" \
    -D icon="$ROOT/scripts/dmg_assets/icon.icns" \
    "$DMG_TITLE" "$DMG_PATH"

echo "==> Setting custom icon on DMG file…"
swift "$ROOT/scripts/set_dmg_icon.swift" "$DMG_PATH" "$ROOT/scripts/dmg_assets/app_icon.png"

echo "==> Signing DMG disk image…"
codesign --force --sign "$SIGN_IDENTITY" "$DMG_PATH" 2>/dev/null || true

echo "==> Preparing clean dist output in build/dist…"
mkdir -p "$ROOT/build/dist"
cp -R "$STAGED_APP_PATH" "$ROOT/build/dist/DuckMD-0.6.16.app"
cp "$DMG_PATH" "$ROOT/build/dist/DuckMD-0.6.16.dmg"

rm -rf "$STAGING"

echo "==> Done: $DMG_PATH and build/dist/DuckMD-0.6.16.dmg"
ls -lh "$DMG_PATH" "$ROOT/build/dist/DuckMD-0.6.16.dmg"
