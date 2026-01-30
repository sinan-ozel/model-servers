#!/bin/bash
# scripts/preload_model.sh

set -e

MODEL_NAME=$1
MODEL_TAG=$2
OLLAMA_VERSION="0.15.2"

# Create a temporary container to extract the model files
docker run --rm \
  -v "$(pwd)/ollama/model-cache:/root/.ollama" \
  ollama/ollama:$OLLAMA_VERSION \
  sh -c "ollama serve & sleep 5 && ollama pull ${MODEL_NAME}:${MODEL_TAG}"