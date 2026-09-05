#!/usr/bin/env bash

set -e

# Usage: ./build_llamacpp_model_server.sh <model_metadata.yaml>
# Example: ./build_llamacpp_model_server.sh model_metadata/gemma3_270m.yaml

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
MODEL_NAME=$(yq -r '.name' "$MODEL_FILE")
MODEL_TAG=$(yq -r '.tag' "$MODEL_FILE")
VRAM_TIER=$(yq -r '.vram_tier' "$MODEL_FILE")
GGUF_FILENAME=$(yq -r '.gguf.filename' "$MODEL_FILE")
GGUF_URL=$(yq -r '.gguf.url' "$MODEL_FILE")
MMPROJ_FILENAME=$(yq -r '.gguf.mmproj.filename' "$MODEL_FILE")
MMPROJ_URL=$(yq -r '.gguf.mmproj.url // ""' "$MODEL_FILE")
WHISPER_FILENAME=$(yq -r '.gguf.whisper.filename' "$MODEL_FILE")
IS_EMBEDDING=$(yq -r '.embedding // "false"' "$MODEL_FILE")
LLAMACPP_ARGS=$(yq -r '.llamacpp_args // ""' "$MODEL_FILE")
LICENSE=$(yq -r '.license' "$MODEL_FILE")
MODEL_SIZE=$(yq -r '.memory.model_size' "$MODEL_FILE")
MEMORY_MIN=$(yq -r '.memory.min' "$MODEL_FILE")
MEMORY_RECOMMENDED=$(yq -r '.memory.recommended' "$MODEL_FILE")
MAX_CONTEXT_WINDOW=$(yq -r '.max_context_window' "$MODEL_FILE")

if [ -z "$VRAM_TIER" ] || [ "$VRAM_TIER" = "null" ]; then
  echo "❌ Error: 'vram_tier' not set in $MODEL_FILE — add vram_tier: cpu|1g|6g|12g|24g|<N>g-ram<M>g"
  exit 1
fi

# Validate fields
if [ -z "$MODEL_NAME" ] || [ "$MODEL_NAME" = "null" ]; then
  echo "❌ Error: Missing 'name' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$MODEL_TAG" ] || [ "$MODEL_TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $MODEL_FILE"
  exit 1
fi

if [ -z "$GGUF_FILENAME" ] || [ "$GGUF_FILENAME" = "null" ]; then
  echo "❌ Error: Missing 'gguf.filename' field in $MODEL_FILE"
  exit 1
fi

IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"
CACHE_DIR="./llamacpp/model-cache"
MODEL_PATH="$CACHE_DIR/$GGUF_FILENAME"

# Validate model exists
if [ ! -f "$MODEL_PATH" ]; then
  echo "❌ Error: Model file not found at $MODEL_PATH"
  echo "Please run download_gguf_model.sh first."
  exit 1
fi

# Determine if this is a multimodal build
HAS_MMPROJ=false
MMPROJ_PATH=""
if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ]; then
  MMPROJ_PATH="$CACHE_DIR/$MMPROJ_FILENAME"
  if [ ! -f "$MMPROJ_PATH" ]; then
    echo "❌ Error: mmproj file not found at $MMPROJ_PATH"
    echo "Please run download_gguf_model.sh first."
    exit 1
  fi
  HAS_MMPROJ=true

  echo "Checking text/mmproj embedding size compatibility..."
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if ! python3 "$SCRIPT_DIR/check_gguf_embd_match.py" "$MODEL_PATH" "$MMPROJ_PATH"; then
    echo "❌ Error: refusing to build — text model and mmproj have mismatched embedding sizes."
    echo "   This produces a container that loads but returns garbage (or crashes) on image input."
    exit 1
  fi
  echo ""
fi

HAS_WHISPER=false
WHISPER_PATH=""
if [ -n "$WHISPER_FILENAME" ] && [ "$WHISPER_FILENAME" != "null" ]; then
  WHISPER_PATH="$CACHE_DIR/$WHISPER_FILENAME"
  if [ ! -f "$WHISPER_PATH" ]; then
    echo "❌ Error: whisper file not found at $WHISPER_PATH"
    echo "Please download the whisper GGUF to $WHISPER_PATH first."
    exit 1
  fi
  HAS_WHISPER=true
fi

echo "=== Building llama.cpp Model Server ==="
echo "Model file: $MODEL_FILE"
echo "Model name: $MODEL_NAME"
echo "Model tag: $MODEL_TAG"
echo "GGUF filename: $GGUF_FILENAME"
echo "Model path: $MODEL_PATH"
echo "Image tag: $IMAGE_TAG"
echo "Model size: $(du -h "$MODEL_PATH" | cut -f1)"
if [ "$HAS_MMPROJ" = true ]; then
  echo "mmproj: $MMPROJ_PATH ($(du -h "$MMPROJ_PATH" | cut -f1))"
fi
if [ "$HAS_WHISPER" = true ]; then
  echo "whisper: $WHISPER_PATH ($(du -h "$WHISPER_PATH" | cut -f1))"
fi
echo ""

# Copy model to build context (preserving real filenames)
echo "Preparing build context..."
cp "$MODEL_PATH" "./llamacpp/$GGUF_FILENAME"

if [ "$VRAM_TIER" = "cpu" ]; then
  DOCKERFILE="llamacpp/Dockerfile.cpu"
else
  DOCKERFILE="llamacpp/Dockerfile.cuda"
fi

