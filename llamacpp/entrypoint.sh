#!/bin/sh
MODEL_ALIAS="${MODEL_NAME}:${MODEL_TAG}"
BASE_ARGS="-m /models/model.gguf --host 0.0.0.0 --port 8080 --alias ${MODEL_ALIAS}"
DEFAULT_ARGS="-ngl 999 -c 4096"
if [ -n "$LLAMACPP_ARGS" ]; then
  ARGS="$BASE_ARGS $LLAMACPP_ARGS"
else
  ARGS="$BASE_ARGS $DEFAULT_ARGS"
fi
if [ -n "$MMPROJ_FILENAME" ] && [ "$MMPROJ_FILENAME" != "null" ] && [ -f "/models/mmproj/$MMPROJ_FILENAME" ]; then
  ARGS="$ARGS --mmproj /models/mmproj/$MMPROJ_FILENAME"
fi
exec /app/llama-server $ARGS
