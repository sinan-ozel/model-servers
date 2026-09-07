#!/usr/bin/env bash
set -e

# Tests the MCP flow in isolation, over both transports the server exposes,
# plus the "refuse while a job is in flight" behavior:
#  1. stdio             - spawns `python3 -m src.mcp.server` directly (this
#     loads its own pipeline from scratch -- slow, expect a long first wait).
#  2. streamable-http    - hits /mcp on the running HTTP server (already
#     warm, since the HTTP app loads the pipeline at startup).
#  3. refuse-while-busy  - submits a job via POST /v1/generate, then
#     immediately calls the MCP tool and expects it to refuse (not queue or
#     block), naming that job's id -- see txt2img/src/mcp/server.py.
# (2) and (3) run via `docker exec` into the same warm server container, so
# client startup overhead can't eat the window before the small test job
# finishes.
# --network none on both containers proves the image is truly self-contained
# (see test_txt2img_cli.sh for why that matters); everything here goes
# through `docker exec`/entrypoint invocation, none of it needs a published
# port, so isolating the network doesn't break anything.

IMAGE_NAME="model-servers/txt2img:zimage-cuda"
CONTAINER_NAME="txt2img-mcp-test"

echo "Running MCP flow test over stdio (this loads its own pipeline -- can take a while)..."
docker run --rm --gpus all --network none \
  --entrypoint python3 \
  -v "$(pwd)/txt2img/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_client_test.py "three cute cats playing" 256 256 4
echo "✓ MCP stdio flow OK"

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all --network none --name "$CONTAINER_NAME" \
  -v "$(pwd)/txt2img/tests:/tests" \
  "$IMAGE_NAME"

echo "Waiting for server (model load can take a while on first start)..."
MAX_WAIT=300
WAITED=0
until docker exec "$CONTAINER_NAME" curl -sf http://localhost:8080/status | grep -q '"model_loaded":[ ]*true'; do
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Server did not become ready within ${MAX_WAIT}s"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED+2))
done

echo "Submitting a job, then immediately calling the MCP tool (expecting a refusal)..."
RESPONSE=$(docker exec "$CONTAINER_NAME" curl -sf -X POST -H "Content-Type: application/json" \
  -d '{"prompt": "three cute cats playing", "width": 256, "height": 256, "steps": 4}' \
  http://localhost:8080/v1/generate)
JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id')
if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
  echo "❌ No job_id returned: $RESPONSE"
  exit 1
fi
docker exec "$CONTAINER_NAME" python3 /tests/mcp_refuse_test.py http://localhost:8080/mcp "$JOB_ID"
echo "✓ MCP refuse-while-busy OK"

echo "Waiting for that job to finish before the next check..."
MAX_WAIT=300
WAITED=0
while true; do
  STATUS=$(docker exec "$CONTAINER_NAME" curl -sf "http://localhost:8080/v1/generate/${JOB_ID}" | jq -r '.status')
  if [ "$STATUS" = "completed" ] || [ "$STATUS" = "failed" ]; then
    break
  fi
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Job did not finish within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED+2))
done

echo "Running MCP flow test over streamable-http, queue now idle..."
docker exec "$CONTAINER_NAME" python3 /tests/mcp_http_client_test.py http://localhost:8080/mcp "three cute cats playing" 256 256 4
echo "✓ MCP streamable-http flow OK"
