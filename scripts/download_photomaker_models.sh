#!/usr/bin/env bash
set -e

# Downloads the models bundled into the faceid image:
# - stabilityai/stable-diffusion-xl-base-1.0 (text encoders, VAE, tokenizers,
#   scheduler, AND unet -- all fp16 variant; the UNet is loaded at runtime
#   via bitsandbytes 8-bit quantization, not GGUF: diffusers' GGUF support
#   does not cover UNet2DConditionModel/SDXL, confirmed against diffusers'
#   own GGUF conversion tool's supported-architecture list and by
#   reproducing a tensor-shape error against two third-party SDXL GGUF
#   conversions. See faceid/src/lib/engine.py's module docstring.)
# - TencentARC/PhotoMaker (photomaker-v1.bin -- V1 weights only)
# - Falconsai/nsfw_image_detection (the safety checker; see src/lib/safety.py)
# Usage: ./download_photomaker_models.sh

TARGET_DIR="./faceid/model-cache"
BASE_TARGET="${TARGET_DIR}/hub/models--stabilityai--stable-diffusion-xl-base-1.0"
PHOTOMAKER_TARGET="${TARGET_DIR}/photomaker-v1.bin"
SAFETY_TARGET="${TARGET_DIR}/hub/models--Falconsai--nsfw_image_detection"
mkdir -p "$TARGET_DIR/hub"

if [ -d "$BASE_TARGET/snapshots" ] && [ -f "$PHOTOMAKER_TARGET" ]; then
  echo "Already present in $TARGET_DIR, skipping download."
else
  echo "Downloading SDXL base components (text encoders/VAE/tokenizers/scheduler/unet, fp16)..."
  python3 - <<'PYEOF'
from huggingface_hub import snapshot_download

path = snapshot_download(
    repo_id="stabilityai/stable-diffusion-xl-base-1.0",
    # SDXL's repo ships each component in several formats (PyTorch
    # safetensors, Flax msgpack, ONNX, OpenVINO) -- a bare "unet/*" wildcard
    # pulls ALL of them (~36GB total for the full repo this way). Pin to
    # just the fp16 safetensors variant + small config/tokenizer files we
    # actually load.
    allow_patterns=[
        "text_encoder/*.json", "text_encoder/*.fp16.safetensors",
        "text_encoder_2/*.json", "text_encoder_2/*.fp16.safetensors",
        "tokenizer/*", "tokenizer_2/*",
        "vae/*.json", "vae/*.fp16.safetensors",
        "unet/*.json", "unet/*.fp16.safetensors",
        "scheduler/*",
        "model_index.json",
    ],
    max_workers=1,
)
print(f"SDXL base components at {path}")
PYEOF

  HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}/hub"
  LOCAL_BASE="${HF_CACHE}/models--stabilityai--stable-diffusion-xl-base-1.0"
  mkdir -p "$BASE_TARGET"
  rsync -aL --exclude='.ipynb_checkpoints/' "${LOCAL_BASE}/" "$BASE_TARGET/"

  echo "Downloading TencentARC/PhotoMaker (photomaker-v1.bin)..."
  python3 - <<'PYEOF'
from huggingface_hub import hf_hub_download

path = hf_hub_download(repo_id="TencentARC/PhotoMaker", filename="photomaker-v1.bin")
print(f"PhotoMaker V1 weights at {path}")
PYEOF
  LOCAL_PM=$(find "${HF_CACHE}/models--TencentARC--PhotoMaker" -name "photomaker-v1.bin" 2>/dev/null | head -1)
  cp "$LOCAL_PM" "$PHOTOMAKER_TARGET"

  echo "Model weights ready in $TARGET_DIR"
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
