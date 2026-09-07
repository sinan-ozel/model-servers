#!/usr/bin/env bash
set -e

# Downloads the models bundled into the txt2img image:
# - Tongyi-MAI/Z-Image-Turbo (scheduler/tokenizer/vae/text encoder)
# - jayn7/Z-Image-Turbo-GGUF Q4_K_M transformer
# - Falconsai/nsfw_image_detection (the safety checker; see src/lib/safety.py)
# Usage: ./download_zimage_models.sh

# BASE_TARGET must live under hub/ -- the standard HuggingFace cache layout
# huggingface_hub uses to resolve models by repo_id. HF_HOME is set to this
# dir at build time (see Dockerfile.cuda) so that from_single_file()'s
# auto-fetch of the transformer's companion config.json finds it locally,
# and so the safety checker resolves the same way.
TARGET_DIR="./txt2img/model-cache"
BASE_TARGET="${TARGET_DIR}/hub/models--Tongyi-MAI--Z-Image-Turbo"
GGUF_TARGET="${TARGET_DIR}/z_image_turbo-Q4_K_M.gguf"
SAFETY_TARGET="${TARGET_DIR}/hub/models--Falconsai--nsfw_image_detection"
mkdir -p "$TARGET_DIR/hub"

HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}/hub"

if [ -d "$BASE_TARGET/snapshots" ] && [ -f "$GGUF_TARGET" ]; then
  echo "Already present in $TARGET_DIR, skipping download."
  exit 0
fi

# Fast path: reuse an existing local HuggingFace cache if these were already
# pulled down for other work (e.g. the jupyterlab-on-kubernetes notebooks).
LOCAL_BASE="${HF_CACHE}/models--Tongyi-MAI--Z-Image-Turbo"
LOCAL_GGUF=$(find "${HF_CACHE}/models--jayn7--Z-Image-Turbo-GGUF" -name "z_image_turbo-Q4_K_M.gguf" 2>/dev/null | head -1)

if [ -d "$LOCAL_BASE" ] && [ -n "$LOCAL_GGUF" ]; then
  echo "Found existing local HF cache, copying (dereferencing symlinks)..."
  rsync -aL --exclude='.ipynb_checkpoints/' "${LOCAL_BASE}/" "$BASE_TARGET/"
  cp "$LOCAL_GGUF" "$GGUF_TARGET"
  echo "Copied from $HF_CACHE"
  exit 0
fi

echo "Not found locally -- downloading from Hugging Face..."
python3 - <<'PYEOF'
from huggingface_hub import snapshot_download, hf_hub_download

print("Downloading Tongyi-MAI/Z-Image-Turbo...")
base_path = snapshot_download(repo_id="Tongyi-MAI/Z-Image-Turbo", max_workers=1)
print(f"Base model at {base_path}")

print("Downloading jayn7/Z-Image-Turbo-GGUF (Q4_K_M)...")
gguf_path = hf_hub_download(
    repo_id="jayn7/Z-Image-Turbo-GGUF",
    filename="z_image_turbo-Q4_K_M.gguf",
)
print(f"GGUF weights at {gguf_path}")
PYEOF

LOCAL_GGUF=$(find "${HF_CACHE}/models--jayn7--Z-Image-Turbo-GGUF" -name "z_image_turbo-Q4_K_M.gguf" 2>/dev/null | head -1)
rsync -aL --exclude='.ipynb_checkpoints/' "${LOCAL_BASE}/" "$BASE_TARGET/"
cp "$LOCAL_GGUF" "$GGUF_TARGET"

echo "Model weights ready in $TARGET_DIR"

# ----------------------------------------------------
# Safety checker (small, always fetched straight into the target HF cache --
# no "reuse an existing local copy" fast path needed for ~1.4GB).
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
