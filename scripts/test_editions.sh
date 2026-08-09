#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
xcodegen generate --spec project.yml
scripts/audit_sources.sh

for edition in Lite Full; do
  lower="$(tr '[:upper:]' '[:lower:]' <<< "$edition")"
  xcodebuild \
    -quiet \
    -project MDViewerPlus.xcodeproj \
    -scheme "MDViewerPlus-$edition" \
    -configuration Debug \
    -derivedDataPath ".build/tests-$lower" \
    CODE_SIGNING_ALLOWED=NO \
    test
done
