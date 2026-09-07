#!/usr/bin/env bash
set -e

# Tests the async POST HTTP flow in isolation: upload -> job_id -> poll -> download.
# This is the exact flow documented as the example in upscaler/src/http/app.py's
# OpenAPI description. Runs on GPU by default; set UPSCALER_DEVICE=cpu to
# force CPU (e.g. if the GPU is busy or unavailable).

IMAGE_NAME="model-servers/upscaler:realesrgan-cuda"
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

echo "Submitting two upscale jobs back to back (scale=4), to check queueing..."
RESPONSE1=$(curl -sf -F "file=@upscaler/tests/fixtures/sample.png" -F "scale=4" "http://localhost:${PORT}/v1/upscale")
echo "Response 1: $RESPONSE1"
JOB1_ID=$(echo "$RESPONSE1" | jq -r '.job_id')

RESPONSE2=$(curl -sf -F "file=@upscaler/tests/fixtures/sample.png" -F "scale=4" "http://localhost:${PORT}/v1/upscale")
echo "Response 2: $RESPONSE2"
JOB2_ID=$(echo "$RESPONSE2" | jq -r '.job_id')
JOB2_QUEUE_POSITION=$(echo "$RESPONSE2" | jq -r '.queue_position')

if [ -z "$JOB1_ID" ] || [ "$JOB1_ID" = "null" ] || [ -z "$JOB2_ID" ] || [ "$JOB2_ID" = "null" ]; then
  echo "❌ No job_id returned"
  exit 1
fi

# Submission is synchronous (registers in the queue before responding), so
# this is deterministic regardless of how fast the GPU processes job 1.
if [ "$JOB2_QUEUE_POSITION" -lt 1 ]; then
  echo "❌ Expected job 2 to be queued behind job 1 (queue_position >= 1), got: $JOB2_QUEUE_POSITION"
  exit 1
fi
echo "Job 2 correctly queued behind job 1 (queue_position=$JOB2_QUEUE_POSITION)."

wait_for_job() {
  local job_id="$1"
  local waited=0
  local max_wait=180
  while true; do
    local status_response
    status_response=$(curl -sf "http://localhost:${PORT}/v1/upscale/${job_id}")
    local status
    status=$(echo "$status_response" | jq -r '.status')
    echo "  job=$job_id status=$status progress=$(echo "$status_response" | jq -r '.progress') queue_position=$(echo "$status_response" | jq -r '.queue_position')"
    if [ "$status" = "completed" ]; then
      return 0
    fi
    if [ "$status" = "failed" ]; then
      echo "❌ Job $job_id failed: $status_response"
      exit 1
    fi
    if [ "$waited" -ge "$max_wait" ]; then
      echo "❌ Job $job_id did not complete within ${max_wait}s"
      exit 1
    fi
    sleep 1
    waited=$((waited+1))
  done
}

check_result() {
  local job_id="$1"
  local out_file
  out_file="$(mktemp --suffix=.png)"
  curl -sf "http://localhost:${PORT}/v1/upscale/${job_id}/result" -o "$out_file"
  local dims
  dims=$(file "$out_file" | grep -o '[0-9]\+ x [0-9]\+')
  rm -f "$out_file"
  echo "Job $job_id output dimensions: $dims"
  if [ "$dims" != "256 x 192" ]; then
    echo "❌ Expected 256 x 192 (4x of the 64x48 fixture), got: $dims"
    exit 1
  fi
}

echo "Polling job 1..."
wait_for_job "$JOB1_ID"
check_result "$JOB1_ID"

echo "Polling job 2 (should now run and complete in turn)..."
wait_for_job "$JOB2_ID"
check_result "$JOB2_ID"

echo "✓ HTTP flow OK (including one-at-a-time job queue)"
