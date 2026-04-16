#!/usr/bin/env bash

set -e

# Load environment variables from .env if it exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Usage: ./download_whisper_model.sh <model_metadata.yaml>
# Example: ./download_whisper_model.sh model_metadata/qwen3.5_0.8b.yaml

if [ $# -lt 1 ]; then
  echo "Usage: $0 <model_metadata.yaml>"
  echo "Example: $0 model_metadata/qwen3.5_0.8b.yaml"
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

# Extract whisper fields
WHISPER_URL=$(yq '.gguf.whisper.url' "$MODEL_FILE")
WHISPER_FILENAME=$(yq '.gguf.whisper.filename' "$MODEL_FILE")
EXPECTED_SIZE_MB=$(yq '.gguf.whisper.file_size' "$MODEL_FILE" | grep -oP '\d+' | head -1)

# Skip gracefully if no whisper configured for this model
if [ -z "$WHISPER_URL" ] || [ "$WHISPER_URL" = "null" ] || [ -z "$WHISPER_FILENAME" ] || [ "$WHISPER_FILENAME" = "null" ]; then
  echo "ℹ No whisper model configured in $MODEL_FILE — skipping."
  exit 0
fi

CACHE_DIR="./llamacpp/model-cache"
mkdir -p "$CACHE_DIR"
OUTPUT_PATH="$CACHE_DIR/$WHISPER_FILENAME"

# Download a file from a URL, with optional HF_TOKEN auth
_download_file() {
  local url="$1"
  local output_path="$2"

  if [ -n "$HF_TOKEN" ]; then
    echo "Using HuggingFace authentication token"
    if ! wget --progress=bar:force:noscroll --header="Authorization: Bearer $HF_TOKEN" -O "$output_path" "$url"; then
      echo ""
      echo "❌ Download failed!"
      if [ -f "$output_path" ]; then
        echo "   Error response:"
        head -3 "$output_path"
      fi
      rm -f "$output_path"
      exit 1
    fi
  else
    if ! wget --progress=bar:force:noscroll -O "$output_path" "$url"; then
      echo ""
      echo "❌ Download failed!"
      if [ -f "$output_path" ]; then
        echo "   Error response:"
        head -3 "$output_path"
      fi
      rm -f "$output_path"
      exit 1
    fi
  fi
}

# Check if whisper model already exists
if [ -f "$OUTPUT_PATH" ]; then
  echo "✓ Whisper model already exists at: $OUTPUT_PATH"
  echo "  File size: $(du -h "$OUTPUT_PATH" | cut -f1)"
  read -p "Do you want to re-download? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping download."
    exit 0
  fi
  echo "Re-downloading whisper model..."
  _download_file "$WHISPER_URL" "$OUTPUT_PATH"
else
  echo "=== Downloading Whisper Model ==="
  echo "Model file: $MODEL_FILE"
  echo "URL: $WHISPER_URL"
  echo "Output: $OUTPUT_PATH"
  if [ -n "$EXPECTED_SIZE_MB" ]; then
    echo "Expected size: ~${EXPECTED_SIZE_MB}MB"
  fi
  echo ""
  _download_file "$WHISPER_URL" "$OUTPUT_PATH"
fi

# Get actual file size in bytes
ACTUAL_SIZE_BYTES=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || stat -f%z "$OUTPUT_PATH" 2>/dev/null || echo "0")
ACTUAL_SIZE_MB=$((ACTUAL_SIZE_BYTES / 1024 / 1024))

echo ""
echo "✓ Download complete!"
echo "  Whisper model saved to: $OUTPUT_PATH"
echo "  File size: $(du -h "$OUTPUT_PATH" | cut -f1) (${ACTUAL_SIZE_MB}MB)"

# Validate file size (must be at least 10MB to avoid error pages)
if [ "$ACTUAL_SIZE_MB" -lt 10 ]; then
  echo ""
  echo "❌ Error: Downloaded file is too small (${ACTUAL_SIZE_MB}MB)"
  echo "   This likely means the download failed or returned an error page."
  echo "   First few lines of the file:"
  head -5 "$OUTPUT_PATH"
  rm -f "$OUTPUT_PATH"
  exit 1
fi

# Warn if size doesn't match expected
if [ -n "$EXPECTED_SIZE_MB" ] && [ "$EXPECTED_SIZE_MB" -gt 0 ]; then
  SIZE_DIFF=$((ACTUAL_SIZE_MB - EXPECTED_SIZE_MB))
  SIZE_DIFF_ABS=${SIZE_DIFF#-}
  PERCENT_DIFF=$((SIZE_DIFF_ABS * 100 / EXPECTED_SIZE_MB))

  if [ "$PERCENT_DIFF" -gt 20 ]; then
    echo "⚠ Warning: File size differs significantly from expected"
    echo "  Expected: ~${EXPECTED_SIZE_MB}MB"
    echo "  Actual: ${ACTUAL_SIZE_MB}MB"
    echo "  Difference: ${SIZE_DIFF}MB (${PERCENT_DIFF}%)"
  fi
fi
