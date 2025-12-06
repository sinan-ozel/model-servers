#!/usr/bin/env bash

set -e

MODEL_FILE="$1"
OLLAMA_VERSION="0.12.11"

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
MAX_CONTEXT_WINDOW=$(yq '.max_context_window' "$MODEL_FILE")


# Show parsed values
echo "${GREEN}Parsed model metadata:${NC}"
echo "  Name:              $MODEL_NAME"
echo "  Tag:               $MODEL_TAG"
echo "  License:           $LICENSE"
echo "  Model Size:        $MODEL_SIZE"
echo "  Memory Min:        $MEMORY_MIN"
echo "  Memory Rec.:       $MEMORY_RECOMMENDED"
echo "  Max Context Win.:  $MAX_CONTEXT_WINDOW"

# Ensure model cache directory exists
CACHE_PATH="/tmp/model-cache"
mkdir -p "$CACHE_PATH"
rm -rf "$CACHE_PATH"/*

# Preload model using Ollama container
# DEBUG: Find where models are actually downloading
echo "=== DEBUGGING MODEL DOWNLOAD LOCATION ==="
echo "Current working directory: $(pwd)"
echo "Cache path (inside devcontainer): $CACHE_PATH"
echo "Checking Docker host mount behavior..."

# Test where Docker actually mounts our volume
docker run --rm -v "$CACHE_PATH:/test-mount" alpine sh -c "echo 'Testing mount' && ls -la /test-mount && echo 'Mount test complete'"

echo "Starting model download with debugging..."
docker run --rm \
    --entrypoint sh \
    -v "$CACHE_PATH:/root/.ollama" \
    -e OLLAMA_ORCHESTRATOR=standalone \
    ollama/ollama:$OLLAMA_VERSION \
    -c "echo 'Container started, checking mount point:' && ls -la /root/.ollama && echo 'Starting ollama server...' && ollama serve & sleep 5 && echo 'Pulling model...' && ollama pull ${MODEL_NAME}:${MODEL_TAG} && echo 'Model pulled, checking files:' && find /root/.ollama -name '*.bin' -o -name '*blob*' | head -5 && echo 'Fixing ownership...' && chown $(id -u):$(id -g) /root/.ollama -R && echo 'Final contents:' && ls -la /root/.ollama"

echo "After download, checking host cache directory:"
ls -la "$CACHE_PATH"
echo "Searching for model files on host:"
find "$CACHE_PATH" -name "*${MODEL_TAG}*" -o -name "*blob*" 2>/dev/null || echo "No model files found in cache"

SAFE_NAME="${MODEL_NAME//\//-}"

# Copy model cache to Docker build context
echo "Copying model cache to Docker build context..."
rm -rf ollama/model-cache
cp -r "$CACHE_PATH" ollama/model-cache

# Docker build command (multiline for readability)
docker buildx build \
    --load \
    --no-cache \
    --build-arg MODEL_NAME=$MODEL_NAME \
    --build-arg MODEL_TAG=$MODEL_TAG \
    --build-arg LICENSE="$LICENSE" \
    --build-arg MODEL_SIZE="$MODEL_SIZE" \
    --build-arg MEMORY_MIN="$MEMORY_MIN" \
    --build-arg MEMORY_RECOMMENDED="$MEMORY_RECOMMENDED" \
    --build-arg MAX_CONTEXT_WINDOW="$MAX_CONTEXT_WINDOW" \
    --tag model-servers/ollama.$OLLAMA_VERSION:$SAFE_NAME-$MODEL_TAG \
    --label org.opencontainers.image.title="Ollama Server - $MODEL_NAME" \
    --label org.opencontainers.image.description="Preloaded Ollama model server for $MODEL_NAME:$MODEL_TAG" \
    --label org.opencontainers.image.version="$MODEL_NAME-$MODEL_TAG" \
    --label org.opencontainers.image.authors="Sinan Ozel" \
    --label org.opencontainers.image.licenses="$LICENSE" \
    --label org.opencontainers.image.vendor="sinanozel" \
    --label org.opencontainers.image.memory.size="$MODEL_SIZE" \
    --label org.opencontainers.image.memory.min="$MEMORY_MIN" \
    --label org.opencontainers.image.memory.recommended="$MEMORY_RECOMMENDED" \
    --label org.opencontainers.image.date="$(date +'%Y-%m-%d')" \
    --label org.opencontainers.image.source="https://github.com/sinan-ozel/model-servers" \
    --label org.opencontainers.image.url="https://github.com/sinan-ozel/model-servers" \
    --label org.opencontainers.image.documentation="https://github.com/sinan-ozel/model-servers" \
    --file ./ollama/Dockerfile ./ollama

rm -rf ollama/model-cache/*
