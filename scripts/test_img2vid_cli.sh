#!/usr/bin/env bash
set -e

# Tests the CLI flow: an image input, then a video input that continues from
# the first clip's last frame, checking output names and dimensions. Uses a
# small size, frame count and step count to keep the (cold-start) test fast
# while still exercising real GPU inference.
# --network none proves the image is truly self-contained.

IMAGE_NAME="model-servers/img2vid:wan22-ti2v-5b-cuda"
FIXTURE="./img2vid/tests/fixtures/start_frame.png"
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT
cp "$FIXTURE" "$OUT_DIR/aaa.png"

echo "=== Output naming and size rules (no GPU) ==="
docker run --rm --network none --entrypoint python3 "$IMAGE_NAME" -c "
from pathlib import Path
from src.lib.media import derive_output_path as d, resolve_size as r
assert d(Path('/x/aaa.png')) == Path('/x/aaa.mp4')
assert d(Path('/x/aaa.mp4')) == Path('/x/aaa-001.mp4')
assert d(Path('/x/aaa-001.mp4')) == Path('/x/aaa-002.mp4')
assert d(Path('/x/aaa-999.mp4')) == Path('/x/aaa-1000.mp4')
assert r(832, 480, None, 250, False) == (448, 256)
assert r(832, 480, 450, None, False) == (448, 256)
assert r(448, 256, None, None, True) == (448, 256)
assert r(1664, 960, None, None, False) == (832, 480)
"
echo "✓ Naming and size rules OK"

run_generate() {
  docker run --rm --gpus all --network none --user "$(id -u):$(id -g)" \
    -v "$OUT_DIR:/data" \
    "$IMAGE_NAME" generate --frames 9 --steps 3 "$@"
}

check_clip() {
  if [ ! -s "$1" ]; then
    echo "❌ Expected output file $1"
    exit 1
  fi
  DIMS=$(docker run --rm --network none --user "$(id -u):$(id -g)" -v "$OUT_DIR:/data" \
    --entrypoint python3 "$IMAGE_NAME" -c "
import imageio.v3 as iio
f = iio.imread('/data/$(basename "$1")')
print(f'{f.shape[0]} frames {f.shape[2]}x{f.shape[1]}')")
  echo "$(basename "$1"): $DIMS"
  if [ "$DIMS" != "9 frames 448x256" ]; then
    echo "❌ Expected 9 frames 448x256, got: $DIMS"
    exit 1
  fi
}

echo "=== Image input: aaa.png -> aaa.mp4 (height 250 rounds to 256) ==="
run_generate --input /data/aaa.png --prompt "she smiles and turns her head" --height 250
check_clip "$OUT_DIR/aaa.mp4"

echo "=== Video input: aaa.mp4 -> aaa-001.mp4 (last frame, same size) ==="
run_generate --input /data/aaa.mp4 --prompt "she waves at the camera"
check_clip "$OUT_DIR/aaa-001.mp4"

echo "=== Existing output must not be overwritten ==="
set +e
run_generate --input /data/aaa.mp4 --prompt "she waves at the camera" >/dev/null 2>&1
CODE=$?
set -e
if [ "$CODE" -ne 1 ]; then
  echo "❌ Expected exit 1 when the output exists, got $CODE"
  exit 1
fi
echo "✓ Refused to overwrite"

echo "✓ CLI flow OK"
