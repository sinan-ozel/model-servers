#!/usr/bin/env bash

set -e

CACHE_DIR="./llamacpp/model-cache"

if [ ! -d "$CACHE_DIR" ]; then
  echo "Cache directory does not exist: $CACHE_DIR"
  exit 0
fi

FILES=$(find "$CACHE_DIR" -maxdepth 1 -type f | sort)

if [ -z "$FILES" ]; then
  echo "Cache is already empty: $CACHE_DIR"
  exit 0
fi

echo "=== llama.cpp Model Cache ==="
echo "Directory: $CACHE_DIR"
echo ""
echo "Files:"
while IFS= read -r f; do
  echo "  $(du -h "$f" | cut -f1)  $(basename "$f")"
done <<< "$FILES"
echo ""
TOTAL=$(du -sh "$CACHE_DIR" | cut -f1)
echo "Total size: $TOTAL"
echo ""

read -p "Delete all cached model files? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted."
  exit 0
fi

rm -f "$CACHE_DIR"/*.gguf
echo "✓ Cache cleared"
