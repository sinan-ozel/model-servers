#!/bin/bash
set -e

# Test Ollama server on AWS EKS
# Usage: ./test_ollama_eks.sh [model_name] [eks_url] [image_tag]

MODEL_NAME="${1:-orieg/gemma3-tools:1b}"
EKS_URL="${2:-http://a878c81ea32c141d0aad0f578258fe03-893170584.ca-central-1.elb.amazonaws.com}"
IMAGE_TAG="${3:-orieg-gemma3-tools-1b}"

echo "Testing Ollama server at: $EKS_URL"
echo "Using model: $MODEL_NAME"
echo "Image tag: $IMAGE_TAG"

# Max 300 seconds wait for server to be ready
MAX_WAIT=300
WAITED=0

echo "Waiting for server to be ready..."
while true; do
    # Check if server responds
    if curl -sf "$EKS_URL/api/tags" > /dev/null 2>&1; then
        break
    fi

    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "Error: server did not respond within $MAX_WAIT seconds."
        exit 1
    fi

    sleep 1
    WAITED=$((WAITED+1))
done

echo "Server is ready."

# Test generation
echo "Testing model generation..."
response=$(curl -X POST "$EKS_URL/api/chat" \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"$MODEL_NAME\",
    \"messages\": [{\"role\": \"user\", \"content\": \"Hello, how are you?\"}],
    \"stream\": false
  }" \
  -m 300 -s)

if echo "$response" | jq -e '.message.content' > /dev/null 2>&1; then
    echo "Response: $(echo "$response" | jq -r '.message.content')"
else
    echo "Error response: $response"
    exit 1
fi

if [ $? -eq 0 ]; then
    echo "✅ Ollama server test successful!"
else
    echo "❌ Ollama server test failed!"
    exit 1
fi