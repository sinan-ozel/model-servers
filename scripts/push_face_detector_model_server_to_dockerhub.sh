#!/usr/bin/env bash
set -e

IMAGE_TAG="yunet-cpu"
LOCAL_IMAGE="model-servers/face-detector:${IMAGE_TAG}"
REMOTE_IMAGE="${DOCKERHUB_NAMESPACE}/face-detector:${IMAGE_TAG}"

echo "Tagging image $LOCAL_IMAGE as $REMOTE_IMAGE..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE" || {
  echo "Failed to tag Docker image."
  exit 1
}

echo "Pushing image to Docker Hub..."
docker push "$REMOTE_IMAGE" || {
  echo "Failed to push Docker image."
  exit 1
}

echo "Image push completed successfully."
