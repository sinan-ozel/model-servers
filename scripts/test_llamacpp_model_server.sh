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

# Validate fields
if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" = "null" ]; then
  echo "❌ Error: Missing 'name' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$MODEL_TAG" ] || [ "$MODEL_TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $MODEL_FILE"
  exit 1
fi

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
IMAGE_NAME="model-servers/llamacpp:$IMAGE_TAG"
CONTAINER_NAME="llamacpp-test-$IMAGE_TAG"
PORT=8080

echo "=== Testing llama.cpp Model Server ==="
echo "Model file: $MODEL_FILE"
echo "Image: $IMAGE_NAME"
echo "Port: $PORT"
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
sleep 5

# Wait for server to be ready (up to 60 seconds)
MAX_ATTEMPTS=12
ATTEMPT=0
while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  if curl -s http://localhost:$PORT/health >/dev/null 2>&1; then
    echo "✓ Server is ready!"
    break
  fi
  ATTEMPT=$((ATTEMPT + 1))
  echo "Waiting... ($ATTEMPT/$MAX_ATTEMPTS)"
  sleep 5
done

if [ $ATTEMPT -eq $MAX_ATTEMPTS ]; then
  echo "❌ Server did not become ready in time."
  docker logs --tail 30 "$CONTAINER_NAME"
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1
  docker rm "$CONTAINER_NAME" >/dev/null 2>&1
  exit 1
fi

echo ""
echo "=== Testing Model Inference ==="
echo ""

# Helper: assert response contains "Paris" (case-insensitive)
_assert_paris() {
  local label="$1"
  local text="$2"
  if echo "$text" | grep -qi "paris"; then
    echo "✓ $label: response contains 'Paris'"
  else
    echo "❌ $label: expected 'Paris' in response, got:"
    echo "$text"
    docker logs --tail 30 "$CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" >/dev/null 2>&1
    docker rm "$CONTAINER_NAME" >/dev/null 2>&1
    exit 1
  fi
}

# Test 1: Native completion endpoint
echo "Test 1: Native /completion endpoint"
RESPONSE=$(curl -s http://localhost:$PORT/completion \
  -H "Content-Type: application/json" \
  -d '{
    "prompt": "What is the capital of France?",
    "n_predict": 50,
    "temperature": 0.7
  }')
CONTENT=$(echo "$RESPONSE" | jq -r '.content // .text // empty' 2>/dev/null)
echo "Response: $CONTENT"
_assert_paris "Test 1" "$CONTENT"
echo ""

# Test 2: OpenAI-compatible chat completions endpoint
echo "Test 2: OpenAI-compatible /v1/chat/completions endpoint"
RESPONSE=$(curl -s http://localhost:$PORT/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"${MODEL_NAME}:${MODEL_TAG}\",
    \"messages\": [{\"role\": \"user\", \"content\": \"What is the capital of France?\"}],
    \"max_tokens\": 50,
    \"temperature\": 0.7
  }")
CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
echo "Response: $CONTENT"
_assert_paris "Test 2" "$CONTENT"
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
