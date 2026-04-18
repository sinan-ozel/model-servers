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
# Auto-enable embeddings: set at build time (single model) or detected from bundle list
_should_embed=false
if [ "$EMBEDDING" = "true" ]; then
  _should_embed=true
elif [ -n "$EMBEDDING_FILENAMES" ] && [ -n "$GGUF_FILENAME" ]; then
  case ",$EMBEDDING_FILENAMES," in
    *",$GGUF_FILENAME,"*) _should_embed=true ;;
  esac
fi
[ "$_should_embed" = "true" ] && ARGS="$ARGS --embeddings"
if [ -n "$WHISPER_FILENAME" ] && [ "$WHISPER_FILENAME" != "null" ] && [ -f "/models/$WHISPER_FILENAME" ]; then
  /app/whisper-server -m /models/$WHISPER_FILENAME --host 0.0.0.0 --port 8081 &
fi
exec /app/llama-server $ARGS "$@"
