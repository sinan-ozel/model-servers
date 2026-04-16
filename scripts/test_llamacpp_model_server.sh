#!/usr/bin/env bash

set -e

# Usage: ./test_llamacpp_model_server.sh <model_metadata.yaml> [vram_gb]
# Example: ./test_llamacpp_model_server.sh model_metadata/gemma3_270m.yaml 6
# vram_gb: 6 | 12 | 24  (default: 6)

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml> [vram_gb]"
  echo "Example: $0 model_metadata/gemma3_270m.yaml 6"
  exit 1
fi

MODEL_FILE="$1"
VRAM_GB="${2:-6}"

# Model weight budget per VRAM tier — remainder covers KV cache + CUDA overhead
case "$VRAM_GB" in
  6)  VRAM_BUDGET_MiB=4608  ;;  # leaves ~1.5 GB for KV cache + overhead
  12) VRAM_BUDGET_MiB=10240 ;;  # leaves ~2 GB
  24) VRAM_BUDGET_MiB=20480 ;;  # leaves ~4 GB
  *)
    echo "❌ Error: unsupported vram_gb '$VRAM_GB'. Choose 6, 12, or 24."
    exit 1
    ;;
esac

# Check if yq is installed
if ! command -v yq &> /dev/null; then
  echo "Error: yq is not installed. Please install yq before running this script."
  exit 1
fi

# Check if model file exists
if [ ! -f "$MODEL_FILE" ]; then
  echo "❌ Error: Model metadata file not found: $MODEL_FILE"
  exit 1
fi

# Extract values using yq
MODEL_NAME=$(yq '.name' "$MODEL_FILE")
MODEL_TAG=$(yq '.tag' "$MODEL_FILE")
MMPROJ_FILENAME=$(yq '.gguf.mmproj.filename' "$MODEL_FILE")
WHISPER_FILENAME=$(yq '.gguf.whisper.filename' "$MODEL_FILE")

# Validate fields
if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" = "null" ]; then
  echo "❌ Error: Missing 'name' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$MODEL_TAG" ] || [ "$MODEL_TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $MODEL_FILE"
  exit 1
fi

HAS_MMPROJ=false
if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ]; then
  HAS_MMPROJ=true
fi

HAS_WHISPER=false
if [ -n "$WHISPER_FILENAME" ] && [ "$WHISPER_FILENAME" != "null" ]; then
  HAS_WHISPER=true
fi

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
IMAGE_NAME="model-servers/llamacpp:$IMAGE_TAG"
CONTAINER_NAME="llamacpp-test-$IMAGE_TAG"
PORT=8080

echo "=== Testing llama.cpp Model Server ==="
echo "Model file: $MODEL_FILE"
echo "Image: $IMAGE_NAME"
echo "Port: $PORT"
echo "Vision (mmproj): $HAS_MMPROJ"
echo "Audio (whisper): $HAS_WHISPER"
echo ""

echo "=== Test 0: Image Label — Model Identifier ==="
LABELS=$(docker inspect --format '{{json .Config.Labels}}' "$IMAGE_NAME" 2>/dev/null) || {
  echo "❌ Test 0: docker inspect failed — image may not exist: $IMAGE_NAME"
  exit 1
}
MODEL_IDENTIFIER="${MODEL_NAME}:${MODEL_TAG}"
if echo "$LABELS" | grep -q "\"${MODEL_IDENTIFIER}\""; then
  echo "✓ Test 0: model identifier '${MODEL_IDENTIFIER}' found in image labels"
else
  echo "❌ Test 0: model identifier '${MODEL_IDENTIFIER}' not found in image labels"
  echo "  Labels: $LABELS"
  exit 1
fi
echo ""

# Check if container is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Stopping and removing existing container..."
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Start container in background
echo "Starting container..."
WHISPER_PORT=8081
docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  -p "$PORT:$PORT" \
  -p "$WHISPER_PORT:$WHISPER_PORT" \
  "$IMAGE_NAME"

