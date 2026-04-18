#!/usr/bin/env bash

set -e

# Usage: ./test_llamacpp_bundle.sh <bundle.yaml> [vram_gb]
# Example: ./test_llamacpp_bundle.sh bundles/llama.cuda.6gb.yaml 6
# vram_gb: 6 | 12 | 24  (default: 6)

if [ $# -lt 1 ]; then
  echo "Usage: $0 <bundle.yaml> [vram_gb]"
  echo "Example: $0 bundles/llama.cuda.6gb.yaml 6"
  exit 1
fi

BUNDLE_FILE="$1"
VRAM_GB="${2:-6}"

case "$VRAM_GB" in
  6)  VRAM_BUDGET_MiB=4608  ;;
  12) VRAM_BUDGET_MiB=10240 ;;
  24) VRAM_BUDGET_MiB=20480 ;;
  *)
    echo "❌ Error: unsupported vram_gb '$VRAM_GB'. Choose 6, 12, or 24."
    exit 1
    ;;
esac

if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq before running this script."
  exit 1
fi

if [ ! -f "$BUNDLE_FILE" ]; then
  echo "❌ Error: Bundle file not found: $BUNDLE_FILE"
  exit 1
fi

REPO=$(yq '.repo' "$BUNDLE_FILE")
TAG=$(yq '.tag' "$BUNDLE_FILE")
MODEL_COUNT=$(yq '.models | length' "$BUNDLE_FILE")
IMAGE_NAME="model-servers/llamacpp:$REPO-$TAG"
PORT=8080
PASS=0
FAIL=0
SKIPPED=0

echo "=== Testing llama.cpp Bundle ==="
echo "Bundle: $BUNDLE_FILE"
echo "Image:  $IMAGE_NAME"
echo "Models: $MODEL_COUNT"
echo "VRAM:   ${VRAM_GB}GB (budget ${VRAM_BUDGET_MiB} MiB)"
echo ""

_stop_container() {
  local name="$1"
  docker stop "$name" >/dev/null 2>&1 || true
  docker rm   "$name" >/dev/null 2>&1 || true
}

