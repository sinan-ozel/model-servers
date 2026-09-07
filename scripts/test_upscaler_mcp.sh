#!/usr/bin/env bash
set -e

# Tests the MCP flow in isolation: spawns `python3 -m src.mcp.server` over
# stdio inside the image and calls the upscale_image tool, exactly as
# documented in the tool's docstring in upscaler/src/mcp/server.py.
# Runs on GPU by default; set UPSCALER_DEVICE=cpu to force CPU (e.g. if the
# GPU is busy or unavailable).

IMAGE_NAME="model-servers/upscaler:upscaler-realesrgan"

echo "Running MCP flow test (scale=4)..."
docker run --rm --gpus all \
  --entrypoint python3 \
  -v "$(pwd)/upscaler/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_client_test.py /tests/fixtures/sample.png 4

echo "✓ MCP flow OK"
