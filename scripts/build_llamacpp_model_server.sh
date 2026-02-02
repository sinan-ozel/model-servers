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

echo "=== Building llama.cpp Model Server ==="
echo "Model file: $MODEL_FILE"
echo "Model name: $MODEL_NAME"
echo "Model tag: $MODEL_TAG"
echo "GGUF filename: $GGUF_FILENAME"
echo "Model path: $MODEL_PATH"
echo "Image tag: $IMAGE_TAG"
echo "Model size: $(du -h "$MODEL_PATH" | cut -f1)"
echo ""

# Copy model to build context
echo "Preparing build context..."
cp "$MODEL_PATH" "./llamacpp/model.gguf"

# Build Docker image
IMAGE_NAME="model-servers/llamacpp:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"
echo ""

docker build \
  -t "$IMAGE_NAME" \
  -f llamacpp/Dockerfile \
  llamacpp/

# Clean up temporary model file
rm -f "./llamacpp/model.gguf"

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
echo "To run locally:"
echo "  docker run --rm --gpus all -p 8080:8080 $IMAGE_NAME"
