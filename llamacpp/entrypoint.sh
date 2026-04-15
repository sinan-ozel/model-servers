#!/bin/sh
BASE_ARGS="-m /models/${GGUF_FILENAME} --host 0.0.0.0 --port 8080 --alias ${MODEL_ALIAS}"
DEFAULT_ARGS="-ngl 999 -c 4096"
if [ -n "$LLAMACPP_ARGS" ]; then
  ARGS="$BASE_ARGS $LLAMACPP_ARGS"
else
  ARGS="$BASE_ARGS $DEFAULT_ARGS"
fi
if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ] && [ -f "/models/$MMPROJ_FILENAME" ]; then
  ARGS="$ARGS --mmproj /models/$MMPROJ_FILENAME"
fi
exec /app/llama-server $ARGS "$@"
