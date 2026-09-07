#!/usr/bin/env bash
set -e

# Downloads the Real-ESRGAN weights bundled into the upscaler image.
# Usage: ./download_upscaler_models.sh

TARGET_DIR="./upscaler/model-cache"
mkdir -p "$TARGET_DIR"

declare -A WEIGHTS=(
  ["RealESRGAN_x4plus.pth"]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.1.0/RealESRGAN_x4plus.pth"
  ["RealESRGAN_x2plus.pth"]="https://github.com/xinntao/Real-ESRGAN/releases/download/v0.2.1/RealESRGAN_x2plus.pth"
)

for filename in "${!WEIGHTS[@]}"; do
  path="${TARGET_DIR}/${filename}"
  if [ -f "$path" ]; then
    echo "Already present: $path"
    continue
  fi
  url="${WEIGHTS[$filename]}"
  echo "Downloading ${filename} from ${url}..."
  curl -sL -o "$path" "$url"
  echo "Saved to $path ($(du -h "$path" | cut -f1))"
done

echo "Model weights ready in $TARGET_DIR"
