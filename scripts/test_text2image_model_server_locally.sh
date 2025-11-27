#!/bin/bash
set -e


VERSION="0.1.0"

MODEL_PUBLISHER="CompVis"
MODEL_NAME="stable-diffusion-v1-4"


docker stop text2image-server || true
docker rm text2image-server || true

# Diagnostic: show model directory permissions
docker run --rm \
    --gpus all \
    -p 8000:8000 \
    --name text2image-server \
    --entrypoint bash \
    model-servers/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME} \
    -c 'ls -al /app/hf/hub/'


docker run -d \
    --gpus all \
    -p 8000:8000 \
    --name text2image-server \
    model-servers/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME}

echo "Waiting for model..."

# Max 180 seconds wait (change as needed)
MAX_WAIT=180
WAITED=0

while true; do
    # Check if container died
    if ! docker ps --format '{{.Names}}' | grep -q '^text2image-server$'; then
        echo "Error: container 'text2image-server' is no longer running."
        exit 1
    fi

    # Check if server responds AND model is loaded
    if curl -sf http://localhost:8000/status 2>/dev/null | grep -q '"model_loaded": true'; then
        break
    fi

    if [ "$WAITED" -ge "$MAX_WAIT" ]; then
        echo "Error: model did not load within $MAX_WAIT seconds."
        exit 1
    fi

    sleep 1
    WAITED=$((WAITED+1))
done

echo "Model loaded."

# Test generation
curl http://localhost:8000/v3/images/generations \
  -H "Content-Type: application/json" \
  -d "{
    \"model\": \"CompVis/stable-diffusion-v1-4\",
    \"prompt\": \"three cats\",
    \"num_inference_steps\": 10,
    \"size\": \"512x512\"
  }" \
| jq -r '.data[0].b64_json' | base64 --decode > output.png

echo "Saved to output.png"

docker stop text2image-server
docker rm text2image-server
echo "Server stopped and removed"