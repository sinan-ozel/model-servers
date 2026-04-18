#!/usr/bin/env bash

set -e

# Usage: ./build_llamacpp_bundle.sh <bundle.yaml>
# Example: ./build_llamacpp_bundle.sh bundles/llama.cuda.6gb.yaml

if [ $# -lt 1 ]; then
  echo "Usage: $0 <bundle.yaml>"
  echo "Example: $0 bundles/llama.cuda.6gb.yaml"
  exit 1
fi

BUNDLE_FILE="$1"

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
BUNDLE_WHISPER_URL=$(yq '.whisper.url' "$BUNDLE_FILE")
BUNDLE_WHISPER_FILENAME=$(yq '.whisper.filename' "$BUNDLE_FILE")

if [ -z "$REPO" ] || [ "$REPO" = "null" ]; then
  echo "❌ Error: Missing 'repo' field in $BUNDLE_FILE"
  exit 1
fi

if [ -z "$TAG" ] || [ "$TAG" = "null" ]; then
  echo "❌ Error: Missing 'tag' field in $BUNDLE_FILE"
  exit 1
fi

IMAGE_NAME="model-servers/llamacpp:$REPO-$TAG"
CACHE_DIR="./llamacpp/model-cache"

echo "=== Building llama.cpp Bundle ==="
echo "Bundle file: $BUNDLE_FILE"
echo "Repo:        $REPO"
echo "Tag:         $TAG"
echo "Models:      $MODEL_COUNT"
echo "Image:       $IMAGE_NAME"
if [ -n "$BUNDLE_WHISPER_FILENAME" ] && [ "$BUNDLE_WHISPER_FILENAME" != "null" ]; then
  echo "Whisper:     $BUNDLE_WHISPER_FILENAME (bundle-level override)"
fi
echo ""

mkdir -p "$CACHE_DIR"

COPIED_FILES=()
MODEL_IDENTIFIERS=""
EMBEDDING_FILENAMES=""

_cleanup() {
  echo "Cleaning up build context..."
  for f in "${COPIED_FILES[@]}"; do
    rm -f "$f"
  done
}
trap _cleanup EXIT

# Download and stage all models
for i in $(seq 0 $((MODEL_COUNT - 1))); do
  MODEL_FILE=$(yq ".models[$i]" "$BUNDLE_FILE")

  if [ ! -f "$MODEL_FILE" ]; then
    echo "❌ Error: Model metadata file not found: $MODEL_FILE"
    exit 1
  fi

  GGUF_URL=$(yq '.gguf.url' "$MODEL_FILE")
  GGUF_FILENAME=$(yq '.gguf.filename' "$MODEL_FILE")
  MMPROJ_URL=$(yq '.gguf.mmproj.url' "$MODEL_FILE")
  MMPROJ_FILENAME=$(yq '.gguf.mmproj.filename' "$MODEL_FILE")
  M_NAME=$(yq '.name' "$MODEL_FILE")
  M_TAG=$(yq '.tag' "$MODEL_FILE")
  M_EMBEDDING=$(yq '.embedding // "false"' "$MODEL_FILE")
  if [ -n "$M_NAME" ] && [ "$M_NAME" != "null" ] && [ -n "$M_TAG" ] && [ "$M_TAG" != "null" ]; then
    if [ -n "$MODEL_IDENTIFIERS" ]; then
      MODEL_IDENTIFIERS="$MODEL_IDENTIFIERS,$M_NAME:$M_TAG"
    else
      MODEL_IDENTIFIERS="$M_NAME:$M_TAG"
    fi
  fi

  if [ -z "$GGUF_URL" ] || [ "$GGUF_URL" = "null" ]; then
    echo "⚠ Skipping $MODEL_FILE — no gguf.url defined"
    continue
  fi

  MODEL_PATH="$CACHE_DIR/$GGUF_FILENAME"

  if [ ! -f "$MODEL_PATH" ]; then
    echo "=== Downloading $GGUF_FILENAME ==="
    if [ -n "$HF_TOKEN" ]; then
      wget --progress=bar:force:noscroll --header="Authorization: Bearer $HF_TOKEN" \
        -O "$MODEL_PATH" "$GGUF_URL"
    else
      wget --progress=bar:force:noscroll -O "$MODEL_PATH" "$GGUF_URL"
    fi
  else
    echo "✓ Already cached: $GGUF_FILENAME ($(du -h "$MODEL_PATH" | cut -f1))"
  fi

  cp "$MODEL_PATH" "./llamacpp/$GGUF_FILENAME"
  COPIED_FILES+=("./llamacpp/$GGUF_FILENAME")

  if [ "$M_EMBEDDING" = "true" ]; then
    if [ -n "$EMBEDDING_FILENAMES" ]; then
      EMBEDDING_FILENAMES="$EMBEDDING_FILENAMES,$GGUF_FILENAME"
    else
      EMBEDDING_FILENAMES="$GGUF_FILENAME"
    fi
  fi

  if [ -n "$MMPROJ_URL" ] && [ "$MMPROJ_URL" != "null" ]; then
    MMPROJ_PATH="$CACHE_DIR/$MMPROJ_FILENAME"
    if [ ! -f "$MMPROJ_PATH" ]; then
      echo "=== Downloading $MMPROJ_FILENAME ==="
      if [ -n "$HF_TOKEN" ]; then
        wget --progress=bar:force:noscroll --header="Authorization: Bearer $HF_TOKEN" \
          -O "$MMPROJ_PATH" "$MMPROJ_URL"
      else
        wget --progress=bar:force:noscroll -O "$MMPROJ_PATH" "$MMPROJ_URL"
      fi
    else
      echo "✓ Already cached: $MMPROJ_FILENAME ($(du -h "$MMPROJ_PATH" | cut -f1))"
    fi
    cp "$MMPROJ_PATH" "./llamacpp/$MMPROJ_FILENAME"
    COPIED_FILES+=("./llamacpp/$MMPROJ_FILENAME")
  fi
done

# Download and stage bundle-level whisper model (overrides any per-model whisper config)
WHISPER_BUILD_ARG=""
if [ -n "$BUNDLE_WHISPER_URL" ] && [ "$BUNDLE_WHISPER_URL" != "null" ] && \
   [ -n "$BUNDLE_WHISPER_FILENAME" ] && [ "$BUNDLE_WHISPER_FILENAME" != "null" ]; then
  WHISPER_PATH="$CACHE_DIR/$BUNDLE_WHISPER_FILENAME"
  if [ ! -f "$WHISPER_PATH" ]; then
    echo "=== Downloading $BUNDLE_WHISPER_FILENAME ==="
    if [ -n "$HF_TOKEN" ]; then
      wget --progress=bar:force:noscroll --header="Authorization: Bearer $HF_TOKEN" \
        -O "$WHISPER_PATH" "$BUNDLE_WHISPER_URL"
    else
      wget --progress=bar:force:noscroll -O "$WHISPER_PATH" "$BUNDLE_WHISPER_URL"
    fi
  else
    echo "✓ Already cached: $BUNDLE_WHISPER_FILENAME ($(du -h "$WHISPER_PATH" | cut -f1))"
  fi
  # Stage with .gguf extension so Dockerfile's "COPY *.gguf /models/" picks it up
  WHISPER_BUILD_FILENAME="${BUNDLE_WHISPER_FILENAME%.*}.gguf"
  cp "$WHISPER_PATH" "./llamacpp/$WHISPER_BUILD_FILENAME"
  COPIED_FILES+=("./llamacpp/$WHISPER_BUILD_FILENAME")
  WHISPER_BUILD_ARG="--build-arg WHISPER_FILENAME=$WHISPER_BUILD_FILENAME"
fi

EMBEDDING_FILENAMES_BUILD_ARG=""
if [ -n "$EMBEDDING_FILENAMES" ]; then
  EMBEDDING_FILENAMES_BUILD_ARG="--build-arg EMBEDDING_FILENAMES=$EMBEDDING_FILENAMES"
  echo "  Embedding models: $EMBEDDING_FILENAMES"
fi

echo ""
echo "=== Building Docker image: $IMAGE_NAME ==="
echo "  Models: $MODEL_IDENTIFIERS"
docker build \
  -t "$IMAGE_NAME" \
  -f llamacpp/Dockerfile \
  $WHISPER_BUILD_ARG \
  $EMBEDDING_FILENAMES_BUILD_ARG \
  --label "org.opencontainers.image.title=llama.cpp Bundle - ${REPO}" \
  --label "org.opencontainers.image.description=llama.cpp bundle ${REPO}:${TAG} containing: ${MODEL_IDENTIFIERS}" \
  --label "org.opencontainers.image.version=${REPO}:${TAG}" \
  --label "org.opencontainers.image.authors=Sinan Ozel" \
  --label "org.opencontainers.image.vendor=sinanozel" \
  --label "org.opencontainers.image.date=$(date +'%Y-%m-%d')" \
  --label "ai.bundle.repo=${REPO}" \
  --label "ai.bundle.tag=${TAG}" \
  --label "ai.bundle.models=${MODEL_IDENTIFIERS}" \
  llamacpp/

echo ""
echo "✓ Build complete!"
echo "  Image: $IMAGE_NAME"
echo "  Size:  $(docker images "$IMAGE_NAME" --format "{{.Size}}")"
