#!/usr/bin/env bash

set -e

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml>"
  exit 1
fi

MODEL_FILE="$1"

MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")
IMAGE="model-servers/llamacpp:$MODEL_NAME-$MODEL_TAG"

echo "=== Running llama.cpp Model Server ==="
echo "  Image:       $IMAGE"
echo "  Port:        8080"
echo "  API (native): http://localhost:8080/completion"
echo "  API (OpenAI): http://localhost:8080/v1/chat/completions"
echo ""
echo "Press Ctrl+C to stop."
echo ""

docker run --rm --gpus all -p 8080:8080 "$IMAGE"