echo "Container started. Waiting for server to be ready..."
if [ "$HAS_MMPROJ" = true ]; then
  echo "  Note: vision model (mmproj) detected — startup includes a clip/vision warmup"
  echo "  phase that can take 1-3 minutes. This is normal. Please be patient."
  INITIAL_WAIT=10
  MAX_ATTEMPTS=36   # up to 3 minutes
else
  INITIAL_WAIT=5
  MAX_ATTEMPTS=24   # up to 2 minutes
fi
sleep $INITIAL_WAIT

# Wait for server to be ready
ATTEMPT=0
TOTAL_WAIT=$INITIAL_WAIT
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -sf http://localhost:$PORT/health >/dev/null 2>&1; then
    echo "✓ Server is ready! (waited ~${TOTAL_WAIT}s)"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  TOTAL_WAIT=$((TOTAL_WAIT + 5))
  echo "Waiting... ($ATTEMPT/$MAX_ATTEMPTS, ~${TOTAL_WAIT}s elapsed)"
  if [ "$HAS_MMPROJ" = true ] && [ $ATTEMPT -eq 12 ]; then
    echo "  Still loading — vision warmup in progress, this is expected."
  fi
  sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "❌ Server did not become ready in time."
  echo "   If this is a vision model (mmproj), try increasing MAX_ATTEMPTS in this script."
  docker logs --tail 30 "$CONTAINER_NAME"
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1
  exit 1
fi

echo ""
echo "=== VRAM Budget Check (${VRAM_GB}GB tier) ==="
VRAM_LINE=$(docker logs "$CONTAINER_NAME" 2>&1 | grep -oP 'CUDA\d+ model buffer size\s*=\s*\K[0-9]+\.[0-9]+' | head -1)
if [ -z "$VRAM_LINE" ]; then
  echo "⚠ VRAM check skipped — 'CUDA model buffer size' not found in logs (CPU-only run?)"
else
  VRAM_MiB=$(printf "%.0f" "$VRAM_LINE")
  if [ "$VRAM_MiB" -gt "$VRAM_BUDGET_MiB" ]; then
    _fail "VRAM check" "model uses ${VRAM_MiB} MiB on GPU — exceeds 6GB budget of ${VRAM_BUDGET_MiB} MiB (no room for KV cache)"
  else
    echo "✓ VRAM check: model uses ${VRAM_MiB} MiB of ${VRAM_BUDGET_MiB} MiB budget ($(( VRAM_BUDGET_MiB - VRAM_MiB )) MiB remaining for KV cache)"
  fi
fi

echo ""
echo "=== Testing Model Inference ==="
echo ""

# Helper: stop container and exit with failure
_fail() {
  local label="$1"
  local message="$2"
  echo "❌ $label: $message"
  docker logs --tail 30 "$CONTAINER_NAME"
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1
  exit 1
}

