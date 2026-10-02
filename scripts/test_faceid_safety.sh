#!/usr/bin/env bash
set -e

# Tests the safety-checker refusal wiring across CLI/HTTP/MCP, using
# SAFETY_CHECKER=always_refuse (see faceid/src/lib/safety.py) instead of a
# real flagged image: this deliberately does NOT try to generate or store
# actual NSFW content just to test plumbing. What's being verified is our
# own mapping of ContentRefusedError onto each surface's convention (see
# ContentRefusedError's docstring) -- not the classifier's own accuracy,
# which is Falconsai's concern (already benchmarked at ~98% on their eval
# set), not ours.

IMAGE_NAME="model-servers/faceid:photomaker-sdxl-cuda"

echo "=== CLI: expect exit code 2 and a 'Refused:' message ==="
OUT_DIR="$(mktemp -d)"
cp faceid/tests/fixtures/id_face.png "$OUT_DIR/id_face.png"
set +e
docker run --rm --gpus all --network none \
  -e SAFETY_CHECKER=always_refuse \
  -v "$OUT_DIR:/data" \
  "$IMAGE_NAME" generate \
    --prompt "a professional headshot photo of a person img" \
    --id-image /data/id_face.png \
    --width 256 --height 256 --steps 4 \
    --output /data/out.png 2>"$OUT_DIR/stderr.txt"
CLI_EXIT=$?
set -e
if [ "$CLI_EXIT" -ne 2 ]; then
  echo "❌ Expected exit code 2, got: $CLI_EXIT"
  cat "$OUT_DIR/stderr.txt"
  exit 1
fi
if ! grep -q "^Refused:" "$OUT_DIR/stderr.txt"; then
  echo "❌ Expected a 'Refused:' line on stderr:"
  cat "$OUT_DIR/stderr.txt"
  exit 1
fi
if [ -f "$OUT_DIR/out.png" ]; then
  echo "❌ Refused content should not have been written to disk"
  exit 1
fi
rm -rf "$OUT_DIR"
echo "✓ CLI refusal OK"

echo ""
echo "=== MCP (stdio): expect isError=True naming the safety checker ==="
# Standalone container, not `docker exec` into the HTTP server container
# below -- stdio MCP always loads its own fresh pipeline in a new process,
# and two pipelines loaded at once doesn't fit in 12GB of VRAM.
docker run --rm --gpus all --network none \
  -e SAFETY_CHECKER=always_refuse \
  --entrypoint python3 \
  -v "$(pwd)/faceid/tests:/tests" \
  "$IMAGE_NAME" /tests/mcp_safety_test.py
echo "✓ MCP refusal OK"

echo ""
echo "=== HTTP: starting a server with SAFETY_CHECKER=always_refuse ==="
CONTAINER_NAME="faceid-safety-test"
cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
  rm -f "${ID_IMAGE_B64_FILE:-}" "${BODY_FILE:-}" 2>/dev/null || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all --network none \
  -e SAFETY_CHECKER=always_refuse \
  -v "$(pwd)/faceid/tests/fixtures:/fixtures:ro" \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME"

dexec() {
  docker exec "$CONTAINER_NAME" "$@"
}

echo "Waiting for server..."
MAX_WAIT=300
WAITED=0
until dexec curl -sf "http://localhost:8080/status" | grep -q '"model_loaded":[ ]*true'; do
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ Server did not become ready within ${MAX_WAIT}s"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED+2))
done

echo "=== HTTP: submit a job, expect it to fail with content_policy_violation ==="
# jq --arg can't take a base64 blob this large as a command-line argument
# (ARG_MAX) -- use --rawfile to read it from a file instead, and copy the
# resulting body into the container so curl can read it with -d @file
# rather than inlining it as an argument (same ARG_MAX limit applies there).
ID_IMAGE_B64_FILE="$(mktemp)"
dexec base64 -w0 /fixtures/id_face.png > "$ID_IMAGE_B64_FILE"
BODY_FILE="$(mktemp)"
jq -n --rawfile b64 "$ID_IMAGE_B64_FILE" \
  '{"prompt": "a professional headshot photo of a person img", "id_images": [$b64], "width": 256, "height": 256, "steps": 4}' \
  > "$BODY_FILE"
docker cp "$BODY_FILE" "$CONTAINER_NAME:/tmp/body.json"
RESPONSE=$(dexec curl -sf -X POST -H "Content-Type: application/json" -d @/tmp/body.json "http://localhost:8080/v1/generate")
JOB_ID=$(echo "$RESPONSE" | jq -r '.job_id')
if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
  echo "❌ No job_id returned: $RESPONSE"
  exit 1
fi

WAITED=0
while true; do
  STATUS_RESPONSE=$(dexec curl -sf "http://localhost:8080/v1/generate/${JOB_ID}")
  STATUS=$(echo "$STATUS_RESPONSE" | jq -r '.status')
  if [ "$STATUS" = "failed" ]; then
    break
  fi
  if [ "$STATUS" = "completed" ]; then
    echo "❌ Expected the job to fail (safety refusal), but it completed: $STATUS_RESPONSE"
    exit 1
  fi
  if [ "$WAITED" -ge 300 ]; then
    echo "❌ Job did not finish within 300s"
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED+2))
done

ERROR_CODE=$(echo "$STATUS_RESPONSE" | jq -r '.error_code')
if [ "$ERROR_CODE" != "content_policy_violation" ]; then
  echo "❌ Expected error_code=content_policy_violation, got: $STATUS_RESPONSE"
  exit 1
fi

RESULT_STATUS=$(dexec curl -s -o /dev/null -w '%{http_code}' "http://localhost:8080/v1/generate/${JOB_ID}/result")
if [ "$RESULT_STATUS" != "400" ]; then
  echo "❌ Expected GET .../result to return 400, got: $RESULT_STATUS"
  exit 1
fi
RESULT_BODY=$(dexec curl -s "http://localhost:8080/v1/generate/${JOB_ID}/result")
RESULT_CODE=$(echo "$RESULT_BODY" | jq -r '.detail.code')
if [ "$RESULT_CODE" != "content_policy_violation" ]; then
  echo "❌ Expected result body's detail.code=content_policy_violation, got: $RESULT_BODY"
  exit 1
fi
echo "✓ HTTP refusal OK (job failed with error_code, GET .../result returned 400)"

echo ""
echo "✓ Safety checker refusal wiring OK across CLI/HTTP/MCP"
