#!/usr/bin/env bash
set -e

# Tests the CLI flow in isolation: `docker run <image> upscale --file ... --scale ...`.
# Runs on GPU by default; set UPSCALER_DEVICE=cpu to force CPU (e.g. if the
# GPU is busy or unavailable).

IMAGE_NAME="model-servers/upscaler:realesrgan-cuda"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

cp upscaler/tests/fixtures/sample.png "$OUT_DIR/sample.png"

echo "Running CLI upscale (scale=4)..."
docker run --rm --gpus all \
  -v "$OUT_DIR:/data" \
  "$IMAGE_NAME" upscale --file /data/sample.png --scale 4 --output /data/sample.x4.png

if [ ! -f "$OUT_DIR/sample.x4.png" ]; then
  echo "❌ CLI did not produce an output file"
  exit 1
fi

DIMS=$(file "$OUT_DIR/sample.x4.png" | grep -o '[0-9]\+ x [0-9]\+')
echo "Output dimensions: $DIMS"

if [ "$DIMS" != "256 x 192" ]; then
  echo "❌ Expected 256 x 192 (4x of the 64x48 fixture), got: $DIMS"
  exit 1
fi

echo "✓ CLI flow OK"
