#!/usr/bin/env bash
set -e

# Usage: ./build_lora_gen.sh
# Builds lora-gen FROM the already-built txt2img image (see
# lora-gen/Dockerfile.cuda) -- no separate model-cache download.

BASE_IMAGE="model-servers/txt2img:zimage-cuda"
IMAGE_NAME="model-servers/lora-gen:zimage-cuda"

if ! docker image inspect "$BASE_IMAGE" > /dev/null 2>&1; then
  echo "❌ Error: base image $BASE_IMAGE not found."
  echo "Please run scripts/build_txt2img_model_server.sh first."
  exit 1
fi

echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "lora-gen/Dockerfile.cuda" \
  --label "org.opencontainers.image.title=lora-gen - Z-Image Turbo + LoRA" \
  --label "org.opencontainers.image.description=Z-Image-Turbo text-to-image generation with an optional LoRA adapter (CLI only)" \
  --label "org.opencontainers.image.version=Z-Image-Turbo" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=Apache-2.0" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.base.source=https://huggingface.co/Tongyi-MAI/Z-Image-Turbo" \
  lora-gen/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run (no LoRA, same as plain txt2img):"
echo "  docker run --rm --gpus all -v \$(pwd)/out:/data $IMAGE_NAME generate --prompt \"three cute cats playing\" --output /data/out.png"
echo "To run with a LoRA (e.g. from lora-train):"
echo "  docker run --rm --gpus all -v \$(pwd)/my_person:/data -v \$(pwd)/out:/out $IMAGE_NAME generate \\"
echo "    --prompt \"a photo of img man at a conference\" --lora /data/output/img.safetensors --output /out/out.png"
