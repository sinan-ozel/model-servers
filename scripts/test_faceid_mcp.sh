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
#     block), naming that job's id -- see faceid/src/mcp/server.py.
# (2) and (3) run via `docker exec` into the same warm server container, so
# client startup overhead can't eat the window before the small test job
# finishes.
# --network none on both containers proves the image is truly self-contained
# (see test_faceid_cli.sh for why that matters); everything here goes
# through `docker exec`/entrypoint invocation, none of it needs a published
# port, so isolating the network doesn't break anything.

IMAGE_NAME="model-servers/faceid:photomaker-sdxl-cuda"
CONTAINER_NAME="faceid-mcp-test"

echo "Running MCP flow test over stdio (this loads its own pipeline -- can take a while)..."
docker run --rm --gpus all --network none \
  --entrypoint python3 \
  -v "$(pwd)/faceid/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_client_test.py /tests/fixtures/id_face.png 256 256 4
echo "✓ MCP stdio flow OK"

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -f "${ID_IMAGE_B64_FILE:-}" "${BODY_FILE:-}" 2>/dev/null || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all --network none --name "$CONTAINER_NAME" \
  -v "$(pwd)/faceid/tests:/tests" \
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
# jq --arg can't take a base64 blob this large as a command-line argument
# (ARG_MAX) -- use --rawfile to read it from a file instead, and copy the
# resulting body into the container so curl can read it with -d @file
# rather than inlining it as an argument (same ARG_MAX limit applies there).
ID_IMAGE_B64_FILE="$(mktemp)"
docker exec "$CONTAINER_NAME" base64 -w0 /tests/fixtures/id_face.png > "$ID_IMAGE_B64_FILE"
BODY_FILE="$(mktemp)"
jq -n --rawfile b64 "$ID_IMAGE_B64_FILE" \
  '{"prompt": "a professional headshot photo of a person img", "id_images": [$b64], "width": 256, "height": 256, "steps": 4}' \
  > "$BODY_FILE"
docker cp "$BODY_FILE" "$CONTAINER_NAME:/tmp/body.json"
RESPONSE=$(docker exec "$CONTAINER_NAME" curl -sf -X POST -H "Content-Type: application/json" \
  -d @/tmp/body.json http://localhost:8080/v1/generate)
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
docker exec "$CONTAINER_NAME" python3 /tests/mcp_http_client_test.py http://localhost:8080/mcp /tests/fixtures/id_face.png 256 256 4
echo "✓ MCP streamable-http flow OK"
