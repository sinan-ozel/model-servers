#!/usr/bin/env bash
set -e

# Usage: ./build_img2vid_model_server.sh
# Builds the img2vid image with bundled Wan 2.2 TI2V-5B weights.

IMAGE_TAG="wan22-ti2v-5b-cuda"
MODEL_CACHE_DIR="./img2vid/model-cache"

if [ ! -d "${MODEL_CACHE_DIR}/hub/models--Wan-AI--Wan2.2-TI2V-5B-Diffusers/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--Wan-AI--Wan2.2-TI2V-5B-Diffusers not found."
  echo "Please run scripts/download_wan_models.sh first."
  exit 1
fi
if [ ! -d "${MODEL_CACHE_DIR}/hub/models--Falconsai--nsfw_image_detection/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--Falconsai--nsfw_image_detection (safety checker) not found."
  echo "Please run scripts/download_wan_models.sh first."
  exit 1
fi

IMAGE_NAME="model-servers/img2vid:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "img2vid/Dockerfile.cuda" \
  --label "org.opencontainers.image.title=img2vid - Wan 2.2 TI2V-5B" \
  --label "org.opencontainers.image.description=Preloaded Wan 2.2 TI2V-5B image+text-to-video generator (CLI)" \
  --label "org.opencontainers.image.version=Wan2.2-TI2V-5B" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=Apache-2.0" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=Wan2.2-TI2V-5B" \
  --label "ai.model.identifier=Wan-AI/Wan2.2-TI2V-5B-Diffusers" \
  --label "ai.model.source=https://huggingface.co/Wan-AI/Wan2.2-TI2V-5B-Diffusers" \
  --label "ai.model.safety_checker.name=Falconsai/nsfw_image_detection" \
  --label "ai.model.safety_checker.source=https://huggingface.co/Falconsai/nsfw_image_detection" \
  img2vid/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run (writes my_clips/aaa.mp4 next to the input):"
echo "  docker run --rm --gpus all --user \"\$(id -u):\$(id -g)\" -v \$(pwd)/my_clips:/data $IMAGE_NAME generate --input /data/aaa.png --prompt \"she turns and smiles\" --height 480"
echo "To continue from the last frame of that clip (writes my_clips/aaa-001.mp4):"
echo "  docker run --rm --gpus all --user \"\$(id -u):\$(id -g)\" -v \$(pwd)/my_clips:/data $IMAGE_NAME generate --input /data/aaa.mp4 --prompt \"she waves\""
