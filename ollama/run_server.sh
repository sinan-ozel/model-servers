#!/bin/bash

# Start GPU metrics writer (non-blocking)
echo "Starting GPU metrics writer..."
/usr/local/bin/gpu_metrics_writer.sh &

# Start Ollama server in the background
echo "Starting Ollama server..."
OLLAMA_HOST=0.0.0.0 /bin/ollama serve &
serve_pid=$!

# Wait for server to be ready (you could add health check later)
sleep 5

# Wait for Ollama to stay up
wait $serve_pid