for i in $(seq 0 $((MODEL_COUNT - 1))); do
  MODEL_FILE=$(yq ".models[$i]" "$BUNDLE_FILE")

  if [ ! -f "$MODEL_FILE" ]; then
    echo "⚠ Skipping: model file not found: $MODEL_FILE"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  M_NAME=$(yq '.name' "$MODEL_FILE")
  M_TAG=$(yq '.tag' "$MODEL_FILE")
  GGUF_FILENAME=$(yq '.gguf.filename' "$MODEL_FILE")
  MMPROJ_FILENAME=$(yq '.gguf.mmproj.filename' "$MODEL_FILE")
  IS_EMBEDDING=$(yq '.embedding // "false"' "$MODEL_FILE")
  MODEL_ALIAS="${M_NAME}:${M_TAG}"

  if [ -z "$GGUF_FILENAME" ] || [ "$GGUF_FILENAME" = "null" ]; then
    echo "⚠ Skipping ${MODEL_ALIAS} — no gguf.filename defined"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  CONTAINER_NAME="llamacpp-bundle-test-${M_NAME}-${M_TAG}"

  echo "--- [$(( i + 1 ))/$MODEL_COUNT] ${MODEL_ALIAS} ---"
  echo "  GGUF:      $GGUF_FILENAME"
  echo "  Embedding: $IS_EMBEDDING"

  _stop_container "$CONTAINER_NAME"

  # Build runtime env for this model
  DOCKER_ENV="-e GGUF_FILENAME=$GGUF_FILENAME -e MODEL_ALIAS=$MODEL_ALIAS"
  [ "$IS_EMBEDDING" = "true" ] && DOCKER_ENV="$DOCKER_ENV -e EMBEDDING=true"
  if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ]; then
    DOCKER_ENV="$DOCKER_ENV -e MMPROJ_FILENAME=$MMPROJ_FILENAME"
  fi

  docker run -d \
    --name "$CONTAINER_NAME" \
    --gpus all \
    -p "${PORT}:${PORT}" \
    $DOCKER_ENV \
    "$IMAGE_NAME"

  # Wait for readiness
  if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ]; then
    INITIAL_WAIT=10
    MAX_ATTEMPTS=36
  else
    INITIAL_WAIT=5
    MAX_ATTEMPTS=24
  fi
  sleep $INITIAL_WAIT

  ATTEMPT=0
  READY=false
  TOTAL_WAIT=$INITIAL_WAIT
  while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
    if curl -sf "http://localhost:$PORT/health" >/dev/null 2>&1; then
      echo "  ✓ Ready (~${TOTAL_WAIT}s)"
      READY=true
      break
    fi
    ATTEMPT=$((ATTEMPT + 1))
    TOTAL_WAIT=$((TOTAL_WAIT + 5))
    sleep 5
  done

  if [ "$READY" != "true" ]; then
    echo "  ❌ Server did not become ready"
    docker logs --tail 20 "$CONTAINER_NAME"
    _stop_container "$CONTAINER_NAME"
    FAIL=$((FAIL + 1))
    echo ""
    continue
  fi

  # VRAM budget check
  VRAM_LINE=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -oP 'CUDA\d+ model buffer size\s*=\s*\K[0-9]+\.[0-9]+' | head -1)
  if [ -z "$VRAM_LINE" ]; then
    echo "  ⚠ VRAM check skipped — 'CUDA model buffer size' not found in logs"
  else
    VRAM_MiB=$(printf "%.0f" "$VRAM_LINE")
    if [ "$VRAM_MiB" -gt "$VRAM_BUDGET_MiB" ]; then
      echo "  ❌ VRAM: ${VRAM_MiB} MiB — exceeds ${VRAM_GB}GB budget of ${VRAM_BUDGET_MiB} MiB"
      _stop_container "$CONTAINER_NAME"
      FAIL=$((FAIL + 1))
      echo ""
      continue
    else
      echo "  ✓ VRAM: ${VRAM_MiB} MiB / ${VRAM_BUDGET_MiB} MiB ($(( VRAM_BUDGET_MiB - VRAM_MiB )) MiB spare)"
    fi
  fi

  # Inference test
  if [ "$IS_EMBEDDING" = "true" ]; then
    EMBED_RESPONSE=$(curl -sf --max-time 30 "http://localhost:$PORT/v1/embeddings" \
      -H "Content-Type: application/json" \
      -d "{\"input\": \"Hello world\", \"model\": \"$MODEL_ALIAS\"}") || {
      echo "  ❌ Embeddings: curl /v1/embeddings failed"
      docker logs --tail 10 "$CONTAINER_NAME"
      _stop_container "$CONTAINER_NAME"
      FAIL=$((FAIL + 1))
      echo ""
      continue
    }
    DIM=$(echo "$EMBED_RESPONSE" | jq '.data[0].embedding | length' 2>/dev/null || echo "0")
    if [ "${DIM:-0}" -gt 0 ]; then
      echo "  ✓ Embeddings: dimension $DIM"
      PASS=$((PASS + 1))
    else
      echo "  ❌ Embeddings: empty or invalid response: $EMBED_RESPONSE"
      FAIL=$((FAIL + 1))
    fi
  else
    RESPONSE=$(curl -sf --max-time 60 "http://localhost:$PORT/v1/chat/completions" \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"$MODEL_ALIAS\",
        \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France? Answer in one word.\"}],
        \"max_tokens\": 64,
        \"temperature\": 0
      }") || {
      echo "  ❌ Chat: curl /v1/chat/completions failed"
      docker logs --tail 10 "$CONTAINER_NAME"
      _stop_container "$CONTAINER_NAME"
      FAIL=$((FAIL + 1))
      echo ""
      continue
    }
    CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    if echo "$CONTENT" | grep -qi "paris"; then
      echo "  ✓ Chat: '$CONTENT'"
      PASS=$((PASS + 1))
    else
      echo "  ❌ Chat: expected 'paris', got: '$CONTENT'"
      FAIL=$((FAIL + 1))
    fi
  fi

  _stop_container "$CONTAINER_NAME"
  echo ""
done

echo "=== Bundle Test Results ==="
echo "  Passed:  $PASS / $((PASS + FAIL))"
[ "$SKIPPED" -gt 0 ] && echo "  Skipped: $SKIPPED"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "❌ Bundle test FAILED ($FAIL failure(s))"
  exit 1
else
  echo "✓ All models passed"
fi
