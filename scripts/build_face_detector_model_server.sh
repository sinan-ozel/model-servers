#!/usr/bin/env bash
set -e

# Usage: ./build_face_detector_model_server.sh
# Builds the face-detector image with the bundled YuNet ONNX weights.

IMAGE_TAG="yunet-cpu"
MODEL_CACHE_DIR="./face-detector/model-cache"

if [ ! -f "${MODEL_CACHE_DIR}/face_detection_yunet_2023mar.onnx" ]; then
  echo "❌ Error: ${MODEL_CACHE_DIR}/face_detection_yunet_2023mar.onnx not found."
  echo "Please run scripts/download_face_detector_models.sh first."
  exit 1
fi

IMAGE_NAME="model-servers/face-detector:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"

docker build \
  -t "$IMAGE_NAME" \
  -f "face-detector/Dockerfile" \
  --label "org.opencontainers.image.title=Face Detector - YuNet" \
  --label "org.opencontainers.image.description=Preloaded YuNet face detection server (CLI, HTTP, and MCP)" \
  --label "org.opencontainers.image.version=face_detection_yunet_2023mar" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=MIT" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=YuNet" \
  --label "ai.model.identifier=face_detection_yunet_2023mar" \
  --label "ai.model.source=https://github.com/opencv/opencv_zoo" \
  --label "ai.model.url=https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/face_detection_yunet_2023mar.onnx" \
  face-detector/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run locally (HTTP server):"
echo "  docker run --rm -p 8080:8080 $IMAGE_NAME"
echo "To run the CLI:"
echo "  docker run --rm -v \$(pwd)/face-detector/tests/fixtures:/data $IMAGE_NAME detect --file /data/faces.png --output-dir /data/out"
echo "  (--file is repeatable and accepts a quoted glob, e.g. --file '/data/*.png')"
echo "To run the MCP server (stdio):"
echo "  docker run --rm -i $IMAGE_NAME mcp"
