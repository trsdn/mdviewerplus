#!/usr/bin/env bash
#
# Deterministically rebuilds every vendored web asset that ships inside the
# MDViewer+ app bundle.
#
# The script never runs at application runtime. It installs the pinned
# build-time dependencies from vendor/package-lock.json, emits the shipped
# files into MDViewerPlus/Resources/{Common,Lite,Full}, and regenerates
# vendor/manifest.json plus THIRD-PARTY-NOTICES.md with exact versions,
# licenses, SHA-256 checksums, and edition membership.
#
# Source maps, TypeScript declarations, tests, package-manager state, and
# unrelated modules are never copied into the app bundle.

set -euo pipefail

cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

VENDOR_DIR="$REPO_ROOT/vendor"
RESOURCES_DIR="$REPO_ROOT/MDViewerPlus/Resources"
COMMON_DIR="$RESOURCES_DIR/Common"
LITE_DIR="$RESOURCES_DIR/Lite"
FULL_DIR="$RESOURCES_DIR/Full"
NODE_MODULES="$VENDOR_DIR/node_modules"

ESBUILD_TARGET="safari15"

log() { printf '  %s\n' "$*"; }

require() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Required tool '$1' is not available." >&2
    exit 1
  }
}

require node
require npm
require shasum

echo "==> Installing pinned build-time dependencies"
if [[ -f "$VENDOR_DIR/package-lock.json" ]]; then
  (cd "$VENDOR_DIR" && npm ci --ignore-scripts=false --no-audit --no-fund)
else
  (cd "$VENDOR_DIR" && npm install --no-audit --no-fund)
fi

ESBUILD="$NODE_MODULES/.bin/esbuild"
[[ -x "$ESBUILD" ]] || {
  echo "esbuild was not installed at $ESBUILD" >&2
  exit 1
}

pkg_version() {
  node -p "require('$NODE_MODULES/$1/package.json').version"
}

echo "==> Preparing edition resource directories"
# Keep hand-written assets; only generated third-party files are replaced.
rm -rf "$FULL_DIR/modules" "$VENDOR_DIR/.build"
rm -f \
  "$LITE_DIR/prism-lite.min.js" \
  "$LITE_DIR/PRISM-LICENSE.txt" \
  "$FULL_DIR/HIGHLIGHTJS-LICENSE.txt" \
  "$FULL_DIR/JS-YAML-LICENSE.txt" \
  "$FULL_DIR/MERMAID-LICENSE.txt" \
  "$FULL_DIR/MERMAID-THIRD-PARTY-NOTICES.txt" \
  "$FULL_DIR/SVG-PAN-ZOOM-LICENSE.txt" \
  "$FULL_DIR/module-allowlist.json"
mkdir -p "$COMMON_DIR" "$LITE_DIR" "$FULL_DIR/modules/mermaid"

##############################################################################
# Common edition assets
##############################################################################

echo "==> Building Common assets"

# marked and DOMPurify are already vendored as reviewed minified files and are
# only re-verified here; upstream ships them ready to use.
#
# marked and marked-footnote do not ship their licence text inside the npm
# tarball, so the reviewed copies are kept in the repository and verified here
# instead of being refetched on every run.
for required in \
  marked.min.js \
  dompurify.min.js \
  MARKED-LICENSE.txt \
  MARKED-FOOTNOTE-LICENSE.txt \
  DOMPURIFY-LICENSE.txt
do
  [[ -f "$COMMON_DIR/$required" ]] || {
    echo "Missing pre-vendored Common asset: $required" >&2
    exit 1
  }
done

log "marked-footnote.min.js"
"$ESBUILD" "$VENDOR_DIR/entries/marked-footnote.mjs" \
  --bundle --format=iife --minify --target="$ESBUILD_TARGET" \
  --legal-comments=none --log-level=warning \
  --outfile="$COMMON_DIR/marked-footnote.min.js"

##############################################################################
# Lite edition assets
##############################################################################

echo "==> Building Lite assets"

# Custom Prism build: core plus exactly the supported languages, concatenated
# in dependency order. No plugins, no autoloader, no theme CSS.
PRISM_COMPONENTS=(
  prism-core
  prism-markup
  prism-css
  prism-clike
  prism-javascript
  prism-typescript
  prism-json
  prism-bash
  prism-python
  prism-rust
  prism-swift
)

mkdir -p "$VENDOR_DIR/.build"
PRISM_SOURCE="$VENDOR_DIR/.build/prism-source.js"
trap 'rm -rf "$VENDOR_DIR/.build"' EXIT

{
  printf '/* Custom Prism %s build: core + markup, css, clike, javascript, typescript, json, bash, python, rust, swift. MIT licensed, see PRISM-LICENSE.txt. */\n' \
    "$(pkg_version prismjs)"
  printf 'var _self = _self || {};\n'
  printf '_self.Prism = { manual: true, disableWorkerMessageHandler: true };\n'
  for component in "${PRISM_COMPONENTS[@]}"; do
    source_file="$NODE_MODULES/prismjs/components/${component}.min.js"
    [[ -f "$source_file" ]] || {
      echo "Missing Prism component: $source_file" >&2
      exit 1
    }
    cat "$source_file"
    printf '\n'
  done
  printf 'globalThis.Prism = _self.Prism;\n'
} > "$PRISM_SOURCE"