MMPROJ_BUILD_ARG=""
MMPROJ_LABEL_ARG=""
if [ "$HAS_MMPROJ" = true ]; then
  cp "$MMPROJ_PATH" "./llamacpp/$MMPROJ_FILENAME"
  MMPROJ_BUILD_ARG="--build-arg MMPROJ_FILENAME=$MMPROJ_FILENAME"
  MMPROJ_LABEL_ARG="--label ai.model.mmproj.url=${MMPROJ_URL}"
fi

EMBEDDING_BUILD_ARG=""
if [ "$IS_EMBEDDING" = "true" ]; then
  EMBEDDING_BUILD_ARG="--build-arg EMBEDDING=true"
fi

LLAMACPP_ARGS_BUILD_ARG=""
if [ -n "$LLAMACPP_ARGS" ] && [ "$LLAMACPP_ARGS" != "null" ]; then
  LLAMACPP_ARGS_BUILD_ARG="--build-arg"
  LLAMACPP_ARGS_BUILD_ARG_VALUE="LLAMACPP_ARGS=${LLAMACPP_ARGS}"
fi

WHISPER_BUILD_ARG=""
WHISPER_BUILD_FILENAME=""
if [ "$HAS_WHISPER" = true ]; then
  # Stage with .gguf extension so Dockerfile's "COPY *.gguf /models/" picks it up
  WHISPER_BUILD_FILENAME="${WHISPER_FILENAME%.*}.gguf"
  cp "$WHISPER_PATH" "./llamacpp/$WHISPER_BUILD_FILENAME"
  WHISPER_BUILD_ARG="--build-arg WHISPER_FILENAME=$WHISPER_BUILD_FILENAME"
fi

# Generate manifest.json for the build context
MANIFEST_ENTRY="{\"alias\":\"${MODEL_NAME}:${MODEL_TAG}\",\"gguf_filename\":\"${GGUF_FILENAME}\""
[ "$HAS_MMPROJ" = true ] && MANIFEST_ENTRY="${MANIFEST_ENTRY},\"mmproj_filename\":\"${MMPROJ_FILENAME}\""
[ "$IS_EMBEDDING" = "true" ] && MANIFEST_ENTRY="${MANIFEST_ENTRY},\"embedding\":true"
MANIFEST_ENTRY="${MANIFEST_ENTRY}}"
echo "[${MANIFEST_ENTRY}]" > ./llamacpp/manifest.json

# Clean up temp files on exit (success or failure)
_cleanup() {
  rm -f "./llamacpp/$GGUF_FILENAME"
  rm -f "./llamacpp/manifest.json"
  [ "$HAS_MMPROJ" = true ] && rm -f "./llamacpp/$MMPROJ_FILENAME" || true
  [ -n "$WHISPER_BUILD_FILENAME" ] && rm -f "./llamacpp/$WHISPER_BUILD_FILENAME" || true
}
trap _cleanup EXIT

# Build Docker image
IMAGE_NAME="model-servers/llamacpp:$IMAGE_TAG"
echo "Building Docker image: $IMAGE_NAME"
echo ""

docker build \
  -t "$IMAGE_NAME" \
  -f "$DOCKERFILE" \
  --build-arg MODEL_NAME="$MODEL_NAME" \
  --build-arg MODEL_TAG="$MODEL_TAG" \
  --build-arg GGUF_FILENAME="$GGUF_FILENAME" \
  $MMPROJ_BUILD_ARG \
  $WHISPER_BUILD_ARG \
  $EMBEDDING_BUILD_ARG \
  ${LLAMACPP_ARGS_BUILD_ARG:+$LLAMACPP_ARGS_BUILD_ARG "$LLAMACPP_ARGS_BUILD_ARG_VALUE"} \
  --label "org.opencontainers.image.title=llama.cpp Server - ${MODEL_NAME}" \
  --label "org.opencontainers.image.description=Preloaded llama.cpp model server for ${MODEL_NAME}:${MODEL_TAG}" \
  --label "org.opencontainers.image.version=${MODEL_NAME}:${MODEL_TAG}" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.licenses=${LICENSE}" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.memory.size=${MODEL_SIZE}" \
  --label "org.opencontainers.image.memory.min=${MEMORY_MIN}" \
  --label "org.opencontainers.image.memory.recommended=${MEMORY_RECOMMENDED}" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.model.name=${MODEL_NAME}" \
  --label "ai.model.tag=${MODEL_TAG}" \
  --label "ai.model.identifier=${MODEL_NAME}:${MODEL_TAG}" \
  --label "ai.model.context_window=${MAX_CONTEXT_WINDOW}" \
  --label "ai.model.gguf.url=${GGUF_URL}" \
  --label "ai.model.manifest=[${MANIFEST_ENTRY}]" \
  $MMPROJ_LABEL_ARG \
  llamacpp/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Image size: $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
echo ""
if [ "$VRAM_TIER" = "cpu" ]; then
  echo "To run locally:"
  echo "  docker run --rm -p 8080:8080 $IMAGE_NAME"
else
  echo "To run locally:"
  echo "  docker run --rm --gpus all -p 8080:8080 $IMAGE_NAME"
fi
if [ "$HAS_MMPROJ" = true ]; then
  echo ""
  echo "Multimodal (vision) image — send images via the /v1/chat/completions endpoint:"
  echo '  curl http://localhost:8080/v1/chat/completions -H "Content-Type: application/json" \'
  echo '    -d '"'"'{"model":"gemma4","messages":[{"role":"user","content":[{"type":"text","text":"Describe this image"},{"type":"image_url","image_url":{"url":"data:image/jpeg;base64,<BASE64>"}}]}]}'"'"
fi
