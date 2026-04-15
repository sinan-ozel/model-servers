#!/usr/bin/env bash

set -e

# Usage: ./build_llamacpp_model_server.sh <model_metadata.yaml>
# Example: ./build_llamacpp_model_server.sh model_metadata/gemma3_270m.yaml

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml>"
  echo "Example: $0 model_metadata/gemma3_270m.yaml"
  exit 1
fi

MODEL_FILE="$1"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq before running this script."
  exit 1
fi

# Check if model file exists
if [ ! -f "$MODEL_FILE" ]; then
  echo "❌ Error: Model metadata file not found: $MODEL_FILE"
  exit 1
fi

# Extract values using yq
MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")
GGUF_FILENAME=$(yq '.gguf.filename' "$MODEL_FILE")
MMPROJ_FILENAME=$(yq '.gguf.mmproj.filename' "$MODEL_FILE")
LICENSE=$(yq '.license' "$MODEL_FILE")
MODEL_SIZE=$(yq '.memory.model_size' "$MODEL_FILE")
MEMORY_MIN=$(yq '.memory.min' "$MODEL_FILE")
MEMORY_RECOMMENDED=$(yq '.memory.recommended' "$MODEL_FILE")
MAX_CONTEXT_WINDOW=$(yq '.max_context_window' "$MODEL_FILE")

# Validate fields
if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" = "null" ]; then
  echo "❌ Error: Missing 'name' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$MODEL_TAG" ] || [ "$MODEL_TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$GGUF_FILENAME" ] || [ "$GGUF_FILENAME" = "null" ]; then
  echo "❌ Error: Missing 'gguf.filename' field in $MODEL_FILE"
  exit 1
fi

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
CACHE_DIR="./llamacpp/model-cache"
MODEL_PATH="$CACHE_DIR/$GGUF_FILENAME"

# Validate model exists
if [ ! -f "$MODEL_PATH" ]; then
  echo "❌ Error: Model file not found at $MODEL_PATH"
  echo "Please run download_gguf_model.sh first."
  exit 1
fi

# Determine if this is a multimodal build
HAS_MMPROJ=false
MMPROJ_PATH=""
if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ]; then
  MMPROJ_PATH="$CACHE_DIR/$MMPROJ_FILENAME"
  if [ ! -f "$MMPROJ_PATH" ]; then
    echo "❌ Error: mmproj file not found at $MMPROJ_PATH"
    echo "Please run download_gguf_model.sh first."
    exit 1
  fi
  HAS_MMPROJ=true
fi

echo "=== Building llama.cpp Model Server ==="
echo "Model file: $MODEL_FILE"
echo "Model name: $MODEL_NAME"
echo "Model tag: $MODEL_TAG"
echo "GGUF filename: $GGUF_FILENAME"
echo "Model path: $MODEL_PATH"
echo "Image tag: $IMAGE_TAG"
echo "Model size: $(du -h "$MODEL_PATH" | cut -f1)"
if [ "$HAS_MMPROJ" = true ]; then
  echo "mmproj: $MMPROJ_PATH ($(du -h "$MMPROJ_PATH" | cut -f1))"
fi
echo ""

# Copy model to build context (preserving real filenames)
echo "Preparing build context..."
cp "$MODEL_PATH" "./llamacpp/$GGUF_FILENAME"

DOCKERFILE="llamacpp/Dockerfile"
MMPROJ_BUILD_ARG=""
if [ "$HAS_MMPROJ" = true ]; then
  cp "$MMPROJ_PATH" "./llamacpp/$MMPROJ_FILENAME"
  MMPROJ_BUILD_ARG="--build-arg MMPROJ_FILENAME=$MMPROJ_FILENAME"
fi

# Clean up temp files on exit (success or failure)
_cleanup() {
  rm -f "./llamacpp/$GGUF_FILENAME"
  [ "$HAS_MMPROJ" = true ] && rm -f "./llamacpp/$MMPROJ_FILENAME"
}
trap _cleanup EXIT

# Build Docker image
IMAGE_NAME="model-servers/llamacpp:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"
echo ""

docker build \
  -t "$IMAGE_NAME" \
  -f "$DOCKERFILE" \
  --build-arg MODEL_NAME="$MODEL_NAME" \
  --build-arg MODEL_TAG="$MODEL_TAG" \
  --build-arg GGUF_FILENAME="$GGUF_FILENAME" \
  $MMPROJ_BUILD_ARG \
  --label "org.opencontainers.image.title=llama.cpp Server - ${MODEL_NAME}" \
  --label "org.opencontainers.image.description=Preloaded llama.cpp model server for ${MODEL_NAME}:${MODEL_TAG}" \
  --label "org.opencontainers.image.version=${MODEL_NAME}:${MODEL_TAG}" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=${LICENSE}" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.memory.size=${MODEL_SIZE}" \
  --label "org.opencontainers.image.memory.min=${MEMORY_MIN}" \
  --label "org.opencontainers.image.memory.recommended=${MEMORY_RECOMMENDED}" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=${MODEL_NAME}" \
  --label "ai.model.tag=${MODEL_TAG}" \
  --label "ai.model.identifier=${MODEL_NAME}:${MODEL_TAG}" \
  --label "ai.model.context_window=${MAX_CONTEXT_WINDOW}" \
  llamacpp/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run locally:"
echo "  docker run --rm --gpus all -p 8080:8080 $IMAGE_NAME"
if [ "$HAS_MMPROJ" = true ]; then
  echo ""
  echo "Multimodal (vision) image — send images via the /v1/chat/completions endpoint:"
  echo '  curl http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" \'
  echo '    -d '"'"'{"model":"gemma4","messages":[{"role":"user","content":[{"type":"text","text":"Describe this image"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,<BASE64>"}}]}]}'"'"
fi
