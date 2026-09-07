#!/usr/bin/env bash
set -e

# Usage: ./build_txt2img_model_server.sh
# Builds the txt2img image with bundled Z-Image-Turbo weights.

IMAGE_TAG="zimage-cuda"
MODEL_CACHE_DIR="./txt2img/model-cache"

if [ ! -d "${MODEL_CACHE_DIR}/hub/models--Tongyi-MAI--Z-Image-Turbo/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--Tongyi-MAI--Z-Image-Turbo not found."
  echo "Please run scripts/download_zimage_models.sh first."
  exit 1
fi
if [ ! -f "${MODEL_CACHE_DIR}/z_image_turbo-Q4_K_M.gguf" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/z_image_turbo-Q4_K_M.gguf not found."
  echo "Please run scripts/download_zimage_models.sh first."
  exit 1
fi
if [ ! -d "${MODEL_CACHE_DIR}/hub/models--Falconsai--nsfw_image_detection/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--Falconsai--nsfw_image_detection (safety checker) not found."
  echo "Please run scripts/download_zimage_models.sh first."
  exit 1
fi

IMAGE_NAME="model-servers/txt2img:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "txt2img/Dockerfile.cuda" \
  --label "org.opencontainers.image.title=txt2img - Z-Image-Turbo" \
  --label "org.opencontainers.image.description=Preloaded Z-Image-Turbo text-to-image server (CLI, HTTP, and MCP)" \
  --label "org.opencontainers.image.version=Z-Image-Turbo-Q4_K_M" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=Apache-2.0" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=Z-Image-Turbo" \
  --label "ai.model.identifier=Tongyi-MAI/Z-Image-Turbo,jayn7/Z-Image-Turbo-GGUF (Q4_K_M)" \
  --label "ai.model.source=https://huggingface.co/Tongyi-MAI/Z-Image-Turbo" \
  --label "ai.model.gguf.source=https://huggingface.co/jayn7/Z-Image-Turbo-GGUF" \
  --label "ai.model.safety_checker.name=Falconsai/nsfw_image_detection" \
  --label "ai.model.safety_checker.source=https://huggingface.co/Falconsai/nsfw_image_detection" \
  txt2img/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run locally (HTTP server):"
echo "  docker run --rm --gpus all -p 8080:8080 $IMAGE_NAME"
echo "To run the CLI:"
echo "  docker run --rm --gpus all -v \$(pwd)/txt2img/output:/data $IMAGE_NAME generate --prompt \"three cute cats playing\" --output /data/out.png"
echo "To run the MCP server (stdio):"
echo "  docker run --rm -i --gpus all $IMAGE_NAME mcp"
