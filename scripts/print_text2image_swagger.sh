#!/usr/bin/env bash
set -e

VERSION="0.1.0"

MODEL_PUBLISHER="CompVis"
MODEL_NAME="stable-diffusion-v1-4"

docker stop text2image-server || true
docker rm text2image-server || true

docker run -d \
    --gpus all \
    -p 8000:8000 \
    --name text2image-server \
    model-servers/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME}

# Wait for server to become available
echo "Waiting for API to become ready..."
until curl -sf http://localhost:8000/openapi.json >/dev/null 2>&1; do
    sleep 1
done

# Create output folder
OUTDIR="swagger"
mkdir -p "$OUTDIR"

# Download Swagger / OpenAPI spec
curl -s http://localhost:8000/openapi.json -o "${OUTDIR}/openapi.json"

echo "Swagger saved to ${OUTDIR}/openapi.json"
