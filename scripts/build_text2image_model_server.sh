#!/usr/bin/env bash
set -e

VERSION="0.1.0"

MODEL_PUBLISHER="CompVis"
MODEL_NAME="stable-diffusion-v1-4"
HOST_MODEL_PATH="/home/sinan//hf/hub/models--${MODEL_PUBLISHER}--${MODEL_NAME}"
MODEL_SIZE=$(du -BG ${HOST_MODEL_PATH}/blobs | awk '{print $1}')  # e.g. "11G"

# Extract numeric GiB value (strip trailing "G")
MODEL_SIZE_GIB=${MODEL_SIZE%G}

# Compute required memory
MEMORY_MIN="$(( MODEL_SIZE_GIB + 4 ))GiB"
MEMORY_RECOMMENDED="$(( MODEL_SIZE_GIB + 16 ))GiB"

echo "MODEL_SIZE = ${MODEL_SIZE_GIB}GiB"
echo "MEMORY_MIN = $MEMORY_MIN"
echo "MEMORY_RECOMMENDED = $MEMORY_RECOMMENDED"

# Absolute path to your model snapshot on the host
SNAPSHOT_ID="133a221b8aa7292a167afc5127cb63fb5005638b"

# Directory inside build context where Docker can reach the files

TARGET_DIR="./text2image/model-cache"

rm -rf "${TARGET_DIR}"
mkdir -p "${TARGET_DIR}/models--${MODEL_PUBLISHER}--${MODEL_NAME}"

rsync -aL --progress --exclude='.ipynb_checkpoints/' \
      "$HOST_MODEL_PATH/" \
      "$TARGET_DIR/models--${MODEL_PUBLISHER}--${MODEL_NAME}/"


# Write MODEL_PATH for the loader
echo "/app/hf/hub/models--${MODEL_PUBLISHER}--${MODEL_NAME}/snapshots/$SNAPSHOT_ID" > ./text2image/MODEL_PATH.txt
cp ./model_metadata/${MODEL_PUBLISHER}/${MODEL_NAME}/PIPELINE.txt ./text2image/PIPELINE.txt
cp ./model_metadata/${MODEL_PUBLISHER}/${MODEL_NAME}/requirements.txt ./text2image/requirements.txt

echo "Prepared model symlink and MODEL_PATH.txt"

docker buildx build \
    --load \
    --no-cache \
    --build-arg MODEL_NAME=$MODEL_NAME \
    --build-arg MODEL_SIZE="$MODEL_SIZE" \
    --build-arg MEMORY_MIN="$MEMORY_MIN" \
    --build-arg MEMORY_RECOMMENDED="$MEMORY_RECOMMENDED" \
    --tag model-servers/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME} \
    --label org.opencontainers.image.title="Hugging Face Text2Image Server - $MODEL_NAME" \
    --label org.opencontainers.image.description="Preloaded Hugging Face model server for $MODEL_NAME@$SNAPSHOT_ID" \
    --label org.opencontainers.image.version="$SNAPSHOT_ID" \
    --label org.opencontainers.image.memory.size="$MODEL_SIZE" \
    --label org.opencontainers.image.memory.min="$MEMORY_MIN" \
    --label org.opencontainers.image.memory.recommended="$MEMORY_RECOMMENDED" \
    --label org.opencontainers.image.date="$(date +'%Y-%m-%d')" \
    --file ./text2image/Dockerfile ./text2image

rm -rf "${TARGET_DIR}"