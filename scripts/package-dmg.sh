#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/Typeless Switch.app"
README_PATH="$ROOT_DIR/release/README-FIRST.txt"
STAGING="$ROOT_DIR/build/dmg-staging"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "DMG packaging requires Apple Silicon (arm64)." >&2
  exit 70
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Build the application first: scripts/build-release.sh" >&2
  exit 66
fi
if ! codesign --verify --deep --strict "$APP_PATH"; then
  echo "Application signature verification failed." >&2
  exit 65
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
DMG_NAME="Typeless-Switch-${VERSION}-arm64.dmg"
DMG_PATH="$ROOT_DIR/dist/$DMG_NAME"

rm -rf "$STAGING"
mkdir -p "$STAGING"
ditto "$APP_PATH" "$STAGING/Typeless Switch.app"
ln -s /Applications "$STAGING/Applications"
install -m 0644 "$README_PATH" "$STAGING/README-FIRST.txt"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"

hdiutil create \
  -volname "Typeless Switch" \
  -srcfolder "$STAGING" \
  -format UDZO \
  -ov \
  "$DMG_PATH"

(
  cd "$ROOT_DIR/dist"
  shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)
printf 'Created %s\n' "$DMG_PATH"
printf 'Checksum: %s.sha256\n' "$DMG_PATH"