log "prism-lite.min.js"
"$ESBUILD" "$PRISM_SOURCE" \
  --minify --target="$ESBUILD_TARGET" --legal-comments=none \
  --log-level=warning --outfile="$LITE_DIR/prism-lite.min.js"

cp "$NODE_MODULES/prismjs/LICENSE" "$LITE_DIR/PRISM-LICENSE.txt"

##############################################################################
# Full edition assets
##############################################################################

echo "==> Building Full assets"

log "modules/highlight.esm.min.mjs"
"$ESBUILD" "$VENDOR_DIR/entries/highlight.mjs" \
  --bundle --format=esm --minify --target="$ESBUILD_TARGET" \
  --legal-comments=none --log-level=warning \
  --outfile="$FULL_DIR/modules/highlight.esm.min.mjs"

log "modules/js-yaml.esm.min.mjs"
"$ESBUILD" "$VENDOR_DIR/entries/js-yaml.mjs" \
  --bundle --format=esm --minify --target="$ESBUILD_TARGET" \
  --legal-comments=none --log-level=warning \
  --outfile="$FULL_DIR/modules/js-yaml.esm.min.mjs"

log "modules/svg-pan-zoom.esm.min.mjs"
"$ESBUILD" "$VENDOR_DIR/entries/svg-pan-zoom.mjs" \
  --bundle --format=esm --minify --target="$ESBUILD_TARGET" \
  --legal-comments=none --log-level=warning \
  --outfile="$FULL_DIR/modules/svg-pan-zoom.esm.min.mjs"

# Mermaid ships an official modular ESM distribution. The entry plus every
# diagram chunk is copied verbatim so all diagram families work offline. Source
# maps, the multi-megabyte IIFE bundles, unminified builds, type declarations,
# docs, and mocks are deliberately excluded.
log "modules/mermaid (official modular ESM distribution)"
MERMAID_DIST="$NODE_MODULES/mermaid/dist"
[[ -f "$MERMAID_DIST/mermaid.esm.min.mjs" ]] || {
  echo "Mermaid ESM entry not found in $MERMAID_DIST" >&2
  exit 1
}
mkdir -p "$FULL_DIR/modules/mermaid/chunks/mermaid.esm.min"
cp "$MERMAID_DIST/mermaid.esm.min.mjs" "$FULL_DIR/modules/mermaid/mermaid.esm.min.mjs"
find "$MERMAID_DIST/chunks/mermaid.esm.min" -type f -name '*.mjs' ! -name '*.map' \
  -exec cp {} "$FULL_DIR/modules/mermaid/chunks/mermaid.esm.min/" \;

cp "$NODE_MODULES/highlight.js/LICENSE" "$FULL_DIR/HIGHLIGHTJS-LICENSE.txt"
cp "$NODE_MODULES/js-yaml/LICENSE" "$FULL_DIR/JS-YAML-LICENSE.txt"
cp "$NODE_MODULES/svg-pan-zoom/LICENSE" "$FULL_DIR/SVG-PAN-ZOOM-LICENSE.txt"
cp "$NODE_MODULES/mermaid/LICENSE" "$FULL_DIR/MERMAID-LICENSE.txt"
node "$VENDOR_DIR/write_mermaid_notices.mjs" \
  --node-modules "$NODE_MODULES" \
  --output "$FULL_DIR/MERMAID-THIRD-PARTY-NOTICES.txt"

##############################################################################
# Guard rails
##############################################################################

echo "==> Verifying that excluded artifacts were not copied"
if find "$COMMON_DIR" "$LITE_DIR" "$FULL_DIR" \
  \( -name '*.map' -o -name '*.d.ts' -o -name '*.spec.*' -o -name 'package.json' \
     -o -name '*.tgz' -o -name 'node_modules' \) -print -quit | grep -q .; then
  echo "Excluded artifacts were copied into the shipped resources." >&2
  find "$COMMON_DIR" "$LITE_DIR" "$FULL_DIR" \
    \( -name '*.map' -o -name '*.d.ts' -o -name '*.spec.*' -o -name 'package.json' \) >&2
  exit 1
fi

##############################################################################
# Manifests and notices
##############################################################################

echo "==> Writing module allowlist, manifest, and notices"
node "$VENDOR_DIR/write_manifests.mjs" \
  --repo "$REPO_ROOT" \
  --marked-version "15.0.7" \
  --dompurify-version "3.4.12" \
  --marked-footnote-version "$(pkg_version marked-footnote)" \
  --prism-version "$(pkg_version prismjs)" \
  --highlight-version "$(pkg_version highlight.js)" \
  --js-yaml-version "$(pkg_version js-yaml)" \
  --svg-pan-zoom-version "$(pkg_version svg-pan-zoom)" \
  --mermaid-version "$(pkg_version mermaid)" \
  --esbuild-version "$(pkg_version esbuild)"

echo "==> Done"
