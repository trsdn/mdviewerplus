#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

EDITION="${1:-}"
APP_PATH="${2:-}"
case "$EDITION" in lite|full) ;; *)
  echo "Usage: scripts/audit_bundle.sh <lite|full> <app-path>" >&2
  exit 2
esac
if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 2
fi

RESOURCES="$APP_PATH/Contents/Resources"
PLIST="$APP_PATH/Contents/Info.plist"
expected_name="$(tr '[:lower:]' '[:upper:]' <<< "${EDITION:0:1}")${EDITION:1}"

[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")" == "2.0.1" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")" == "9" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :MDViewerEdition' "$PLIST")" == "$EDITION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleGetInfoString' "$PLIST")" == \
    "MDViewer+ $expected_name 2.0.1 (9)" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :NSHumanReadableCopyright' "$PLIST")" == \
    "Copyright © 2026 Torsten Mahr" ]]

if [[ "$EDITION" == "lite" ]]; then
  [[ -d "$RESOURCES/Common" && -d "$RESOURCES/Lite" ]]
  [[ ! -e "$RESOURCES/Full" ]]
  if find "$RESOURCES" -type f \
      \( -iname '*mermaid*' -o -iname '*highlight*' \
         -o -iname '*js-yaml*' -o -iname '*svg-pan-zoom*' \) \
      -print -quit | grep -q .; then
    echo "Lite contains a Full-only asset." >&2
    exit 1
  fi
else
  [[ -d "$RESOURCES/Common" && -d "$RESOURCES/Full" ]]
  [[ ! -e "$RESOURCES/Lite" ]]
  if find "$RESOURCES" -type f -iname '*prism*' -print -quit | grep -q .; then
    echo "Full contains a Lite-only Prism asset." >&2
    exit 1
  fi
fi

if find "$RESOURCES" \
    \( -name '*.map' -o -name '*.d.ts' -o -name 'node_modules' \
       -o -name 'package.json' \) -print -quit | grep -q .; then
  echo "$expected_name contains excluded development files." >&2
  exit 1
fi

python3 - "$EDITION" "$RESOURCES" vendor/manifest.json <<'PY'
import hashlib
import json
import pathlib
import sys

edition, resources, manifest_path = sys.argv[1:]
resources = pathlib.Path(resources)
manifest = json.loads(pathlib.Path(manifest_path).read_text())
allowed = {"common", edition}
for entry in manifest["files"]:
    if entry["edition"] not in allowed:
        continue
    path = resources / entry["path"]
    if not path.is_file():
        raise SystemExit(f"Missing bundled asset: {entry['path']}")
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if digest != entry["sha256"]:
        raise SystemExit(f"Checksum mismatch: {entry['path']}")
PY

echo "$expected_name bundle audit passed."
