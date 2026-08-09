#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

ENV_FILE="${RELEASE_ENV_FILE:-.release.env}"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  . "$ENV_FILE"
  set +a
fi

EDITION="${EDITION:-full}"
case "$EDITION" in
  lite) SCHEME="MDViewerPlus-Lite"; EDITION_NAME="Lite" ;;
  full) SCHEME="MDViewerPlus-Full"; EDITION_NAME="Full" ;;
  *) echo "EDITION must be 'lite' or 'full'." >&2; exit 2 ;;
esac

APP_BUNDLE_NAME="MDViewer+"
PROJECT="MDViewerPlus.xcodeproj"
BUILD_ROOT="${BUILD_ROOT:-release-build/$EDITION}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
DIST_DIR="${DIST_DIR:-dist}"
DIST_EDITION_DIR="$DIST_DIR/$EDITION"
DIST_APP="$DIST_EDITION_DIR/$APP_BUNDLE_NAME.app"
REQUIRE_SIGNING="${REQUIRE_SIGNING:-1}"

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate --spec project.yml
fi

identity="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$identity" ]]; then
  identity="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | grep 'Developer ID Application' \
      | head -1 \
      | sed 's/.*"\(.*\)"/\1/' || true
  )"
fi
if [[ "$REQUIRE_SIGNING" == "1" && -z "$identity" ]]; then
  echo "No Developer ID Application signing identity found." >&2
  exit 1
fi

rm -rf "$BUILD_ROOT" "$DIST_EDITION_DIR"
mkdir -p "$DIST_EDITION_DIR"

settings=(
  ENABLE_HARDENED_RUNTIME=YES
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
)
if [[ -n "$identity" ]]; then
  settings+=(
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$identity"
    OTHER_CODE_SIGN_FLAGS="--timestamp"
  )
  if [[ -n "${TEAM_ID:-}" ]]; then
    settings+=(DEVELOPMENT_TEAM="$TEAM_ID")
  fi
else
  settings+=(CODE_SIGNING_ALLOWED=NO)
fi

xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  clean build \
  "${settings[@]}"

built_app="$DERIVED_DATA/Build/Products/Release/$APP_BUNDLE_NAME.app"
if [[ ! -d "$built_app" ]]; then
  echo "Build succeeded, but $built_app was not produced." >&2
  exit 1
fi
ditto "$built_app" "$DIST_APP"
if [[ -n "$identity" ]]; then
  codesign --verify --strict --deep --verbose=2 "$DIST_APP"
fi

scripts/audit_bundle.sh "$EDITION" "$DIST_APP"
echo "$EDITION_NAME app bundle created: $DIST_APP"
