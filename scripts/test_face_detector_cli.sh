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

FACE_COUNT=$(jq '.faces | length' "$OUT_DIR/out/detections.json")
echo "Detected faces: $FACE_COUNT"
if [ "$FACE_COUNT" != "$EXPECTED_FACE_COUNT" ]; then
  echo "❌ Expected $EXPECTED_FACE_COUNT face(s), got: $FACE_COUNT"
  exit 1
fi

if [ ! -f "$OUT_DIR/out/face_0.png" ]; then
  echo "❌ CLI did not write face_0.png"
  exit 1
fi

DIMS=$(file "$OUT_DIR/out/face_0.png" | grep -o '[0-9]\+ x [0-9]\+')
echo "Thumbnail dimensions: $DIMS"
if [ "$DIMS" != "256 x 256" ]; then
  echo "❌ Expected 256 x 256 thumbnail, got: $DIMS"
  exit 1
fi

echo "✓ CLI flow OK"
