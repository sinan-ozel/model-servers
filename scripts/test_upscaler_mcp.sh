#!/usr/bin/env bash
set -e

# Tests the MCP flow in isolation, over both transports the server exposes:
#  1. stdio    - spawns `python3 -m src.mcp.server` directly.
#  2. streamable-http - hits /mcp on the same HTTP server used by
#     scripts/test_upscaler_http.sh, per the streamable_http_path="/"
#     mount documented in upscaler/src/http/app.py.
# Both call upscale_image exactly as documented in the tool's docstring in
# upscaler/src/mcp/server.py. Runs on GPU by default; set UPSCALER_DEVICE=cpu
# to force CPU (e.g. if the GPU is busy or unavailable).

IMAGE_NAME="model-servers/upscaler:realesrgan-cuda"
CONTAINER_NAME="upscaler-mcp-http-test"

echo "Running MCP flow test over stdio (scale=4)..."
docker run --rm --gpus all \
  --entrypoint python3 \
  -v "$(pwd)/upscaler/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_client_test.py /tests/fixtures/sample.png 4
echo "✓ MCP stdio flow OK"

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all --name "$CONTAINER_NAME" "$IMAGE_NAME"

echo "Waiting for server..."
MAX_WAIT=60
WAITED=0
until docker exec "$CONTAINER_NAME" curl -sf http://localhost:8080/status | grep -q '"model_loaded":[ ]*true'; do
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Server did not become ready within ${MAX_WAIT}s"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  sleep 1
  WAITED=$((WAITED+1))
done

echo "Running MCP flow test over streamable-http (scale=4)..."
docker run --rm \
  --network "container:${CONTAINER_NAME}" \
  --entrypoint python3 \
  -v "$(pwd)/upscaler/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_http_client_test.py http://localhost:8080/mcp /tests/fixtures/sample.png 4
echo "✓ MCP streamable-http flow OK"
