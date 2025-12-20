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
WORKSPACE_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

echo "=== Running Containerized Deployment ==="
echo "Model file: $MODEL_FILE"
echo "Workspace: $WORKSPACE_DIR"

# Check if kubeconfig exists
KUBECONFIG_PATH="$WORKSPACE_DIR/.iac/kubeconfig.yaml"
if [ ! -f "$KUBECONFIG_PATH" ]; then
    echo "Warning: kubeconfig not found at $KUBECONFIG_PATH"
    echo ""
    echo "Options to resolve this:"
    echo "1. Run the download_model_cluster_kubeconfig task first"
    echo "2. Manually copy your kubeconfig to $KUBECONFIG_PATH"
    echo "3. Set KUBECONFIG environment variable to point to your kubeconfig file"
    echo ""

    # Check if KUBECONFIG env var is set and file exists
    if [ -n "$KUBECONFIG" ] && [ -f "$KUBECONFIG" ]; then
        echo "Using KUBECONFIG environment variable: $KUBECONFIG"
        KUBECONFIG_PATH="$KUBECONFIG"
    else
        echo "Error: No valid kubeconfig found"
        exit 1
    fi
fi

# Run deployment container
CONTAINER_TAG="model-server-deployer:latest"
docker run --rm \
    -v "$KUBECONFIG_PATH:/app/.iac/kubeconfig.yaml:ro" \
    -v "$HOME/secrets/.aws:/root/.aws:ro" \
    -e KUBECONFIG="/app/.iac/kubeconfig.yaml" \
    -e WORKSPACE_FOLDER="/app" \
    "$CONTAINER_TAG" \
    "$MODEL_FILE"

echo "=== Containerized Deployment Complete ==="