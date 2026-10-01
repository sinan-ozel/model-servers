#!/usr/bin/env bash
set -e

# Downloads the YuNet ONNX weights bundled into the face-detector image.
# Usage: ./download_face_detector_models.sh

TARGET_DIR="./face-detector/model-cache"
mkdir -p "$TARGET_DIR"

FILENAME="face_detection_yunet_2023mar.onnx"
URL="https://github.com/opencv/opencv_zoo/raw/main/models/face_detection_yunet/${FILENAME}"
PATH_="${TARGET_DIR}/${FILENAME}"

if [ -f "$PATH_" ]; then
  echo "Already present: $PATH_"
else
  echo "Downloading ${FILENAME} from ${URL}..."
  curl -sL -o "$PATH_" "$URL"
  echo "Saved to $PATH_ ($(du -h "$PATH_" | cut -f1))"
fi

echo "Model weights ready in $TARGET_DIR"
