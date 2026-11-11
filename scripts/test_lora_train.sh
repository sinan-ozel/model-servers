#!/usr/bin/env bash
set -e

# Smoke test for the lora-train image: a short training run on the fixture
# dataset, then a check that a missing description.yaml is rejected.
# Usage: ./test_lora_train.sh [steps]
# The fixture is copied to a temp dir, so nothing is written into the repo.

IMAGE_NAME="model-servers/lora-train:zimage-cuda"
FIXTURE_DIR="./lora-train/tests/fixtures"
STEPS="${1:-20}"
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "=== Training ${STEPS} steps on fixture ==="
DATASET="${WORK_DIR}/dataset"
mkdir -p "$DATASET"
cp "$FIXTURE_DIR"/* "$DATASET/"
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "${DATASET}:/data" "$IMAGE_NAME" \
  /data --trigger-word img --steps "$STEPS"

LORA="${DATASET}/output/img.safetensors"
if [ ! -s "$LORA" ]; then
  echo "❌ FAIL: expected LoRA at $LORA"
  exit 1
fi
echo "✓ LoRA written: $(du -h "$LORA" | cut -f1) at $LORA"

echo "=== Missing description.yaml must be rejected ==="
NO_YAML="${WORK_DIR}/no_yaml"
mkdir -p "$NO_YAML"
cp "$FIXTURE_DIR"/id_face.png "$NO_YAML/"
set +e
docker run --rm --gpus all --user "$(id -u):$(id -g)" -v "${NO_YAML}:/data" "$IMAGE_NAME" /data --steps 1 >/dev/null 2>&1
CODE=$?
set -e
if [ "$CODE" -ne 2 ]; then
  echo "❌ FAIL: expected exit 2 for missing description.yaml, got $CODE"
  exit 1
fi
echo "✓ Rejected with exit 2"

echo "✓ All lora-train checks passed"
