#!/usr/bin/env bash
set -euo pipefail

MODEL_FILE="$1"

# Extract fields using yq (requires yq installed: https://github.com/mikefarah/yq)
model_name=$(yq '.name' "$MODEL_FILE")
model_tag=$(yq '.tag' "$MODEL_FILE")
image_name="model-servers/ollama-server:$model_name-$model_tag"

echo "Creating container with overridden entrypoint..."
container_id=$(docker create --entrypoint bash "$image_name" -c 'find /root/.ollama/models/blobs -type f -name sha256-* -size +1000000k -print -quit | grep -q . || exit 1')

echo "Starting container to verify model presence..."
docker start -a "$container_id"

# Get container exit code
exit_code=$(docker inspect "$container_id" --format='{{.State.ExitCode}}')

# Clean up
docker rm "$container_id" > /dev/null

if [ "$exit_code" -ne 0 ]; then
  echo "❌ No file larger than 1GB found. Exiting with error."
  exit 1
else
  echo "✅ File larger than 1GB found. Success."
fi
