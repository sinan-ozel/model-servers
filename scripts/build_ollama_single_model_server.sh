#!/bin/bash

set -e

MODEL_FILE="$1"

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq before running this script."
  exit 1
fi

# Extract values using yq
MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")
LICENSE=$(yq '.license' "$MODEL_FILE")
MODEL_SIZE=$(yq '.memory.model_size' "$MODEL_FILE")
MEMORY_MIN=$(yq '.memory.min' "$MODEL_FILE")
MEMORY_RECOMMENDED=$(yq '.memory.recommended' "$MODEL_FILE")

# Ensure model cache directory exists
CACHE_PATH="$(realpath ollama/model-cache)"
mkdir -p "$CACHE_PATH"
[ -d ollama/model-cache ] && rm -rf ollama/model-cache/*

# Preload model using Ollama container
docker run --rm \
    --entrypoint sh \
    -v "$CACHE_PATH:/root/.ollama" \
    -e OLLAMA_ORCHESTRATOR=standalone \
    ollama/ollama:0.6.5 \
    -c "ollama serve & sleep 5 && ollama pull ${MODEL_NAME}:${MODEL_TAG}"

# Docker build command (multiline for readability)
docker build --no-cache \
    --build-arg MODEL_NAME=$MODEL_NAME \
    --build-arg MODEL_TAG=$MODEL_TAG \
    --build-arg LICENSE=$LICENSE \
    --build-arg MODEL_SIZE=$MODEL_SIZE \
    --build-arg MEMORY_MIN=$MEMORY_MIN \
    --build-arg MEMORY_RECOMMENDED=$MEMORY_RECOMMENDED \
    --tag model-servers/ollama-server:$MODEL_NAME-$MODEL_TAG \
    --label org.opencontainers.image.title="Ollama Server - $MODEL_NAME" \
    --label org.opencontainers.image.description="Preloaded Ollama model server for $MODEL_NAME:$MODEL_TAG" \
    --label org.opencontainers.image.version="$MODEL_NAME-$MODEL_TAG" \
    --label org.opencontainers.image.authors="Sinan Ozel" \
    --label org.opencontainers.image.licenses=$LICENSE \
    --label org.opencontainers.image.vendor="sinanozel" \
    --label org.opencontainers.image.memory.size=$MODEL_SIZE \
    --label org.opencontainers.image.memory.min=$MEMORY_MIN \
    --label org.opencontainers.image.memory.recommended=$MEMORY_RECOMMENDED \
    --label org.opencontainers.image.date="$(date +'%Y-%m-%d')" \
    --file ./ollama/Dockerfile ./ollama

rm -rf ollama/model-cache/*