# Test 1 (pre): /v1/models returns the expected model identifier
echo "Test 1 (pre): /v1/models lists '${MODEL_NAME}:${MODEL_TAG}'"
MODELS_RESPONSE=$(curl -sf --max-time 10 http://localhost:$PORT/v1/models) \
  || _fail "Test 1 (pre)" "curl /v1/models failed"
if echo "$MODELS_RESPONSE" | grep -q "\"${MODEL_NAME}:${MODEL_TAG}\""; then
  echo "✓ Test 1 (pre): model identifier '${MODEL_NAME}:${MODEL_TAG}' found in /v1/models"
else
  echo "❌ Test 1 (pre): '${MODEL_NAME}:${MODEL_TAG}' not found in /v1/models response:"
  echo "$MODELS_RESPONSE"
  _fail "Test 1 (pre)" "model identifier missing from /v1/models"
fi
echo ""

# Helper: assert response contains expected string (case-insensitive)
_assert_contains() {
  local label="$1"
  local text="$2"
  local expected="$3"
  if echo "$text" | grep -qi "$expected"; then
    echo "✓ $label: response contains '$expected'"
  else
    echo "❌ $label: expected '$expected' in response, got:"
    echo "$text"
    _fail "$label" "assertion failed"
  fi
}

# Test 1: Native completion endpoint
echo "Test 1: Native /completion endpoint"
RESPONSE=$(curl -sf --max-time 60 http://localhost:$PORT/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is the capital of France? Answer in one word.",
    "n_predict": 100,
    "temperature": 0
  }') || _fail "Test 1" "curl request failed (HTTP error or timeout)"
CONTENT=$(echo "$RESPONSE" | jq -r '.content // .text // empty' 2>/dev/null)
if [ -z "$CONTENT" ]; then
  _fail "Test 1" "empty or unparseable response: $RESPONSE"
fi
echo "Response: $CONTENT"
_assert_contains "Test 1" "$CONTENT" "paris"
echo ""

# Test 2: OpenAI-compatible chat completions endpoint
echo "Test 2: OpenAI-compatible /v1/chat/completions endpoint"
RESPONSE=$(curl -sf --max-time 120 http://localhost:$PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}:${MODEL_TAG}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France? Answer in one word.\"}],
    \"max_tokens\": 2048,
    \"temperature\": 0
  }") || _fail "Test 2" "curl request failed (HTTP error or timeout)"
# Reasoning models (e.g. Qwen3, DeepSeek-R1) put the final answer in content
# and chain-of-thought in reasoning_content. Fall back to reasoning_content only
# when content is absent, as it may still contain the answer for some models.
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
if [ -z "$CONTENT" ]; then
  CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.reasoning_content // empty' 2>/dev/null)
fi
if [ -z "$CONTENT" ]; then
  _fail "Test 2" "empty or unparseable response: $RESPONSE"
fi
echo "Response: $CONTENT"
_assert_contains "Test 2" "$CONTENT" "paris"
echo ""

# Test 3: Vision / image test (only if model has mmproj)
if [ "$HAS_MMPROJ" = true ]; then
  echo "Test 3: Vision — image description via /v1/chat/completions"

  # Generate a solid red 32x32 PNG inline using python3
  SIMPLE_IMG_B64=$(python3 - <<'PYEOF'
import base64, zlib, struct
w, h = 32, 32
raw = b''.join(b'\x00' + bytes([255, 0, 0] * w) for _ in range(h))
ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
def chunk(t, d):
    c = t + d
    return struct.pack('>I', len(d)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', ihdr) + chunk(b'IDAT', zlib.compress(raw)) + chunk(b'IEND', b'')
print(base64.b64encode(png).decode())
PYEOF
)

  if [ -z "$SIMPLE_IMG_B64" ]; then
    echo "⚠ Skipping Test 3: python3 unavailable for image generation"
  else
    RESPONSE=$(curl -sf --max-time 180 http://localhost:$PORT/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d "{
        \"model\": \"${MODEL_NAME}:${MODEL_TAG}\",
        \"messages\": [{
          \"role\": \"user\",
          \"content\": [
            {\"type\": \"image_url\", \"image_url\": {\"url\": \"data:image/png;base64,${SIMPLE_IMG_B64}\"}},
            {\"type\": \"text\", \"text\": \"What color is this image? Answer in one word.\"}
          ]
        }],
        \"max_tokens\": 2048,
        \"temperature\": 0
      }") || _fail "Test 3" "curl request failed (HTTP error or timeout)"
    CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
    if [ -z "$CONTENT" ]; then
      CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.reasoning_content // empty' 2>/dev/null)
    fi
    if [ -z "$CONTENT" ]; then
      _fail "Test 3" "empty or unparseable response: $RESPONSE"
    fi
    echo "Response: $CONTENT"
    _assert_contains "Test 3" "$CONTENT" "red"
    echo ""
  fi
else
  echo "Test 3: Vision — skipped (no mmproj in $MODEL_FILE)"
  echo ""
fi

# Test 4: Extra docker run args are passed through to llama-server and override defaults
# The entrypoint appends "$@" after its own args, so --ctx-size N passed at docker run
# time should win over the hardcoded -c 4096 in DEFAULT_ARGS.
echo "Test 4: Extra docker run args override entrypoint defaults via \"\$@\""
TEST4_CONTAINER="${CONTAINER_NAME}-argstest"
TEST4_PORT=$(python3 -c "import socket; s=socket.socket(); s.bind(('',0)); print(s.getsockname()[1]); s.close()")

if docker ps -a --format '{{.Names}}' | grep -q "^${TEST4_CONTAINER}$"; then
  docker stop "$TEST4_CONTAINER" >/dev/null 2>&1 || true
  docker rm  "$TEST4_CONTAINER" >/dev/null 2>&1 || true
fi

docker run -d \
  --name "$TEST4_CONTAINER" \
  --gpus all \
  -p "$TEST4_PORT:8080" \
  "$IMAGE_NAME" \
  --ctx-size 512

sleep $INITIAL_WAIT
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -sf "http://localhost:$TEST4_PORT/health" >/dev/null 2>&1; then break; fi
  ATTEMPT=$((ATTEMPT + 1))
  sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  docker stop "$TEST4_CONTAINER" >/dev/null 2>&1 || true
  docker rm  "$TEST4_CONTAINER" >/dev/null 2>&1 || true
  _fail "Test 4" "server did not become ready"
fi

if docker logs "$TEST4_CONTAINER" 2>&1 | grep -qE 'n_ctx\s*=\s*512\b'; then
  echo "✓ Test 4: n_ctx=512 found in startup logs — extra docker run args correctly override entrypoint defaults"
else
  FOUND=$(docker logs "$TEST4_CONTAINER" 2>&1 | grep -oE 'n_ctx\s*=\s*[0-9]+' | head -5 | tr '\n' ' ')
  docker stop "$TEST4_CONTAINER" >/dev/null 2>&1
  docker rm  "$TEST4_CONTAINER" >/dev/null 2>&1
  _fail "Test 4" "n_ctx=512 not found in server startup logs — extra args may not be passed through. n_ctx lines found: ${FOUND:-none}"
fi
docker stop "$TEST4_CONTAINER" >/dev/null 2>&1
docker rm  "$TEST4_CONTAINER" >/dev/null 2>&1
echo ""

# Test 5: Audio transcription (only if model has whisper)
if [ "$HAS_WHISPER" = true ]; then
  echo "Test 5: Audio — transcription via /v1/audio/transcriptions"

  # Derive the staged filename (build scripts rename .bin → .gguf to satisfy COPY *.gguf)
  WHISPER_IMAGE_FILENAME="${WHISPER_FILENAME%.*}.gguf"
  if ! docker exec "$CONTAINER_NAME" test -f "/models/$WHISPER_IMAGE_FILENAME" 2>/dev/null; then
    _fail "Test 5" "whisper model not found in container at /models/$WHISPER_IMAGE_FILENAME — was the image rebuilt after adding the whisper field?"
  fi
  echo "  whisper model present in container: /models/$WHISPER_IMAGE_FILENAME"

  AUDIO_FILE="./cosmic-monster-growl-80376.mp3"
  if [ ! -f "$AUDIO_FILE" ]; then
    _fail "Test 5" "audio file not found at $AUDIO_FILE"
  fi
  RESPONSE=$(curl -sf --max-time 60 http://localhost:$WHISPER_PORT/inference \
    -F "file=@$AUDIO_FILE" \
    -F "temperature=0" \
    -F "response_format=json") || _fail "Test 5" "curl whisper-server /inference failed — is whisper-server running on port $WHISPER_PORT?"
  if echo "$RESPONSE" | jq -e 'has("text")' >/dev/null 2>&1; then
    TEXT=$(echo "$RESPONSE" | jq -r '.text')
    echo "✓ Test 5: whisper-server /inference returned valid response"
    echo "  Transcription: '$TEXT'"
  else
    _fail "Test 5" "response missing 'text' field: $RESPONSE"
  fi
else
  echo "Test 5: Audio — skipped (no whisper in $MODEL_FILE)"
fi
echo ""

echo "=== Container Logs (last 20 lines) ==="
docker logs --tail 20 "$CONTAINER_NAME"
echo ""

echo "✓ All tests passed!"
echo ""
echo "Stopping and removing container..."
docker stop "$CONTAINER_NAME" >/dev/null 2>&1
docker rm "$CONTAINER_NAME" >/dev/null 2>&1
echo "✓ Container cleaned up"
