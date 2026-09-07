#!/usr/bin/env bash
set -e

# Usage: ./build_upscaler_model_server.sh
# Builds the upscaler image with bundled Real-ESRGAN weights.

IMAGE_TAG="realesrgan-cuda"
MODEL_CACHE_DIR="./upscaler/model-cache"

for filename in RealESRGAN_x2plus.pth RealESRGAN_x4plus.pth; do
  if [ ! -f "${MODEL_CACHE_DIR}/${filename}" ]; then
    echo "❌ Error: ${MODEL_CACHE_DIR}/${filename} not found."
    echo "Please run scripts/download_upscaler_models.sh first."
    exit 1
  fi
done

IMAGE_NAME="model-servers/upscaler:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "upscaler/Dockerfile.cuda" \
  --label "org.opencontainers.image.title=Upscaler - Real-ESRGAN" \
  --label "org.opencontainers.image.description=Preloaded Real-ESRGAN image upscaling server (CLI, HTTP, and MCP)" \
  --label "org.opencontainers.image.version=RealESRGAN_x2plus+x4plus" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=BSD-3-Clause" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=Real-ESRGAN" \
  --label "ai.model.identifier=RealESRGAN_x2plus,RealESRGAN_x4plus" \
  --label "ai.model.source=https://github.com/xinntao/Real-ESRGAN" \
  --label "ai.model.x2plus.url=https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth" \
  --label "ai.model.x4plus.url=https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth" \
  upscaler/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run locally (HTTP server):"
echo "  docker run --rm --gpus all -p 8080:8080 $IMAGE_NAME"
echo "To run the CLI:"
echo "  docker run --rm --gpus all -v \$(pwd)/upscaler/tests/fixtures:/data $IMAGE_NAME upscale --file /data/sample.png --scale 4 --output /data/out.png"
echo "To run the MCP server (stdio):"
echo "  docker run --rm -i --gpus all $IMAGE_NAME mcp"
