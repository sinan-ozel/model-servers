#!/usr/bin/env bash
set -e

# Tests the synchronous POST HTTP flow: one call, full result inline. No
# job_id/poll/download legs -- there is no job queue for this pipeline.

IMAGE_NAME="model-servers/face-detector:yunet-cpu"
CONTAINER_NAME="face-detector-server-test"
PORT=8093
EXPECTED_FACE_COUNT=1

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d \
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

echo "Submitting a detection request..."
RESPONSE=$(curl -sf -F "file=@face-detector/tests/fixtures/faces.png" -F "score_threshold=0.5" "http://localhost:${PORT}/v1/detect")

FACE_COUNT=$(echo "$RESPONSE" | jq '.faces | length')
echo "Detected faces: $FACE_COUNT"
if [ "$FACE_COUNT" != "$EXPECTED_FACE_COUNT" ]; then
  echo "❌ Expected $EXPECTED_FACE_COUNT face(s), got: $FACE_COUNT"
  exit 1
fi

THUMB_FILE="$(mktemp --suffix=.png)"
echo "$RESPONSE" | jq -r '.faces[0].thumbnail_base64' | base64 -d > "$THUMB_FILE"
DIMS=$(file "$THUMB_FILE" | grep -o '[0-9]\+ x [0-9]\+')
rm -f "$THUMB_FILE"
echo "Thumbnail dimensions: $DIMS"
if [ "$DIMS" != "256 x 256" ]; then
  echo "❌ Expected 256 x 256 thumbnail, got: $DIMS"
  exit 1
fi

echo "✓ HTTP flow OK (synchronous, no job queue)"
