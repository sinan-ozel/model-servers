#!/usr/bin/env bash
set -e

# Tests the CLI flow in isolation: `docker run <image> detect --file ... --output-dir ...`.

IMAGE_NAME="model-servers/face-detector:yunet-cpu"
EXPECTED_FACE_COUNT=1
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

cp face-detector/tests/fixtures/faces.png "$OUT_DIR/faces.png"

echo "Running CLI detect..."
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$OUT_DIR:/data" \
  "$IMAGE_NAME" detect --file /data/faces.png --output-dir /data/out --score-threshold 0.5

if [ ! -f "$OUT_DIR/out/detections.json" ]; then
  echo "❌ CLI did not produce detections.json"
  exit 1
fi

FACE_COUNT=$(jq '.files[0].faces | length' "$OUT_DIR/out/detections.json")
echo "Detected faces: $FACE_COUNT"
if [ "$FACE_COUNT" != "$EXPECTED_FACE_COUNT" ]; then
  echo "❌ Expected $EXPECTED_FACE_COUNT face(s), got: $FACE_COUNT"
  exit 1
fi

# Thumbnails are named <input-stem>_face_N.png (not face_N.png) so repeated
# runs against the same --output-dir, or a wildcard --file covering several
# photos, never overwrite a previous photo's thumbnails.
if [ ! -f "$OUT_DIR/out/faces_face_0.png" ]; then
  echo "❌ CLI did not write faces_face_0.png"
  exit 1
fi

DIMS=$(file "$OUT_DIR/out/faces_face_0.png" | grep -o '[0-9]\+ x [0-9]\+')
echo "Thumbnail dimensions: $DIMS"
if [ "$DIMS" != "256 x 256" ]; then
  echo "❌ Expected 256 x 256 thumbnail, got: $DIMS"
  exit 1
fi

echo "✓ CLI flow OK"

echo ""
echo "=== Wildcard --file: process multiple photos in one invocation ==="
cp face-detector/tests/fixtures/faces.png "$OUT_DIR/faces2.png"
rm -rf "$OUT_DIR/out2"
docker run --rm \
  --user "$(id -u):$(id -g)" \
  -v "$OUT_DIR:/data" \
  "$IMAGE_NAME" detect --file '/data/faces*.png' --output-dir /data/out2 --score-threshold 0.5

FILE_COUNT=$(jq '.files | length' "$OUT_DIR/out2/detections.json")
if [ "$FILE_COUNT" != "2" ]; then
  echo "❌ Expected 2 files processed via wildcard, got: $FILE_COUNT"
  exit 1
fi
if [ ! -f "$OUT_DIR/out2/faces_face_0.png" ] || [ ! -f "$OUT_DIR/out2/faces2_face_0.png" ]; then
  echo "❌ Expected both faces_face_0.png and faces2_face_0.png, per-source filenames"
  ls "$OUT_DIR/out2"
  exit 1
fi
echo "✓ Wildcard --file OK"
