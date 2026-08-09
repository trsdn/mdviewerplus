#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

python3 - vendor/manifest.json MDViewerPlus/Resources <<'PY'
import hashlib
import json
import pathlib
import sys

manifest = json.loads(pathlib.Path(sys.argv[1]).read_text())
resources = pathlib.Path(sys.argv[2])
for entry in manifest["files"]:
    path = resources / entry["path"]
    if not path.is_file():
        raise SystemExit(f"Missing source asset: {entry['path']}")
    actual = hashlib.sha256(path.read_bytes()).hexdigest()
    if actual != entry["sha256"]:
        raise SystemExit(
            f"Source checksum mismatch for {entry['path']}; rerun vendoring"
        )

lite_bytes = manifest["totals"]["lite"]
if lite_bytes > 36 * 1024:
    raise SystemExit(f"Lite vendored assets exceed 36 KiB: {lite_bytes}")
print(
    f"Source asset audit passed: common={manifest['totals']['common']} bytes, "
    f"lite={lite_bytes} bytes, full={manifest['totals']['full']} bytes"
)
PY

if find MDViewerPlus/Resources \
    \( -name '*.map' -o -name '*.d.ts' -o -name 'node_modules' \
       -o -name 'package.json' \) -print -quit | grep -q .; then
  echo "Excluded development files exist in shipped resources." >&2
  exit 1
fi
