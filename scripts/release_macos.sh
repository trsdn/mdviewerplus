#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then set -a; . "$ENV_FILE"; set +a; fi

for edition in lite full; do
  EDITION="$edition" scripts/build_release.sh
  EDITION="$edition" scripts/make_dmg.sh

  name="$(tr '[:lower:]' '[:upper:]' <<< "${edition:0:1}")${edition:1}"
  dmg="dist/MDViewerPlus-$name-macos.dmg"
  if [[ -n "${NOTARY_PROFILE:-}" \
        || ( -n "${APPLE_ID:-}" \
          && -n "${APPLE_TEAM_ID:-}" \
          && -n "${APPLE_APP_PASSWORD:-}" ) ]]; then
    DMG_PATH="$dmg" scripts/notarize_dmg.sh
  else
    echo "Skipping notarization for $name because credentials are not set."
  fi
done

echo "Lite and Full release artifacts are ready in dist/."
