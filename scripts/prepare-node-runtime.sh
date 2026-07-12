#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:-}"

if [[ -z "$DESTINATION" ]]; then
  echo "Usage: $0 <destination-node-path>" >&2
  exit 64
fi

# shellcheck disable=SC1091
source "$ROOT_DIR/release/node-runtime.env"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/typeless-node-runtime.XXXXXX")"
cleanup() {
  rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

verify_runtime() {
  local runtime="$1"
  local description
  description="$(file "$runtime")"
  if [[ "$description" != *"Mach-O"* || "$description" != *"arm64"* ]]; then
    echo "Node runtime must be a Mach-O arm64 executable: $description" >&2
    return 1
  fi
  if [[ "$($runtime --version)" != "$NODE_VERSION" ]]; then
    echo "Node runtime version must be $NODE_VERSION" >&2
    return 1
  fi
}

if [[ -n "${NODE_RUNTIME_PATH:-}" ]]; then
  if [[ ! -x "$NODE_RUNTIME_PATH" ]]; then
    echo "NODE_RUNTIME_PATH is not executable: $NODE_RUNTIME_PATH" >&2
    exit 65
  fi
  SOURCE_NODE="$NODE_RUNTIME_PATH"
else
  ARCHIVE_PATH="$TEMP_DIR/$NODE_ARCHIVE"
  curl --fail --location --show-error --output "$ARCHIVE_PATH" "$NODE_RUNTIME_URL"
  cp "$ROOT_DIR/release/node-sha256.txt" "$TEMP_DIR/node-sha256.txt"
  (
    cd "$TEMP_DIR"
    shasum -a 256 -c node-sha256.txt
  )
  tar -xzf "$ARCHIVE_PATH" -C "$TEMP_DIR" "${NODE_ARCHIVE%.tar.gz}/bin/node"
  SOURCE_NODE="$TEMP_DIR/${NODE_ARCHIVE%.tar.gz}/bin/node"
fi

verify_runtime "$SOURCE_NODE"
mkdir -p "$(dirname "$DESTINATION")"
install -m 0755 "$SOURCE_NODE" "$TEMP_DIR/node"
verify_runtime "$TEMP_DIR/node"
mv -f "$TEMP_DIR/node" "$DESTINATION"
printf 'Prepared Node %s at %s\n' "$NODE_VERSION" "$DESTINATION"
