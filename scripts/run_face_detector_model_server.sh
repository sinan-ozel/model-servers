#!/usr/bin/env bash
set -e

# Usage: ./run_face_detector_model_server.sh [serve|mcp|detect ...]
# With no arguments, starts the HTTP server on :8080.

IMAGE_NAME="model-servers/face-detector:yunet-cpu"

docker run --rm \
  -p 8080:8080 \
  "$IMAGE_NAME" "$@"
