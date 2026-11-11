#!/usr/bin/env bash
set -e

# Smoke test for lora-gen: plain generation (no LoRA, same as txt2img),
# then generation with a throwaway LoRA trained via lora-train's own
# fixture. Everything happens in a temp dir -- nothing is written into the repo.
# Usage: ./test_lora_gen_cli.sh

IMAGE_NAME="model-servers/lora-gen:zimage-cuda"
TRAIN_IMAGE="model-servers/lora-train:zimage-cuda"
FIXTURE_DIR="./lora-train/tests/fixtures"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Plain generation (no LoRA) ==="
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "${WORK_DIR}:/data" "$IMAGE_NAME" \
  generate --prompt "three cute cats playing" --steps 8 --output /data/plain.png
if [ ! -s "${WORK_DIR}/plain.png" ]; then
  echo "❌ FAIL: expected ${WORK_DIR}/plain.png"
  exit 1
fi
echo "✓ plain.png written"

echo "=== Training a throwaway LoRA (20 steps) for the --lora test ==="
if ! docker image inspect "$TRAIN_IMAGE" > /dev/null 2>&1; then
  echo "❌ Error: $TRAIN_IMAGE not found -- run scripts/build_lora_train.sh first."
  exit 1
fi
DATASET="${WORK_DIR}/dataset"
mkdir -p "$DATASET"
cp "$FIXTURE_DIR"/* "$DATASET/"
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "${DATASET}:/data" "$TRAIN_IMAGE" \
  /data --trigger-word img --steps 20

LORA="${DATASET}/output/img.safetensors"
if [ ! -s "$LORA" ]; then
  echo "❌ FAIL: expected LoRA at $LORA"
  exit 1
fi

echo "=== Generation with --lora ==="
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "${WORK_DIR}:/data" -v "${DATASET}:/dataset" "$IMAGE_NAME" \
  generate --prompt "a photo of img man, portrait" --steps 8 \
  --lora /dataset/output/img.safetensors --output /data/with_lora.png
if [ ! -s "${WORK_DIR}/with_lora.png" ]; then
  echo "❌ FAIL: expected ${WORK_DIR}/with_lora.png"
  exit 1
fi
echo "✓ with_lora.png written"

echo "✓ All lora-gen checks passed"
