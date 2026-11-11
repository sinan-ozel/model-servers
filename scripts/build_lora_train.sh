#!/usr/bin/env bash
set -e

# Usage: ./build_lora_train.sh
# Builds the lora-train image with bundled Z-Image Turbo weights (~35GB image).

IMAGE_TAG="zimage-cuda"
MODEL_CACHE_DIR="./lora-train/model-cache"

if [ ! -d "${MODEL_CACHE_DIR}/hub/models--Tongyi-MAI--Z-Image-Turbo/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--Tongyi-MAI--Z-Image-Turbo not found."
  echo "Please run scripts/download_lora_train_models.sh first."
  exit 1
fi

IMAGE_NAME="model-servers/lora-train:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "lora-train/Dockerfile.cuda" \
  --label "org.opencontainers.image.title=lora-train - Z-Image Turbo LoRA trainer" \
  --label "org.opencontainers.image.description=Batch LoRA trainer for Z-Image Turbo from a folder of images and a description.yaml" \
  --label "org.opencontainers.image.version=Z-Image-Turbo" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=Apache-2.0" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.base.source=https://huggingface.co/Tongyi-MAI/Z-Image-Turbo" \
  lora-train/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To train (dataset folder must contain images and description.yaml):"
echo "  docker run --rm --gpus all --user \"\$(id -u):\$(id -g)\" -v \$(pwd)/my_person:/data $IMAGE_NAME /data --trigger-word img --steps 1000"
