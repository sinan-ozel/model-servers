#!/bin/bash
set -e

# Run containerized deployment
# Usage: ./scripts/run_containerized_deployment.sh <model_file>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <model_file>"
    echo "Example: $0 gemma3_12b.yaml"
    exit 1
fi

MODEL_FILE="$1"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== Running Containerized Deployment ==="
echo "Model file: $MODEL_FILE"

# Check if kubeconfig exists
if [ ! -f "$WORKSPACE_DIR/.iac/kubeconfig.yaml" ]; then
    echo "Error: kubeconfig not found at .iac/kubeconfig.yaml"
    echo "Run the download_model_cluster_kubeconfig task first"
    exit 1
fi

# Check if AWS credentials exist
if [ ! -f "$WORKSPACE_DIR/.aws/credentials" ] || [ ! -f "$WORKSPACE_DIR/.aws/config" ]; then
    echo "Error: AWS credentials not found at .aws/"
    echo "Copy your AWS credentials to the workspace .aws/ directory"
    exit 1
fi

CONTAINER_TAG="model-server-deployer:latest"

# Run with relative path mounts from workspace
docker run --rm \
    --network host \
    -v "$WORKSPACE_DIR/.aws:/root/.aws:ro" \
    -v "$WORKSPACE_DIR/.iac:/app/.iac:ro" \
    "$CONTAINER_TAG" \
    "$MODEL_FILE"

echo "=== Containerized Deployment Complete ==="