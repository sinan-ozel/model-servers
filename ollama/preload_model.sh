#!/bin/bash

until curl -s localhost:11434 > /dev/null; do
  echo "Waiting for Ollama to be ready..."
  sleep 1
done


if [[ -z "$MODEL_NAME" || -z "$MODEL_TAG" ]]; then
  echo "MODEL_NAME and MODEL_TAG must be set"
  exit 1
fi

# Issue a dummy prompt to trigger model loading.
echo "What is 2 + 2?" | ollama run "$MODEL_NAME:$MODEL_TAG"
