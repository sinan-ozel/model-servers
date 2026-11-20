#!/usr/bin/env bash
set -e

# Downloads the models bundled into the img2vid image:
# - Wan-AI/Wan2.2-TI2V-5B-Diffusers (transformer, UMT5 text encoder,
#   tokenizer, VAE, scheduler; ~34GB)
# - Falconsai/nsfw_image_detection (the safety checker; see src/lib/safety.py)
# Usage: ./download_wan_models.sh

# Both live under hub/ -- the standard HuggingFace cache layout. HF_HOME is
# set to this dir at build time (see Dockerfile.cuda) so the safety checker
# resolves by repo id; the engine globs the Wan snapshot from the same place.
TARGET_DIR="./img2vid/model-cache"
BASE_TARGET="${TARGET_DIR}/hub/models--Wan-AI--Wan2.2-TI2V-5B-Diffusers"
SAFETY_TARGET="${TARGET_DIR}/hub/models--Falconsai--nsfw_image_detection"
mkdir -p "$TARGET_DIR/hub"

if [ -d "$BASE_TARGET/snapshots" ]; then
  echo "Wan 2.2 TI2V-5B already present in $BASE_TARGET, skipping."
else
  echo "Downloading Wan-AI/Wan2.2-TI2V-5B-Diffusers (~34GB)..."
  HF_HOME="$(pwd)/${TARGET_DIR}" python3 -c "
from huggingface_hub import snapshot_download
path = snapshot_download('Wan-AI/Wan2.2-TI2V-5B-Diffusers', max_workers=3)
print(f'Wan 2.2 TI2V-5B at {path}')
"
fi

# ----------------------------------------------------
# Safety checker (same as txt2img -- own copy, each image is self-contained)
# ----------------------------------------------------
if [ -d "$SAFETY_TARGET/snapshots" ]; then
  echo "Safety checker already present in $SAFETY_TARGET, skipping."
else
  echo "Downloading Falconsai/nsfw_image_detection (safety checker)..."
  HF_HOME="$(pwd)/${TARGET_DIR}" python3 -c "
from huggingface_hub import snapshot_download
path = snapshot_download('Falconsai/nsfw_image_detection')
print(f'Safety checker at {path}')
"
fi

echo "Model weights ready in $TARGET_DIR"
