#!/bin/bash

MODEL_FILE="$1"
OLLAMA_VERSION="0.12.2"

model_name=$(yq '.name' "$MODEL_FILE")
model_tag=$(yq '.tag' "$MODEL_FILE")
model_size=$(yq '.memory.model_size' "$MODEL_FILE")

if [ -z "$model_name" ] || [ -z "$model_tag" ] || [ -z "$model_size" ]; then
  echo "❌ Invalid or missing fields in YAML" >&2
  exit 1
fi

# Convert GiB to kilobytes (e.g., 1.1GiB -> 1126400)
model_size_kb=$(echo "$model_size" | awk '
    /^[0-9.]+GiB$/ {
        val = $0; sub(/GiB/, "", val); printf "%.0f", val * 1024 * 1024; next
    }
    /^[0-9.]+GB$/ {
        val = $0; sub(/GB/, "", val); printf "%.0f", val * 1000 * 1000; next
    }
    /^[0-9.]+MiB$/ {
        val = $0; sub(/MiB/, "", val); printf "%.0f", val * 1024; next
    }
    /^[0-9.]+MB$/ {
        val = $0; sub(/MB/, "", val); printf "%.0f", val * 1000; next
    }
    { print "Invalid model_size format: " $0 > "/dev/stderr"; exit 1 }
')
expected_file_size_kb=$((model_size_kb / 4))

if [ -z "$model_size_kb" ]; then
  echo "Failed to parse model size" >&2
  exit 1
fi
echo "Model size: $model_size. Parsed size in kB: $model_size_kb."

image_name="model-servers/ollama.${OLLAMA_VERSION}:$model_name-$model_tag"
manifest_path="/root/.ollama/models/manifests/registry.ollama.ai/library/$model_name/$model_tag"

container_id=$(docker create \
  --entrypoint bash \
  "$image_name" \
  -c "find /root/.ollama/models/blobs -type f -name sha256-* -size +${expected_file_size_kb}k -print -quit | grep -q . && test -f '$manifest_path'")

if [ -z "$container_id" ]; then
  echo "❌ Docker create failed. Check image name: $image_name" >&2
  exit 1
fi

docker start -a "$container_id"
exit_code=$(docker inspect "$container_id" --format='{{.State.ExitCode}}')
docker rm "$container_id" >/dev/null

if [ "$exit_code" -ne 0 ]; then
  echo "❌ No file larger than ${expected_file_size_kb}kB found. Exiting with error."
  exit 1
else
  echo "✅ File larger than ${expected_file_size_kb}kB found. Success."
  exit 0
fi

# echo "Creating container to verify /metrics/gpu.json existence and content..."
# gpu_metrics_check_container_id=$(docker create \
#   --entrypoint bash \
#   "$image_name" \
#   -c "test -s /metrics/gpu.json")

# echo "Starting container to check /metrics/gpu.json..."
# docker start -a "$gpu_metrics_check_container_id"

# gpu_metrics_exit_code=$(docker inspect "$gpu_metrics_check_container_id" --format='{{.State.ExitCode}}')

# docker rm "$gpu_metrics_check_container_id" >/dev/null

# if [ "$gpu_metrics_exit_code" -ne 0 ]; then
#   echo "❌ /metrics/gpu.json is missing or empty. Exiting with error."
#   exit 1
# else
#   echo "✅ /metrics/gpu.json exists and is not empty."
# fi
