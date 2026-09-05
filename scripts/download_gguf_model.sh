#!/usr/bin/env bash

set -e

# Load environment variables from .env if it exists
if [ -f .env ]; then
  export $(grep -v '^#' .env | xargs)
fi

# Usage: ./download_gguf_model.sh <model_metadata.yaml>
# Example: ./download_gguf_model.sh model_metadata/gemma3_270m.yaml

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

# Download a file from a URL, with optional HF_TOKEN auth
# Usage: _download_file <url> <output_path>
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
      echo ""
      echo "💡 If this is a gated model, you may need to:"
      echo "   1. Accept the model's license on HuggingFace"
      echo "   2. Create a token at https://huggingface.co/settings/tokens"
      echo "   3. Export it: export HF_TOKEN=your_token_here"
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
      echo ""
      echo "💡 If this is a gated model, you may need to:"
      echo "   1. Accept the model's license on HuggingFace"
      echo "   2. Create a token at https://huggingface.co/settings/tokens"
      echo "   3. Export it: export HF_TOKEN=your_token_here"
      exit 1
    fi
  fi
}

# Extract values using yq
GGUF_URL=$(yq -r '.gguf.url' "$MODEL_FILE")
GGUF_FILENAME=$(yq -r '.gguf.filename' "$MODEL_FILE")
EXPECTED_SIZE_MB=$(yq -r '.gguf.file_size' "$MODEL_FILE" | grep -oP '\d+' | head -1)
MMPROJ_URL=$(yq -r '.gguf.mmproj.url' "$MODEL_FILE")
MMPROJ_FILENAME=$(yq -r '.gguf.mmproj.filename' "$MODEL_FILE")

# Validate GGUF fields
if [ -z "$GGUF_URL" ] || [ "$GGUF_URL" = "null" ] || [ -z "$GGUF_FILENAME" ] || [ "$GGUF_FILENAME" = "null" ]; then
  echo "❌ Error: Missing or empty gguf.url or gguf.filename in $MODEL_FILE"
  echo "Please add the following fields to the YAML file:"
  echo ""
  echo "gguf:"
  echo "  url: https://huggingface.co/.../model.gguf"
  echo "  filename: model.gguf"
  exit 1
fi

CACHE_DIR="./llamacpp/model-cache"

# Create cache directory if it doesn't exist
mkdir -p "$CACHE_DIR"

OUTPUT_PATH="$CACHE_DIR/$GGUF_FILENAME"

# Check if model already exists
if [ -f "$OUTPUT_PATH" ]; then
  echo "✓ Model already exists at: $OUTPUT_PATH"
  echo "  File size: $(du -h "$OUTPUT_PATH" | cut -f1)"
  read -p "Do you want to re-download? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Skipping download."
  else
    echo "Re-downloading model..."
    _download_file "$GGUF_URL" "$OUTPUT_PATH"
  fi
else
  echo "=== Downloading GGUF Model ==="
  echo "Model file: $MODEL_FILE"
  echo "URL: $GGUF_URL"
  echo "Output: $OUTPUT_PATH"
  if [ -n "$EXPECTED_SIZE_MB" ]; then
    echo "Expected size: ~${EXPECTED_SIZE_MB}MB"
  fi
  echo ""

  _download_file "$GGUF_URL" "$OUTPUT_PATH"
fi

# Get actual file size in bytes
ACTUAL_SIZE_BYTES=$(stat -c%s "$OUTPUT_PATH" 2>/dev/null || stat -f%z "$OUTPUT_PATH" 2>/dev/null || echo "0")
ACTUAL_SIZE_MB=$((ACTUAL_SIZE_BYTES / 1024 / 1024))

echo ""
echo "✓ Download complete!"
echo "  Model saved to: $OUTPUT_PATH"
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

# Download mmproj file if present in metadata
if [ -n "$MMPROJ_URL" ] && [ "$MMPROJ_URL" != "null" ] && [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ]; then
  MMPROJ_OUTPUT_PATH="$CACHE_DIR/$MMPROJ_FILENAME"

  echo ""
  echo "=== Downloading mmproj (multimodal projector) ==="
  echo "URL: $MMPROJ_URL"
  echo "Output: $MMPROJ_OUTPUT_PATH"

  if [ -f "$MMPROJ_OUTPUT_PATH" ]; then
    echo "✓ mmproj already exists at: $MMPROJ_OUTPUT_PATH"
    echo "  File size: $(du -h "$MMPROJ_OUTPUT_PATH" | cut -f1)"
    read -p "Do you want to re-download? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Skipping mmproj download."
    else
      _download_file "$MMPROJ_URL" "$MMPROJ_OUTPUT_PATH"
    fi
  else
    _download_file "$MMPROJ_URL" "$MMPROJ_OUTPUT_PATH"
  fi

  echo "✓ mmproj saved to: $MMPROJ_OUTPUT_PATH"
  echo "  File size: $(du -h "$MMPROJ_OUTPUT_PATH" | cut -f1)"
fi
