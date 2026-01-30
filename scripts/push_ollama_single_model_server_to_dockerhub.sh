#!/usr/bin/env bash

set -e  # Exit on error

OLLAMA_VERSION="0.15.2"

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <model.yaml>"
  exit 1
fi

# Ensure yq is available
if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required but not installed. Install it from https://github.com/mikefarah/yq"
  exit 1
fi


# Read and parse YAML
MODEL_FILE="$1"
MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")
LICENSE=$(yq '.license' "$MODEL_FILE")
MODEL_SIZE=$(yq '.memory.model_size' "$MODEL_FILE")
MEM_MIN=$(yq '.memory.min' "$MODEL_FILE")
MEM_RECOMMENDED=$(yq '.memory.recommended' "$MODEL_FILE")

# Show parsed values
echo "Parsed model metadata:"
echo "  Name:         $MODEL_NAME"
echo "  Tag:          $MODEL_TAG"
echo "  License:      $LICENSE"
echo "  Model Size:   $MODEL_SIZE"
echo "  Memory Min:   $MEM_MIN"
echo "  Memory Rec.:  $MEM_RECOMMENDED"
echo ""

# Docker Hub namespace from env
if [ -z "$DOCKERHUB_NAMESPACE" ]; then
  echo "Environment variable DOCKERHUB_NAMESPACE is not set. Exiting."
  exit 1
fi


# Login to Docker Hub (interactive)
echo "Logging in to Docker Hub..."
docker login || {
  echo "Docker login failed."
  exit 1
}

# Compose image names
SAFE_NAME="${MODEL_NAME//\//-}"
REMOTE_IMAGE="${DOCKERHUB_NAMESPACE}/ollama.${OLLAMA_VERSION}:${SAFE_NAME}-${MODEL_TAG}"
LOCAL_IMAGE="model-servers/ollama.${OLLAMA_VERSION}:${SAFE_NAME}-${MODEL_TAG}"

# Tag the image
echo "Tagging image $LOCAL_IMAGE as $REMOTE_IMAGE..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE" || {
  echo "Failed to tag Docker image."
  exit 1
}

# Push the image
echo "Pushing image to Docker Hub..."
docker push "$REMOTE_IMAGE" || {
  echo "Failed to push Docker image."
  exit 1
}

echo "Image push completed successfully."