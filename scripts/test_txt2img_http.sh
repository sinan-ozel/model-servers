#!/usr/bin/env bash
set -e

# Tests the async POST HTTP flow in isolation: submit -> job_id -> poll -> download,
# and proves the job queue: two jobs submitted back to back, the second must
# come back queued behind the first (queue_position >= 1), deterministically
# (submission is synchronous, so this doesn't depend on GPU speed).
# Uses a small size/step count to keep the test's actual GPU work fast --
# model load on first request is the dominant cost regardless.
# All requests go via `docker exec` (hitting the container's own loopback)
# rather than a published port, so --network none can prove the image is
# truly self-contained (see test_txt2img_cli.sh for why that matters).

IMAGE_NAME="model-servers/txt2img:zimage-cuda"
CONTAINER_NAME="txt2img-server-test"

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all --network none \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME"

dexec() {
  docker exec "$CONTAINER_NAME" "$@"
}

echo "Waiting for server (model load can take a while on first start)..."
MAX_WAIT=300
WAITED=0
until dexec curl -sf "http://localhost:8080/status" | grep -q '"model_loaded":[ ]*true'; do
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}\$"; then
    echo "❌ Container is no longer running"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Server did not become ready within ${MAX_WAIT}s"
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED+2))
done
echo "Server ready."

BODY='{"prompt": "three cute cats playing", "width": 256, "height": 256, "steps": 4}'

echo "Submitting two generate jobs back to back, to check queueing..."
RESPONSE1=$(dexec curl -sf -X POST -H "Content-Type: application/json" -d "$BODY" "http://localhost:8080/v1/generate")
echo "Response 1: $RESPONSE1"
JOB1_ID=$(echo "$RESPONSE1" | jq -r '.job_id')

RESPONSE2=$(dexec curl -sf -X POST -H "Content-Type: application/json" -d "$BODY" "http://localhost:8080/v1/generate")
echo "Response 2: $RESPONSE2"
JOB2_ID=$(echo "$RESPONSE2" | jq -r '.job_id')
JOB2_QUEUE_POSITION=$(echo "$RESPONSE2" | jq -r '.queue_position')

if [ -z "$JOB1_ID" ] || [ "$JOB1_ID" = "null" ] || [ -z "$JOB2_ID" ] || [ "$JOB2_ID" = "null" ]; then
  echo "❌ No job_id returned"
  exit 1
fi

if [ "$JOB2_QUEUE_POSITION" -lt 1 ]; then
  echo "❌ Expected job 2 to be queued behind job 1 (queue_position >= 1), got: $JOB2_QUEUE_POSITION"
  exit 1
fi
echo "Job 2 correctly queued behind job 1 (queue_position=$JOB2_QUEUE_POSITION)."

wait_for_job() {
  local job_id="$1"
  local waited=0
  local max_wait=300
  while true; do
    local status_response
    status_response=$(dexec curl -sf "http://localhost:8080/v1/generate/${job_id}")
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
    sleep 2
    waited=$((waited+2))
  done
}

check_result() {
  local job_id="$1"
  local out_file
  out_file="$(mktemp --suffix=.png)"
  dexec curl -sf "http://localhost:8080/v1/generate/${job_id}/result" > "$out_file"
  local dims
  dims=$(file "$out_file" | grep -o '[0-9]\+ x [0-9]\+')
  rm -f "$out_file"
  echo "Job $job_id output dimensions: $dims"
  if [ "$dims" != "256 x 256" ]; then
    echo "❌ Expected 256 x 256, got: $dims"
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
