#!/bin/bash
set -e

export KUBECONFIG="${WORKSPACE_FOLDER:-$(pwd)}/.iac/kubeconfig.yaml"

echo "=== Getting Model Server URL ==="

# Get the ingress for the model server
INGRESS_NAME=$(kubectl get ingress -l app.kubernetes.io/instance=basic-llm -o jsonpath='{.items[0].metadata.name}')

if [ -z "$INGRESS_NAME" ]; then
    echo "Error: No model server ingress found"
    exit 1
fi

echo "Found ingress: $INGRESS_NAME"

# Get the hostname from the ingress
LB_HOST=$(kubectl get ingress "$INGRESS_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}{.status.loadBalancer.ingress[0].ip}')

if [ -z "$LB_HOST" ]; then
    echo "Error: LoadBalancer not found in ingress status"
    exit 1
fi

# Get the path from the ingress (strip the regex pattern to get just the base path)
MODEL_PATH=$(kubectl get ingress "$INGRESS_NAME" -o jsonpath='{.spec.rules[0].http.paths[0].path}' | sed 's/(\/.*)$//')

if [ -z "$MODEL_PATH" ]; then
    echo "Error: Path not found in ingress"
    exit 1
fi

echo "LoadBalancer: $LB_HOST"
echo "Model path: $MODEL_PATH"
echo ""
echo "=== Model Server URL ==="
echo "http://$LB_HOST$MODEL_PATH"
