#!/usr/bin/env bash

set -e

# Usage: ./push_llamacpp_model_server_to_dockerhub.sh <model_metadata.yaml>
# Repo is derived automatically from vram_tier in the YAML:
#   cpu  → llama.cpu
#   1g   → llama.cuda.1gb
#   6g   → llama.cuda.6gb
#   12g  → llama.cuda.12gb
#   24g  → llama.cuda.24gb

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml>"
  echo "Example: $0 model_metadata/gemma3_270m.yaml"
  exit 1
fi

MODEL_FILE="$1"

if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq before running this script."
  exit 1
fi

if [ ! -f "$MODEL_FILE" ]; then
  echo "❌ Error: Model metadata file not found: $MODEL_FILE"
  exit 1
fi

MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")
VRAM_TIER=$(yq '.vram_tier' "$MODEL_FILE")

if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" = "null" ]; then
  echo "❌ Error: Missing 'name' field in $MODEL_FILE"; exit 1
fi
if [ -z "$MODEL_TAG" ] || [ "$MODEL_TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $MODEL_FILE"; exit 1
fi
if [ -z "$VRAM_TIER" ] || [ "$VRAM_TIER" = "null" ]; then
  echo "❌ Error: 'vram_tier' not set in $MODEL_FILE — add vram_tier: cpu|1g|6g|12g|24g"; exit 1
fi

case "$VRAM_TIER" in
  cpu) REPO="llama.cpu"       ;;
  1g)  REPO="llama.cuda.1gb"  ;;
  6g)  REPO="llama.cuda.6gb"  ;;
  12g) REPO="llama.cuda.12gb" ;;
  24g) REPO="llama.cuda.24gb" ;;
  *)
    echo "❌ Error: unknown vram_tier '$VRAM_TIER'. Choose cpu, 1g, 6g, 12g, or 24g."
    exit 1
    ;;
esac

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
LOCAL_IMAGE="model-servers/llamacpp:$IMAGE_TAG"

if [ -z "$DOCKERHUB_NAMESPACE" ]; then
  echo "❌ Environment variable DOCKERHUB_NAMESPACE is not set."
  echo "Example: export DOCKERHUB_NAMESPACE=yourusername"
  exit 1
fi

REMOTE_IMAGE="$DOCKERHUB_NAMESPACE/$REPO:$IMAGE_TAG"

echo "=== Pushing llama.cpp Model Server to Docker Hub ==="
echo "Model file:   $MODEL_FILE"
echo "VRAM tier:    $VRAM_TIER"
echo "Local image:  $LOCAL_IMAGE"
echo "Remote image: $REMOTE_IMAGE"
echo ""

if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${LOCAL_IMAGE}$"; then
  echo "❌ Error: Local image not found: $LOCAL_IMAGE"
  echo "Please build the image first using build_llamacpp_model_server.sh"
  exit 1
fi

echo "Logging in to Docker Hub..."
docker login || { echo "❌ Docker login failed."; exit 1; }

echo "Tagging image..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

echo "Pushing image to Docker Hub..."
echo "This may take several minutes depending on the model size..."
echo ""
docker push "$REMOTE_IMAGE"

echo ""
echo "✓ Push complete!"
echo "  Image: $REMOTE_IMAGE"
echo "  Docker Hub: https://hub.docker.com/r/$DOCKERHUB_NAMESPACE/$REPO"
echo ""
echo "To pull and run on another machine:"
echo "  docker pull $REMOTE_IMAGE"
if [ "$VRAM_TIER" = "cpu" ]; then
  echo "  docker run --rm -p 8080:8080 $REMOTE_IMAGE"
else
  echo "  docker run --rm --gpus all -p 8080:8080 $REMOTE_IMAGE"
fi
