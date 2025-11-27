
VERSION="0.1.0"

MODEL_PUBLISHER="CompVis"
MODEL_NAME="stable-diffusion-v1-4"

REMOTE_IMAGE="${DOCKERHUB_NAMESPACE}/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME}"
LOCAL_IMAGE="model-servers/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME}"


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