#!/bin/bash
set -e

# Build deployment container
# Usage: ./scripts/build_deployment_container.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Building Deployment Container ==="
echo "Workspace: $WORKSPACE_DIR"

# Build Docker image
CONTAINER_TAG="model-server-deployer:latest"
docker build -t "$CONTAINER_TAG" -f "$WORKSPACE_DIR/scripts/deploy_ollama_single_model_server_to_k8s/Dockerfile" "$WORKSPACE_DIR"

echo "=== Build Complete ==="
echo "Container tag: $CONTAINER_TAG"