#!/usr/bin/env bash
set -e

# Tests the safety-checker refusal wiring for the CLI, using
# SAFETY_CHECKER=always_refuse (see img2vid/src/lib/safety.py) instead of a
# real flagged video: this deliberately does NOT try to generate or store
# actual NSFW content just to test plumbing. Same contract as
# scripts/test_txt2img_safety.sh: exit code 2, a "Refused:" line, no output.

IMAGE_NAME="model-servers/img2vid:wan22-ti2v-5b-cuda"
FIXTURE="./img2vid/tests/fixtures/start_frame.png"

echo "=== CLI: expect exit code 2 and a 'Refused:' message ==="
OUT_DIR="$(mktemp -d)"
trap 'rm -rf "$OUT_DIR"' EXIT
cp "$FIXTURE" "$OUT_DIR/aaa.png"
set +e
docker run --rm --gpus all --network none --user "$(id -u):$(id -g)" \
  -e SAFETY_CHECKER=always_refuse \
  -v "$OUT_DIR:/data" \
  "$IMAGE_NAME" generate \
    --input /data/aaa.png --prompt "she smiles" \
    --height 256 --frames 9 --steps 2 2>"$OUT_DIR/stderr.txt"
CLI_EXIT=$?
set -e
if [ "$CLI_EXIT" -ne 2 ]; then
  echo "❌ Expected exit code 2, got: $CLI_EXIT"
  cat "$OUT_DIR/stderr.txt"
  exit 1
fi
if ! grep -q "^Refused:" "$OUT_DIR/stderr.txt"; then
  echo "❌ Expected a 'Refused:' line on stderr:"
  cat "$OUT_DIR/stderr.txt"
  exit 1
fi
if [ -f "$OUT_DIR/aaa.mp4" ]; then
  echo "❌ Refused content should not have been written to disk"
  exit 1
fi
echo "✓ CLI refusal OK"
