#!/bin/bash
set -e

# Deploy LLM to EKS with nginx ingress
# Usage: ./scripts/deploy_llm.sh <model_file>

if [ $# -ne 1 ]; then
    echo "Usage: $0 <model_file>"
    echo "Example: $0 gemma3_12b.yaml"
    exit 1
fi

MODEL_FILE="$1"
export KUBECONFIG="${WORKSPACE_FOLDER:-$(pwd)}/.iac/kubeconfig.yaml"

echo "=== Deploying LLM Model ==="
echo "Model file: $MODEL_FILE"

# Parse model metadata
MODEL_NAME=$(yq eval '.name' "model_metadata/$MODEL_FILE")
MODEL_TAG=$(yq eval '.tag' "model_metadata/$MODEL_FILE")
IMAGE_TAG="$MODEL_NAME-$MODEL_TAG"

echo "Model name: $MODEL_NAME"
echo "Model tag: $MODEL_TAG"
echo "Image tag: $IMAGE_TAG"

# Install NVIDIA GPU device plugin
echo "=== Installing NVIDIA GPU device plugin ==="
if ! kubectl get daemonset -n kube-system nvidia-device-plugin-daemonset 2>/dev/null; then
    echo "Installing NVIDIA GPU device plugin..."
    kubectl apply -f https://raw.githubusercontent.com/NVIDIA/k8s-device-plugin/v0.14.0/nvidia-device-plugin.yml
    echo "Waiting for GPU device plugin to be ready..."
    kubectl wait --for=condition=ready pod -l name=nvidia-device-plugin-ds -n kube-system --timeout=180s || echo "GPU plugin wait timeout, continuing..."
else
    echo "NVIDIA GPU device plugin already installed"
fi

# Check if nginx-ingress is already installed
echo "=== Checking nginx-ingress installation ==="
if ! helm list -n ingress-nginx | grep -q nginx-ingress; then
    echo "Installing nginx-ingress..."
    helm dependency update ./helm/nginx-ingress
    helm install nginx-ingress ./helm/nginx-ingress --create-namespace --namespace ingress-nginx
else
    echo "nginx-ingress already installed"
fi

# Wait for LoadBalancer to be ready
echo "=== Waiting for LoadBalancer ==="
kubectl wait --for=condition=Ready --timeout=180s pod -l app.kubernetes.io/name=ingress-nginx -n ingress-nginx || echo "Pod wait timeout, continuing..."
sleep 10

# Get LoadBalancer hostname
LB_HOSTNAME=$(kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')
echo "LoadBalancer hostname: $LB_HOSTNAME"

if [ -z "$LB_HOSTNAME" ]; then
    echo "Error: LoadBalancer hostname not found"
    exit 1
fi

# Find GPU node type based on nvidia.com/gpu taint
echo "=== Finding GPU node type ==="
GPU_NODE_TYPE=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.taints != null) | select(.spec.taints[] | .key == "nvidia.com/gpu" and .value == "true") | .metadata.labels["node.kubernetes.io/instance-type"]' | head -1)

if [ -z "$GPU_NODE_TYPE" ]; then
    echo "Warning: No GPU node with nvidia.com/gpu=true taint found, using default g4dn.xlarge"
    GPU_NODE_TYPE="g4dn.xlarge"
else
    echo "Found GPU node type: $GPU_NODE_TYPE"
fi

# Deploy LLM service
MODEL_PATH="/$MODEL_NAME/$MODEL_TAG"
echo "=== Deploying LLM service ==="
echo "Model path: $MODEL_PATH"

# Remove existing deployment if it exists
if helm list | grep -q basic-llm; then
    echo "Removing existing basic-llm deployment..."
    helm uninstall basic-llm
    sleep 5
fi

# Install new deployment
helm install basic-llm ./helm/basic-llm \
    --set image.tag="$IMAGE_TAG" \
    --set ingress.hosts[0].host="$LB_HOSTNAME" \
    --set ingress.hosts[0].paths[0].path="$MODEL_PATH" \
    --set model.name="$MODEL_NAME" \
    --set model.tag="$MODEL_TAG" \
    --set nodeSelector.instanceType="$GPU_NODE_TYPE"

echo "=== Deployment Complete ==="
echo "Access URL: http://$LB_HOSTNAME$MODEL_PATH"
echo ""
echo "=== Deployment Status ==="
kubectl get pods,svc,ingress