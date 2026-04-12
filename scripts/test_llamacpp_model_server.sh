#!/usr/bin/env bash

set -e

# Usage: ./test_llamacpp_model_server.sh <model_metadata.yaml>
# Example: ./test_llamacpp_model_server.sh model_metadata/gemma3_270m.yaml

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml>"
  echo "Example: $0 model_metadata/gemma3_270m.yaml"
  exit 1
fi

MODEL_FILE="$1"

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

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
IMAGE_NAME="model-servers/llamacpp:$IMAGE_TAG"
CONTAINER_NAME="llamacpp-test-$IMAGE_TAG"
PORT=8080

echo "=== Testing llama.cpp Model Server ==="
echo "Model file: $MODEL_FILE"
echo "Image: $IMAGE_NAME"
echo "Port: $PORT"
echo "Vision (mmproj): $HAS_MMPROJ"
echo ""

# Check if container is already running
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Stopping and removing existing container..."
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Start container in background
echo "Starting container..."
docker run -d \
  --name "$CONTAINER_NAME" \
  --gpus all \
  -p "$PORT:$PORT" \
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
RESPONSE=$(curl -sf --max-time 60 http://localhost:$PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}:${MODEL_TAG}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France? Answer in one word.\"}],
    \"max_tokens\": 100,
    \"temperature\": 0
  }") || _fail "Test 2" "curl request failed (HTTP error or timeout)"
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
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
    RESPONSE=$(curl -sf --max-time 90 http://localhost:$PORT/v1/chat/completions \
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
        \"max_tokens\": 50,
        \"temperature\": 0
      }") || _fail "Test 3" "curl request failed (HTTP error or timeout)"
    CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
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

echo "=== Container Logs (last 20 lines) ==="
docker logs --tail 20 "$CONTAINER_NAME"
echo ""

echo "✓ All tests passed!"
echo ""
echo "Stopping and removing container..."
docker stop "$CONTAINER_NAME" >/dev/null 2>&1
docker rm "$CONTAINER_NAME" >/dev/null 2>&1
echo "✓ Container cleaned up"
