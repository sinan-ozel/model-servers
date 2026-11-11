#!/usr/bin/env bash
set -e

# Bundles Tongyi-MAI/Z-Image-Turbo into lora-train/model-cache for the
# lora-train image: transformer (bf16 safetensors, quantized to 4-bit at
# runtime), Qwen3 text encoder, tokenizer, VAE, and scheduler config.
# The text encoder and tokenizer are copied from txt2img/model-cache if present
# (dereferenced, so the copy is self-contained) instead of downloaded again.
# Also bundles ostris/zimage_turbo_training_adapter (Apache-2.0): a frozen
# training-time LoRA that keeps Turbo's step-distillation from degrading while
# the identity LoRA trains. Without it, a direct LoRA on Turbo is a known
# failure mode -- see lora-train/README.md.
# Requires huggingface_hub on the host (pip install huggingface_hub).
# Usage: ./download_lora_train_models.sh

TARGET_DIR="./lora-train/model-cache"
REPO="models--Tongyi-MAI--Z-Image-Turbo"
BASE_TARGET="${TARGET_DIR}/hub/${REPO}"
TXT2IMG_BASE="./txt2img/model-cache/hub/${REPO}"
DISTILL_ADAPTER_TARGET="${TARGET_DIR}/zimage_turbo_distill_adapter.safetensors"
mkdir -p "$TARGET_DIR/hub"

if [ -d "$BASE_TARGET/snapshots" ] && [ -d "$BASE_TARGET/snapshots"/*/transformer ]; then
  echo "Z-Image Turbo already present in $BASE_TARGET, skipping."
else
  echo "Downloading Z-Image Turbo transformer, VAE, and scheduler (~25GB)..."
  HF_HOME="$(pwd)/${TARGET_DIR}" python3 - <<'PYEOF'
from huggingface_hub import snapshot_download

path = snapshot_download(
    repo_id="Tongyi-MAI/Z-Image-Turbo",
    allow_patterns=["transformer/*", "vae/*", "scheduler/*", "model_index.json"],
    max_workers=2,
)
print(f"Z-Image Turbo components at {path}")
PYEOF

  SNAP="$(ls -d "${BASE_TARGET}"/snapshots/* | head -1)"
  if [ -d "$TXT2IMG_BASE/snapshots" ]; then
    echo "Copying text encoder and tokenizer from txt2img/model-cache..."
    TXT_SNAP="$(ls -d "${TXT2IMG_BASE}"/snapshots/* | head -1)"
    cp -rL "$TXT_SNAP/text_encoder" "$TXT_SNAP/tokenizer" "$SNAP/"
  else
    echo "Downloading text encoder and tokenizer..."
    HF_HOME="$(pwd)/${TARGET_DIR}" python3 - <<'PYEOF'
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="Tongyi-MAI/Z-Image-Turbo",
    allow_patterns=["text_encoder/*", "tokenizer/*"],
    max_workers=2,
)
PYEOF
  fi
fi

if [ -f "$DISTILL_ADAPTER_TARGET" ]; then
  echo "De-distillation adapter already present, skipping."
else
  echo "Downloading de-distillation training adapter (~340MB)..."
  HF_HOME="$(pwd)/${TARGET_DIR}" python3 - <<'PYEOF'
from huggingface_hub import hf_hub_download

path = hf_hub_download("ostris/zimage_turbo_training_adapter", "zimage_turbo_training_adapter_v2.safetensors")
print(f"De-distillation adapter at {path}")
PYEOF
  LOCAL_ADAPTER=$(find "$(pwd)/${TARGET_DIR}/hub/models--ostris--zimage_turbo_training_adapter" -name "*.safetensors" 2>/dev/null | head -1)
  cp "$LOCAL_ADAPTER" "$DISTILL_ADAPTER_TARGET"
fi

echo "Model weights ready in $TARGET_DIR"
