#!/bin/bash
# scripts/preload_model.sh

set -e

MODEL_NAME=$1
MODEL_TAG=$2

# Create a temporary container to extract the model files
docker run --rm \
  -v "$(pwd)/ollama-cache:/root/.ollama" \
  ollama/ollama:0.6.5 \
  sh -c "ollama serve & sleep 5 && ollama pull ${MODEL_NAME}:${MODEL_TAG}"