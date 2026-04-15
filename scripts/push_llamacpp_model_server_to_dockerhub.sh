#!/usr/bin/env bash

set -e

# Usage: ./push_llamacpp_model_server_to_dockerhub.sh <model_metadata.yaml> [repo]
# Example: ./push_llamacpp_model_server_to_dockerhub.sh model_metadata/gemma3_270m.yaml llama.cuda.6gb

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml> [repo]"
  echo "Example: $0 model_metadata/gemma3_270m.yaml llama.cuda.6gb"
  exit 1
fi

MODEL_FILE="$1"
REPO="${2:-llama.cuda}"

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

# Validate fields
if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" = "null" ]; then
  echo "❌ Error: Missing 'name' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$MODEL_TAG" ] || [ "$MODEL_TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $MODEL_FILE"
  exit 1
fi

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
LOCAL_IMAGE="model-servers/llamacpp:$IMAGE_TAG"

# Docker Hub namespace from env
if [ -z "$DOCKERHUB_NAMESPACE" ]; then
  echo "❌ Environment variable DOCKERHUB_NAMESPACE is not set."
  echo "Example: export DOCKERHUB_NAMESPACE=yourusername"
  exit 1
fi

REMOTE_IMAGE="$DOCKERHUB_NAMESPACE/$REPO:$IMAGE_TAG"

echo "=== Pushing llama.cpp Model Server to Docker Hub ==="
echo "Model file: $MODEL_FILE"
echo "Local image: $LOCAL_IMAGE"
echo "Remote image: $REMOTE_IMAGE"
echo ""

# Check if local image exists
if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${LOCAL_IMAGE}$"; then
  echo "❌ Error: Local image not found: $LOCAL_IMAGE"
  echo "Please build the image first using build_llamacpp_model_server.sh"
  exit 1
fi

# Login to Docker Hub
echo "Logging in to Docker Hub..."
docker login || {
  echo "❌ Docker login failed."
  exit 1
}

# Tag image for Docker Hub
echo "Tagging image..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

# Push image
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
echo "  docker run --rm --gpus all -p 8080:8080 $REMOTE_IMAGE"
