#!/usr/bin/env bash

echo "🚀 Starting push to AWS"

set -euo pipefail

OLLAMA_VERSION="0.12.11"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log()    { echo -e "${BLUE}$1${NC}"; }
warn()   { echo -e "${YELLOW}$1${NC}"; }
error()  { echo -e "${RED}$1${NC}" >&2; }

# Get YAML file path
MODEL_FILE="$1"

# Check for yq
if ! command -v yq >/dev/null 2>&1; then
  error "❌ 'yq' is not installed. Please install it from https://github.com/mikefarah/yq"
  exit 1
fi

# Parse model metadata
MODEL_NAME=$(yq e '.name' "$MODEL_FILE")
MODEL_TAG=$(yq e '.tag' "$MODEL_FILE")
LICENSE=$(yq e '.license' "$MODEL_FILE")
MODEL_SIZE=$(yq e '.memory.model_size' "$MODEL_FILE")
MEM_MIN=$(yq e '.memory.min' "$MODEL_FILE")
MEM_RECOMMENDED=$(yq e '.memory.recommended' "$MODEL_FILE")

# Show parsed values
echo "${GREEN}Parsed model metadata:${NC}"
echo "  Name:         $MODEL_NAME"
echo "  Tag:          $MODEL_TAG"
echo "  License:      $LICENSE"
echo "  Model Size:   $MODEL_SIZE"
echo "  Memory Min:   $MEM_MIN"
echo "  Memory Rec.:  $MEM_RECOMMENDED"
echo ""

# Check AWS region
if [[ -z "${AWS_REGION:-}" ]]; then
  error "❌ Environment variable AWS_REGION is not set. Exiting."
  exit 1
fi

# Get AWS account ID
log "🔍 Fetching AWS account ID..."
ACCOUNT_ID=$(aws sts get-caller-identity --query 'Account' --output text)
if [[ -z "$ACCOUNT_ID" ]]; then
  error "❌ Failed to get AWS account ID."
  exit 1
fi

HOSTNAME="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
REPO_NAME="model-servers/ollama.${OLLAMA_VERSION}"
REMOTE_IMAGE="${HOSTNAME}/${REPO_NAME}:${MODEL_NAME}-${MODEL_TAG}"
LOCAL_IMAGE="model-servers/ollama.${OLLAMA_VERSION}:${MODEL_NAME}-${MODEL_TAG}"

# Authenticate with ECR
log "🔐 Logging in to AWS ECR..."
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$HOSTNAME"

# Ensure ECR repo exists
log "📁 Checking for repository $REPO_NAME..."
if ! aws ecr describe-repositories --repository-names "$REPO_NAME" --region "$AWS_REGION" >/dev/null 2>&1; then
  warn "📁 Repository does not exist. Creating it..."
  aws ecr create-repository --repository-name "$REPO_NAME" --region "$AWS_REGION" >/dev/null
  log "✅ Repository created."
else
  log "✅ Repository exists."
fi

# Tag and push Docker image
log "🏷️ Tagging image $LOCAL_IMAGE as $REMOTE_IMAGE..."
docker tag "$LOCAL_IMAGE" "$REMOTE_IMAGE"

log "📤 Pushing image to ECR..."
docker push "$REMOTE_IMAGE"

log "✅ Push to AWS ECR completed successfully."
