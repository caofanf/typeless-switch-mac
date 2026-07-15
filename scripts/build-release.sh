#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="$ROOT_DIR/build/DerivedData"
SIDECAR_STAGE="$ROOT_DIR/build/Sidecar"
BUILT_APP="$DERIVED_DATA/Build/Products/$CONFIGURATION/Typeless Switch.app"
DIST_APP="$ROOT_DIR/dist/Typeless Switch.app"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "This build requires Apple Silicon (arm64)." >&2
  exit 70
fi
XCODE_VERSION="$(xcodebuild -version 2>/dev/null || true)"
if [[ "$XCODE_VERSION" != Xcode\ * ]]; then
  echo "A complete Xcode installation is required." >&2
  exit 69
fi

rm -rf "$SIDECAR_STAGE"
mkdir -p "$SIDECAR_STAGE"
"$ROOT_DIR/scripts/prepare-sidecar.sh" "$SIDECAR_STAGE"
"$ROOT_DIR/scripts/prepare-node-runtime.sh" "$SIDECAR_STAGE/node"

xcodebuild \
  -project "$ROOT_DIR/macOS/TypelessSwitch.xcodeproj" \
  -scheme TypelessSwitch \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$BUILT_APP" ]]; then
  echo "Built application not found: $BUILT_APP" >&2
  exit 66
fi

mkdir -p "$ROOT_DIR/dist"
rm -rf "$DIST_APP"
ditto "$BUILT_APP" "$DIST_APP"
mkdir -p "$DIST_APP/Contents/Resources"
ditto "$SIDECAR_STAGE" "$DIST_APP/Contents/Resources/Sidecar"
install -m 0644 "$ROOT_DIR/release/THIRD_PARTY_NOTICES.md" \
  "$DIST_APP/Contents/Resources/THIRD_PARTY_NOTICES.md"

NODE_HELPER="$DIST_APP/Contents/Resources/Sidecar/node"
codesign --force --sign - --timestamp=none "$NODE_HELPER"
codesign --force --sign - --timestamp=none \
  --entitlements "$ROOT_DIR/macOS/TypelessSwitch/TypelessSwitch.entitlements" \
  "$DIST_APP"
codesign --verify --deep --strict --verbose=2 "$DIST_APP"

printf 'Built and ad-hoc signed %s app at %s\n' "$CONFIGURATION" "$DIST_APP"
