#!/bin/bash

# Start Ollama in the background.
echo "Starting Ollama server..."
/bin/ollama serve &
serve_pid=$!

# Wait a few seconds for the server to become available.
sleep 5

echo "🔴 Retrieving model $MODEL_NAME:$MODEL_TAG..."
ollama pull "$MODEL_NAME:$MODEL_TAG"
echo "🟢 Model download complete!"

# Shut down the background Ollama server.
kill $serve_pid
wait $serve_pid 2>/dev/null