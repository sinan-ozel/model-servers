#!/usr/bin/env bash
set -e

# Tests the MCP flow over both transports the server exposes:
#  1. stdio            - spawns `python3 -m src.mcp.server` directly.
#  2. streamable-http    - hits /mcp on the running HTTP server, per the
#     streamable_http_path="/" mount documented in face-detector/src/http/app.py.
# Unlike upscaler, there is no "refuse while busy" leg -- detection is
# synchronous and stateless per call, no job queue to be busy with.

IMAGE_NAME="model-servers/face-detector:yunet-cpu"
CONTAINER_NAME="face-detector-mcp-test"
EXPECTED_FACE_COUNT=1

echo "Running MCP flow test over stdio..."
docker run --rm \
  --entrypoint python3 \
  -v "$(pwd)/face-detector/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_client_test.py /tests/fixtures/faces.png "$EXPECTED_FACE_COUNT"
echo "✓ MCP stdio flow OK"

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d --name "$CONTAINER_NAME" \
  -v "$(pwd)/face-detector/tests:/tests" \
  "$IMAGE_NAME"

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

echo "Running MCP flow test over streamable-http..."
docker exec "$CONTAINER_NAME" python3 /tests/mcp_http_client_test.py http://localhost:8080/mcp /tests/fixtures/faces.png "$EXPECTED_FACE_COUNT"
echo "✓ MCP streamable-http flow OK"
