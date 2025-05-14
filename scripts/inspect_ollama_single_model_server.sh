#!/bin/bash

set -e

model_file="$1"
model_name=$(yq '.name' "$model_file")
model_tag=$(yq '.tag' "$model_file")
model_size=$(yq '.memory.model_size' "$model_file")

# Convert GiB to kilobytes (e.g., 1.1GiB -> 1126400)
model_size_kb=$(echo "$model_size" | sed 's/GiB//' | awk '{printf "%.0f", $1 * 1024 * 1024}')
expected_file_size_kb=$((model_size_kb / 2))

image_name="model-servers/ollama-server:$model_name-$model_tag"
manifest_path="/root/.ollama/models/manifests/registry.ollama.ai/library/$model_name/$model_tag"

container_id=$(docker create \
  --entrypoint bash \
  "$image_name" \
  -c "find /root/.ollama/models/blobs -type f -name sha256-* -size +${expected_file_size_kb}k -print -quit | grep -q . && test -f '$manifest_path'")

docker start -a "$container_id"
exit_code=$(docker inspect "$container_id" --format='{{.State.ExitCode}}')
docker rm "$container_id" >/dev/null

if [ "$exit_code" -ne 0 ]; then
  echo "❌ No file larger than 1GB found. Exiting with error."
  exit 1
else
  echo "✅ File larger than 1GB found. Success."
fi
