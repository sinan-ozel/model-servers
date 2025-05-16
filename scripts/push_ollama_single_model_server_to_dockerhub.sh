#!/bin/sh

# Check arguments
if [ $# -lt 1 ]; then
  echo "Usage: $0 <model.yaml>"
  exit 1
fi

# Dependencies: yq
if ! command -v yq >/dev/null 2>&1; then
  echo "yq is required but not installed. Install it from https://github.com/mikefarah/yq"
  exit 1
fi

# Read and parse YAML
MODEL_FILE="$1"
MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")

# Docker Hub namespace from env
if [ -z "$DOCKERHUB_NAMESPACE" ]; then
  echo "Environment variable DOCKERHUB_NAMESPACE is not set. Exiting."
  exit 1
fi

# Login (interactive)
echo "Logging in to Docker Hub..."
docker login || exit 1

# Local and remote image names
LOCAL_IMAGE="model-servers/ollama-server:$MODEL_NAME-$MODEL_TAG"
REMOTE_IMAGE="$DOCKERHUB_NAMESPACE/ollama-server:$MODEL_NAME-$MODEL_TAG"

# Tag and push
echo "Tagging $LOCAL_IMAGE as $REMOTE_IMAGE..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

echo "Pushing $REMOTE_IMAGE..."
docker push "$REMOTE_IMAGE"
