#!/bin/bash
#
# Assemble a flashable Magisk module from blobs/ + variants/<name>/.
#
#   ./build.sh gles      # r38p1 driver only, SurfaceFlinger stays on GLES
#   ./build.sh vulkan    # r38p1 driver + Vulkan ICD + 1.3 feature declaration
#
set -e

VARIANT="${1:-gles}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="$ROOT/variants/$VARIANT"
OUT="$ROOT/out"

[ -d "$SRC" ] || { echo "unknown variant: $VARIANT (have: $(ls "$ROOT/variants" | tr '\n' ' '))"; exit 1; }

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

# Shared driver blobs.
mkdir -p "$STAGE/system"
cp -a "$ROOT/blobs/vendor" "$STAGE/system/vendor"

# Variant specific extras (ICD + feature declaration for the vulkan one).
if [ -d "$SRC/extra" ]; then
	cp -a "$SRC/extra/." "$STAGE/system/"
fi

cp "$SRC/module.prop" "$SRC/system.prop" "$STAGE/"
if [ -f "$SRC/customize.sh" ]; then
	cp "$SRC/customize.sh" "$STAGE/"
else
	cp "$ROOT/common/customize.sh" "$STAGE/"
fi
cp -a "$ROOT/common/META-INF" "$STAGE/"

# Deterministic permissions: only the script needs +x.
find "$STAGE" -type f -exec chmod 0644 {} +
chmod 0755 "$STAGE/customize.sh" "$STAGE/META-INF/com/google/android/update-binary"

ID=$(sed -n 's/^id=//p' "$STAGE/module.prop")
VER=$(sed -n 's/^version=//p' "$STAGE/module.prop")

mkdir -p "$OUT"
ZIP="$OUT/${ID}-${VER}.zip"
rm -f "$ZIP"
( cd "$STAGE" && zip -r -9 -q "$ZIP" . -x '.*' )

echo "built $ZIP"
sha256sum "$ZIP"
