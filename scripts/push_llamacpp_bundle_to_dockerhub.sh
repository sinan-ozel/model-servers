#!/usr/bin/env bash

set -e

# Usage: ./push_llamacpp_bundle_to_dockerhub.sh <bundle.yaml>
# Example: ./push_llamacpp_bundle_to_dockerhub.sh bundles/llama.cuda.6gb.yaml

if [ $# -lt 1 ]; then
  echo "Usage: $0 <bundle.yaml>"
  echo "Example: $0 bundles/llama.cuda.6gb.yaml"
  exit 1
fi

BUNDLE_FILE="$1"

if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq before running this script."
  exit 1
fi

if [ ! -f "$BUNDLE_FILE" ]; then
  echo "❌ Error: Bundle file not found: $BUNDLE_FILE"
  exit 1
fi

REPO=$(yq '.repo' "$BUNDLE_FILE")
TAG=$(yq '.tag' "$BUNDLE_FILE")

if [ -z "$REPO" ] || [ "$REPO" = "null" ]; then
  echo "❌ Error: Missing 'repo' field in $BUNDLE_FILE"
  exit 1
fi

if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $BUNDLE_FILE"
  exit 1
fi

if [ -z "$DOCKERHUB_NAMESPACE" ]; then
  echo "❌ Environment variable DOCKERHUB_NAMESPACE is not set."
  echo "Example: export DOCKERHUB_NAMESPACE=yourusername"
  exit 1
fi

LOCAL_IMAGE="model-servers/llamacpp:$REPO-$TAG"
REMOTE_IMAGE="$DOCKERHUB_NAMESPACE/$REPO:$TAG"

echo "=== Pushing llama.cpp Bundle to Docker Hub ==="
echo "Bundle file:  $BUNDLE_FILE"
echo "Local image:  $LOCAL_IMAGE"
echo "Remote image: $REMOTE_IMAGE"
echo ""

if ! docker images --format "{{.Repository}}:{{.Tag}}" | grep -q "^${LOCAL_IMAGE}$"; then
  echo "❌ Error: Local image not found: $LOCAL_IMAGE"
  echo "Please build the bundle first using build_llamacpp_bundle.sh"
  exit 1
fi

echo "Logging in to Docker Hub..."
docker login || { echo "❌ Docker login failed."; exit 1; }

echo "Tagging image..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

echo "Pushing image to Docker Hub..."
echo "This may take several minutes depending on bundle size..."
echo ""
docker push "$REMOTE_IMAGE"

echo ""
echo "✓ Push complete!"
echo "  Image: $REMOTE_IMAGE"
echo "  Docker Hub: https://hub.docker.com/r/$DOCKERHUB_NAMESPACE/$REPO"
