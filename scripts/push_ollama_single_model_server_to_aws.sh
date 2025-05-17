#!/usr/bin/env bash

set -euo pipefail

# Get YAML file path
MODEL_FILE="$1"

# Requires: yq (https://github.com/mikefarah/yq)
if ! command -v yq >/dev/null 2>&1; then
  echo "❌ yq is not installed. Please install it to parse YAML." >&2
  exit 1
fi

# Extract values from YAML
MODEL_NAME=$(yq e '.name' "$MODEL_FILE")
MODEL_TAG=$(yq e '.tag' "$MODEL_FILE")
LICENSE=$(yq e '.license' "$MODEL_FILE")
MODEL_SIZE=$(yq e '.memory.model_size' "$MODEL_FILE")
MEM_MIN=$(yq e '.memory.min' "$MODEL_FILE")
MEM_RECOMMENDED=$(yq e '.memory.recommended' "$MODEL_FILE")

# AWS region from env var
if [[ -z "${AWS_REGION:-}" ]]; then
  echo "❌ Environment variable AWS_REGION is not set. Exiting." >&2
  exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
HOSTNAME="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO_NAME="model-servers/ollama-server"

# Login to ECR
echo "🔐 Logging into AWS ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$HOSTNAME"

# Ensure repo exists
echo "📁 Ensuring repository $REPO_NAME exists..."
if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  echo "📁 Repository does not exist. Creating..."
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION" >/dev/null
else
  echo "✅ Repository exists."
fi

# Tag and push the image
LOCAL_IMAGE="model-servers/ollama-server:${MODEL_NAME}-${MODEL_TAG}"
REMOTE_IMAGE="${HOSTNAME}/${REPO_NAME}:${MODEL_NAME}-${MODEL_TAG}"

echo "🏷️ Tagging image $LOCAL_IMAGE as $REMOTE_IMAGE..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

echo "📤 Pushing image to ECR..."
docker push "$REMOTE_IMAGE"
