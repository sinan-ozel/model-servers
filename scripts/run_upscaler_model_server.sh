#!/usr/bin/env bash
set -e

# Usage: ./run_upscaler_model_server.sh [serve|mcp|upscale ...]
# With no arguments, starts the HTTP server on :8080.

IMAGE_NAME="model-servers/upscaler:realesrgan-cuda"

docker run --rm --gpus all \
  -p 8080:8080 \
  "$IMAGE_NAME" "$@"
