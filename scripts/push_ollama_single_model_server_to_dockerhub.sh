#!/bin/sh

set -e  # Exit on error

# Colors for clarity
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <model.yaml>"
  exit 1
fi

# Ensure yq is available
if ! command -v yq >/dev/null 2>&1; then
  echo "${RED}yq is required but not installed. Install it from https://github.com/mikefarah/yq${NC}"
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
echo "${GREEN}Parsed model metadata:${NC}"
echo "  Name:         $MODEL_NAME"
echo "  Tag:          $MODEL_TAG"
echo "  License:      $LICENSE"
echo "  Model Size:   $MODEL_SIZE"
echo "  Memory Min:   $MEM_MIN"
echo "  Memory Rec.:  $MEM_RECOMMENDED"
echo ""

# Docker Hub namespace from env
if [ -z "$DOCKERHUB_NAMESPACE" ]; then
  echo "${RED}Environment variable DOCKERHUB_NAMESPACE is not set. Exiting.${NC}"
  exit 1
fi


# Login to Docker Hub (interactive)
echo "${GREEN}Logging in to Docker Hub...${NC}"
docker login || {
  echo "${RED}Docker login failed.${NC}"
  exit 1
}

# Compose image names
LOCAL_IMAGE="model-servers/ollama-server:${MODEL_NAME}-${MODEL_TAG}"
REMOTE_IMAGE="${DOCKERHUB_NAMESPACE}/ollama-server:${MODEL_NAME}-${MODEL_TAG}"

# Tag the image
echo "${GREEN}Tagging image $LOCAL_IMAGE as $REMOTE_IMAGE...${NC}"
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE" || {
  echo "${RED}Failed to tag Docker image.${NC}"
  exit 1
}

# Push the image
echo "${GREEN}Pushing image to Docker Hub...${NC}"
docker push "$REMOTE_IMAGE" || {
  echo "${RED}Failed to push Docker image.${NC}"
  exit 1
}

echo "${GREEN}Image push completed successfully.${NC}"