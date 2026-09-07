#!/usr/bin/env bash
set -e

# Tests the MCP flow in isolation, over both transports the server exposes,
# plus the "refuse while a job is in flight" behavior:
#  1. stdio             - spawns `python3 -m src.mcp.server` directly.
#  2. streamable-http    - hits /mcp on the running HTTP server, per the
#     streamable_http_path="/" mount documented in upscaler/src/http/app.py.
#  3. refuse-while-busy  - submits a job via POST /v1/upscale, then
#     immediately calls the MCP tool and expects it to refuse (not queue or
#     block), naming that job's id -- see upscaler/src/mcp/server.py.
# All calls in (2) and (3) run via `docker exec` into the same warm server
# container, so client startup overhead can't eat the ~1s window before the
# tiny fixture job finishes. Runs on GPU by default; set UPSCALER_DEVICE=cpu
# to force CPU (e.g. if the GPU is busy or unavailable).

IMAGE_NAME="model-servers/upscaler:realesrgan-cuda"
CONTAINER_NAME="upscaler-mcp-test"

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

docker run -d --gpus all --name "$CONTAINER_NAME" \
  -v "$(pwd)/upscaler/tests:/tests" \
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

echo "Submitting a job, then immediately calling the MCP tool (expecting a refusal)..."
RESPONSE=$(docker exec "$CONTAINER_NAME" curl -sf -F "file=@/tests/fixtures/sample.png" -F "scale=4" http://localhost:8080/v1/upscale)
JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id')
if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
  echo "❌ No job_id returned: $RESPONSE"
  exit 1
fi
docker exec "$CONTAINER_NAME" python3 /tests/mcp_refuse_test.py http://localhost:8080/mcp "$JOB_ID"
echo "✓ MCP refuse-while-busy OK"

echo "Waiting for that job to finish before the next check..."
MAX_WAIT=60
WAITED=0
while true; do
  STATUS=$(docker exec "$CONTAINER_NAME" curl -sf "http://localhost:8080/v1/upscale/${JOB_ID}" | jq -r '.status')
  if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
    break
  fi
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Job did not finish within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 1
  WAITED=$((WAITED+1))
done

echo "Running MCP flow test over streamable-http, queue now idle (scale=4)..."
docker exec "$CONTAINER_NAME" python3 /tests/mcp_http_client_test.py http://localhost:8080/mcp /tests/fixtures/sample.png 4
echo "✓ MCP streamable-http flow OK"
