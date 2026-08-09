#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then set -a; . "$ENV_FILE"; set +a; fi

EDITION="${EDITION:-full}"
case "$EDITION" in
  lite) EDITION_NAME="Lite" ;;
  full) EDITION_NAME="Full" ;;
  *) echo "EDITION must be 'lite' or 'full'." >&2; exit 2 ;;
esac

APP_BUNDLE_NAME="MDViewer+"
VOLUME_NAME="MDViewer+ $EDITION_NAME"
DIST_DIR="${DIST_DIR:-dist}"
APP_PATH="$DIST_DIR/$EDITION/$APP_BUNDLE_NAME.app"
DMG_PATH="${DMG_PATH:-$DIST_DIR/MDViewerPlus-$EDITION_NAME-macos.dmg}"
STAGING_DIR="$DIST_DIR/.dmg-staging-$EDITION"

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found at $APP_PATH" >&2
  exit 1
fi

scripts/audit_bundle.sh "$EDITION" "$APP_PATH"
rm -rf "$STAGING_DIR" "$DMG_PATH" "$DMG_PATH.sha256"
mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_BUNDLE_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"
rm -rf "$STAGING_DIR"

identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' \
      | head -1 \
      | sed 's/.*"\(.*\)"/\1/' || true
  )"
fi
if [[ -n "$identity" ]]; then
  codesign --force --sign "$identity" --timestamp "$DMG_PATH"
  codesign --verify --strict --verbose=2 "$DMG_PATH"
fi
hdiutil verify "$DMG_PATH"
(
  cd "$(dirname "$DMG_PATH")"
  shasum -a 256 "$(basename "$DMG_PATH")" \
    > "$(basename "$DMG_PATH").sha256"
)
echo "DMG created: $DMG_PATH"
