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

# Detect if we're in a dev container with DooD and get the host paths
if [ "$REMOTE_CONTAINERS" = "true" ] && command -v docker >/dev/null 2>&1; then
    # Get the host mount path from the current container
    HOST_MOUNT=$(docker inspect $(hostname) --format '{{range .Mounts}}{{if eq .Destination "/workspace"}}{{.Source}}{{end}}{{end}}' 2>/dev/null || echo "")
    if [ -n "$HOST_MOUNT" ]; then
        HOST_WORKSPACE_DIR="$HOST_MOUNT"
        # Infer host home from workspace path (e.g., /Users/username/path/to/workspace -> /Users/username)
        HOST_HOME_DIR=$(echo "$HOST_MOUNT" | sed -E 's|(/[^/]+/[^/]+)/.*|\1|')
    else
        HOST_WORKSPACE_DIR="$WORKSPACE_DIR"
        HOST_HOME_DIR="$HOME"
    fi
else
    # Running on host directly
    HOST_WORKSPACE_DIR="$WORKSPACE_DIR"
    HOST_HOME_DIR="$HOME"
fi

echo "=== Running Containerized Deployment ==="
echo "Model file: $MODEL_FILE"
echo "Workspace: $WORKSPACE_DIR"
echo "Docker mount path: $HOST_WORKSPACE_DIR"

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

# Mount AWS credentials directory if available
AWS_MOUNT=""
if [ -f "$HOME/.aws/credentials" ] && [ -f "$HOME/.aws/config" ]; then
    echo "Mounting AWS credentials from ~/.aws"
    AWS_MOUNT="-v $HOST_HOME_DIR/.aws:/root/.aws:ro"
elif [ -d "$HOME/secrets/.aws" ]; then
    echo "Mounting AWS credentials from ~/secrets/.aws"
    AWS_MOUNT="-v $HOST_HOME_DIR/secrets/.aws:/root/.aws:ro"
else
    echo "Warning: No AWS credentials found"
fi

# Run without workspace mount - everything is copied during build
docker run --rm \
    $AWS_MOUNT \
    -e KUBECONFIG="/app/.iac/kubeconfig.yaml" \
    "$CONTAINER_TAG" \
    "$MODEL_FILE"

echo "=== Containerized Deployment Complete ==="