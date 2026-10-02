#!/usr/bin/env bash
set -e

# Usage: ./build_faceid_model_server.sh
# Builds the faceid image with bundled SDXL + PhotoMaker V1 weights.

IMAGE_TAG="photomaker-sdxl-cuda"
MODEL_CACHE_DIR="./faceid/model-cache"

if [ ! -d "${MODEL_CACHE_DIR}/hub/models--stabilityai--stable-diffusion-xl-base-1.0/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--stabilityai--stable-diffusion-xl-base-1.0 not found."
  echo "Please run scripts/download_photomaker_models.sh first."
  exit 1
fi
if [ ! -f "${MODEL_CACHE_DIR}/photomaker-v1.bin" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/photomaker-v1.bin not found."
  echo "Please run scripts/download_photomaker_models.sh first."
  exit 1
fi
if [ ! -d "${MODEL_CACHE_DIR}/hub/models--Falconsai--nsfw_image_detection/snapshots" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/hub/models--Falconsai--nsfw_image_detection (safety checker) not found."
  echo "Please run scripts/download_photomaker_models.sh first."
  exit 1
fi

IMAGE_NAME="model-servers/faceid:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "faceid/Dockerfile.cuda" \
  --label "org.opencontainers.image.title=faceid - PhotoMaker + SDXL" \
  --label "org.opencontainers.image.description=Preloaded PhotoMaker V1 + SDXL identity-preserving image generation server (CLI, HTTP, and MCP)" \
  --label "org.opencontainers.image.version=PhotoMaker-V1+SDXL-base-1.0" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=Apache-2.0" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=PhotoMaker" \
  --label "ai.model.identifier=TencentARC/PhotoMaker (V1),stabilityai/stable-diffusion-xl-base-1.0" \
  --label "ai.model.source=https://github.com/TencentARC/PhotoMaker" \
  --label "ai.model.base.source=https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0" \
  --label "ai.model.safety_checker.name=Falconsai/nsfw_image_detection" \
  --label "ai.model.safety_checker.source=https://huggingface.co/Falconsai/nsfw_image_detection" \
  faceid/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run locally (HTTP server):"
echo "  docker run --rm --gpus all -p 8080:8080 $IMAGE_NAME"
echo "To run the CLI:"
echo "  docker run --rm --gpus all -v \$(pwd)/faceid/tests/fixtures:/data $IMAGE_NAME generate --prompt \"a photo of a person img\" --id-image /data/id_face.png --output /data/out.png"
echo "To run the MCP server (stdio):"
echo "  docker run --rm -i --gpus all $IMAGE_NAME mcp"
