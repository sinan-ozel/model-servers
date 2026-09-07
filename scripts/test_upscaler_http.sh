#!/usr/bin/env bash
set -e

# Tests the async POST HTTP flow in isolation: upload -> job_id -> poll -> download.
# This is the exact flow documented as the example in upscaler/src/http/app.py's
# OpenAPI description. Runs on GPU by default; set UPSCALER_DEVICE=cpu to
# force CPU (e.g. if the GPU is busy or unavailable).

IMAGE_NAME="model-servers/upscaler:upscaler-realesrgan"
CONTAINER_NAME="upscaler-server-test"
PORT=8090

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all \
  -p "${PORT}:8080" \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME"

echo "Waiting for server..."
MAX_WAIT=60
WAITED=0
until curl -sf "http://localhost:${PORT}/status" | grep -q '"model_loaded":[ ]*true'; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo "❌ Container is no longer running"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Server did not become ready within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 1
  WAITED=$((WAITED+1))
done
echo "Server ready."

echo "Submitting upscale job (scale=4)..."
RESPONSE=$(curl -sf -F "file=@upscaler/tests/fixtures/sample.png" -F "scale=4" "http://localhost:${PORT}/v1/upscale")
echo "Response: $RESPONSE"
JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id')

if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
  echo "❌ No job_id returned"
  exit 1
fi

echo "Polling job $JOB_ID..."
MAX_WAIT=180
WAITED=0
while true; do
  STATUS_RESPONSE=$(curl -sf "http://localhost:${PORT}/v1/upscale/${JOB_ID}")
  STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
  echo "  status=$STATUS progress=$(echo "$STATUS_RESPONSE" | jq -r '.progress')"
  if [ "$STATUS" = "completed" ]; then
    break
  fi
  if [ "$STATUS" = "failed" ]; then
    echo "❌ Job failed: $STATUS_RESPONSE"
    exit 1
  fi
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Job did not complete within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 1
  WAITED=$((WAITED+1))
done

OUT_FILE="$(mktemp --suffix=.png)"
curl -sf "http://localhost:${PORT}/v1/upscale/${JOB_ID}/result" -o "$OUT_FILE"

DIMS=$(file "$OUT_FILE" | grep -o '[0-9]\+ x [0-9]\+')
rm -f "$OUT_FILE"
echo "Output dimensions: $DIMS"

if [ "$DIMS" != "256 x 192" ]; then
  echo "❌ Expected 256 x 192 (4x of the 64x48 fixture), got: $DIMS"
  exit 1
fi

echo "✓ HTTP flow OK"
