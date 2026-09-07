#!/usr/bin/env bash
set -e

# Tests the CLI flow in isolation: `docker run <image> generate --prompt ... --output ...`.
# Uses a small size/step count to keep the (cold-start, first-load) test
# fast while still exercising real GPU inference.
# --network none proves the image is truly self-contained: a model file
# fetched over the network instead of from the bundled cache would fail
# loudly here instead of silently passing (see Tongyi-MAI/Z-Image-Turbo's
# transformer/config.json, which has bitten this exact model before).

IMAGE_NAME="model-servers/txt2img:zimage-cuda"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT

echo "Running CLI generate (256x256, steps=4)..."
docker run --rm --gpus all --network none \
  -v "$OUT_DIR:/data" \
  "$IMAGE_NAME" generate \
    --prompt "three cute cats playing" \
    --width 256 --height 256 --steps 4 \
    --output /data/out.png

if [ ! -f "$OUT_DIR/out.png" ]; then
  echo "❌ CLI did not produce an output file"
  exit 1
fi

DIMS=$(file "$OUT_DIR/out.png" | grep -o '[0-9]\+ x [0-9]\+')
echo "Output dimensions: $DIMS"

if [ "$DIMS" != "256 x 256" ]; then
  echo "❌ Expected 256 x 256, got: $DIMS"
  exit 1
fi

echo "✓ CLI flow OK"
