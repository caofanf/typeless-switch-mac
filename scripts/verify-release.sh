#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/dist/Typeless Toolkit.app"
NODE_HELPER="$APP_PATH/Contents/Resources/Sidecar/node"
SIDECAR_MAIN="$APP_PATH/Contents/Resources/Sidecar/sidecar/main.js"
DMG_PATH="${1:-}"

if [[ "$(uname -m)" != "arm64" ]]; then
  echo "Release verification requires Apple Silicon (arm64)." >&2
  exit 70
fi
if [[ ! -d "$APP_PATH" ]]; then
  echo "Application not found: $APP_PATH" >&2
  exit 66
fi

require_arm64() {
  local executable="$1"
  local description
  description="$(file "$executable")"
  if [[ "$description" != *"Mach-O"* || "$description" != *"arm64"* ]]; then
    echo "Expected a Mach-O arm64 executable: $description" >&2
    exit 65
  fi
}

require_arm64 "$APP_PATH/Contents/MacOS/Typeless Toolkit"
require_arm64 "$NODE_HELPER"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if find "$APP_PATH" \
  \( -iname 'accounts.json' -o -iname 'config.json' -o -iname '.env' -o -iname '.env.*' \
     -o -iname 'profiles' -o -iname 'runtime-backups' -o -iname 'patch-backups' \
     -o -iname '*token*.json' \) \
  -print -quit | grep -q .; then
  echo "Sensitive runtime data found in application bundle." >&2
  exit 67
fi

SMOKE_DATA="$(mktemp -d "${TMPDIR:-/tmp}/typeless-release-smoke.XXXXXX")"
MOUNT_POINT=""
cleanup() {
  if [[ -n "$MOUNT_POINT" ]] && mount | grep -Fq "on $MOUNT_POINT "; then
    hdiutil detach "$MOUNT_POINT" >/dev/null || true
  fi
  rm -rf "$SMOKE_DATA"
  if [[ -n "$MOUNT_POINT" ]]; then rm -rf "$MOUNT_POINT"; fi
}
trap cleanup EXIT

SMOKE_OUTPUT="$(printf '%s\n%s\n' \
  '{"jsonrpc":"2.0","id":"hello","method":"core.hello","params":{}}' \
  '{"jsonrpc":"2.0","id":"bye","method":"core.shutdown","params":{}}' | \
  env TYPELESS_DATA_DIR="$SMOKE_DATA" "$NODE_HELPER" "$SIDECAR_MAIN" \
    --transport=stdio --parent-pid=$$)"
if ! printf '%s\n' "$SMOKE_OUTPUT" | grep -q '"protocol_name":"typeless-toolkit-core"'; then
  echo "core.hello smoke test failed." >&2
  exit 68
fi
if ! printf '%s\n' "$SMOKE_OUTPUT" | grep -q '"architecture":"arm64"'; then
  echo "core.hello did not report arm64." >&2
  exit 68
fi

if [[ -z "$DMG_PATH" ]]; then
  shopt -s nullglob
  DMG_FILES=("$ROOT_DIR"/dist/Typeless-Toolkit-*-arm64.dmg)
  shopt -u nullglob
  if [[ "${#DMG_FILES[@]}" -ne 1 ]]; then
    echo "Expected exactly one versioned arm64 DMG; pass its path explicitly." >&2
    exit 66
  fi
  DMG_PATH="${DMG_FILES[0]}"
fi
if [[ ! -f "$DMG_PATH" || ! -f "$DMG_PATH.sha256" ]]; then
  echo "DMG or checksum file missing: $DMG_PATH" >&2
  exit 66
fi
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 -c "$(basename "$DMG_PATH").sha256"
)

MOUNT_POINT="$(mktemp -d "${TMPDIR:-/tmp}/typeless-dmg-mount.XXXXXX")"
hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
if [[ ! -d "$MOUNT_POINT/Typeless Toolkit.app" || ! -L "$MOUNT_POINT/Applications" ]]; then
  echo "DMG does not contain the application and Applications link." >&2
  exit 69
fi
hdiutil detach "$MOUNT_POINT" >/dev/null
rm -rf "$MOUNT_POINT"
MOUNT_POINT=""

if spctl --assess --type execute "$APP_PATH" >/dev/null 2>&1; then
  echo "Gatekeeper assessment passed; this build is still distributed without notarization."
else
  echo "Expected: Gatekeeper assessment rejects the unnotarized ad-hoc build. See release/README-FIRST.txt."
fi
printf 'Release verification passed: %s\n' "$DMG_PATH"
