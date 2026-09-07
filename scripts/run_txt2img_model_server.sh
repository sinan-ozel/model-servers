#!/usr/bin/env bash
set -e

# Usage: ./run_txt2img_model_server.sh [serve|mcp|generate ...]
# With no arguments, starts the HTTP server on :8080.

IMAGE_NAME="model-servers/txt2img:zimage-cuda"

docker run --rm --gpus all \
  -p 8080:8080 \
  "$IMAGE_NAME" "$@"
