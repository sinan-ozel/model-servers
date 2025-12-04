#!/bin/bash
set -e

# Test LLM deployment on EKS
# Usage: ./scripts/test_llm_on_cloud.sh <model_file>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <model_file>"
    echo "Example: $0 gemma3_12b.yaml"
    exit 1
fi

MODEL_FILE="$1"
export KUBECONFIG="${WORKSPACE_FOLDER:-$(pwd)}/.iac/kubeconfig.yaml"

echo "=== Testing LLM Model on Cloud ==="
echo "Model file: $MODEL_FILE"

# Parse model metadata
MODEL_NAME=$(yq eval '.name' "model_metadata/$MODEL_FILE")
MODEL_TAG=$(yq eval '.tag' "model_metadata/$MODEL_FILE")
OLLAMA_MODEL="$MODEL_NAME:$MODEL_TAG"
IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"

echo "Model name: $MODEL_NAME"
echo "Model tag: $MODEL_TAG"
echo "Ollama model: $OLLAMA_MODEL"
echo "Image tag: $IMAGE_TAG"

# Get LoadBalancer hostname
echo "=== Getting LoadBalancer hostname ==="
LB_HOSTNAME=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

if [ -z "$LB_HOSTNAME" ]; then
    echo "Error: LoadBalancer hostname not found"
    echo "Make sure nginx-ingress is deployed and running"
    exit 1
fi

echo "LoadBalancer hostname: $LB_HOSTNAME"

# Construct test URL
EKS_URL="http://$LB_HOSTNAME/$MODEL_NAME/$MODEL_TAG"
echo "Test URL: $EKS_URL"

# Check if deployment is ready
echo "=== Checking deployment readiness ==="
kubectl wait --for=condition=available --timeout=300s deployment/basic-llm-basic-deployment || echo "Deployment wait timeout, continuing with test..."

# Run the test
echo "=== Running Test ==="
echo "Testing model: $OLLAMA_MODEL"
echo "Image tag: $IMAGE_TAG"
echo "URL: $EKS_URL"
echo ""

./test_ollama_eks.sh "$OLLAMA_MODEL" "$EKS_URL" "$IMAGE_TAG"