#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then set -a; . "$ENV_FILE"; set +a; fi
DMG_PATH="${DMG_PATH:-dist/MDViewerPlus-macos.dmg}"
./scripts/build_release.sh
DMG_PATH="$DMG_PATH" ./scripts/make_dmg.sh
if [[ -n "${NOTARY_PROFILE:-}" || ( -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" ) ]]; then
  DMG_PATH="$DMG_PATH" ./scripts/notarize_dmg.sh
else
  echo "Skipping notarization because neither NOTARY_PROFILE nor APPLE_ID, APPLE_TEAM_ID, and APPLE_APP_PASSWORD are set."
fi