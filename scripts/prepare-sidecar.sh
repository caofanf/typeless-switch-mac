#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DESTINATION="${1:-}"

if [[ -z "$DESTINATION" ]]; then
  echo "Usage: $0 <destination-directory>" >&2
  exit 64
fi

if [[ -e "$DESTINATION" ]] && [[ -n "$(find "$DESTINATION" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  echo "Destination must be empty: $DESTINATION" >&2
  exit 65
fi

mkdir -p "$DESTINATION/sidecar" "$DESTINATION/lib"

SIDECAR_FILES=(
  command-registry.js
  main.js
  protocol.js
)
LIB_FILES=(
  application-service.js
  common.js
  core-errors.js
  operation-confirmations.js
  patch-transaction.js
  public-dto.js
  runtime-data.js
  task-runner.js
)

for file in "${SIDECAR_FILES[@]}"; do
  install -m 0644 "$ROOT_DIR/sidecar/$file" "$DESTINATION/sidecar/$file"
done
for file in "${LIB_FILES[@]}"; do
  install -m 0644 "$ROOT_DIR/lib/$file" "$DESTINATION/lib/$file"
done
install -m 0644 "$ROOT_DIR/LICENSE" "$DESTINATION/LICENSE"

while IFS= read -r -d '' script; do
  node --check "$script" >/dev/null
done < <(find "$DESTINATION" -type f -name '*.js' -print0)

if find "$DESTINATION" \
  \( -name '.git' -o -name '.env' -o -name '.env.*' -o -name 'accounts.json' \
     -o -name 'config.json' -o -name 'profiles' -o -name 'runtime-backups' \
     -o -name 'patch-backups' -o -name '*backup*' \) \
  -print -quit | grep -q .; then
  echo "Refusing to stage sensitive or non-runtime files" >&2
  exit 66
fi

printf 'Prepared sidecar at %s\n' "$DESTINATION"
