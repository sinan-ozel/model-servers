#!/bin/bash

# Script to create a Docker Hub repository if it doesn't exist
# Usage: ./create_dockerhub_repo.sh <ollama_version> [description] [is_private]
# Note: DOCKERHUB_NAMESPACE environment variable is required

set -e

OLLAMA_VERSION=$1
DESCRIPTION=${2:-"Model servers based on Ollama with pre-downloaded models, allowing version freeze and quick startup."}
IS_PRIVATE=${3:-false}

# Construct repository name with ollama prefix
REPO_NAME="ollama.${OLLAMA_VERSION}"

NAMESPACE=$DOCKERHUB_NAMESPACE
if [ -z "$NAMESPACE" ] || [ -z "$OLLAMA_VERSION" ]; then
    echo "Usage: $0 <ollama_version> [description] [is_private]"
    echo "Example: $0 0.13.5 'Ollama v0.13.5 with preloaded models' false"
    echo "Error: DOCKERHUB_NAMESPACE environment variable is required"
    exit 1
fi

if [ -z "$DOCKERHUB_TOKEN" ]; then
    echo "Error: DOCKERHUB_TOKEN environment variable is required"
    echo "You can get a token from: https://hub.docker.com/settings/security"
    exit 1
fi

FULL_REPO_NAME="${NAMESPACE}/${REPO_NAME}"

echo "Checking if Docker Hub repository ${FULL_REPO_NAME} exists..."

# Check if repository exists
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -H "Authorization: Bearer ${DOCKERHUB_TOKEN}" \
    "https://hub.docker.com/v2/repositories/${FULL_REPO_NAME}/")

if [ "$HTTP_STATUS" = "200" ]; then
    echo "Repository ${FULL_REPO_NAME} already exists"
    exit 0
elif [ "$HTTP_STATUS" = "404" ]; then
    echo "Repository ${FULL_REPO_NAME} does not exist. Creating it..."

    # Create the repository
    CREATE_RESPONSE=$(curl -s -X POST \
        -H "Authorization: Bearer ${DOCKERHUB_TOKEN}" \
        -H "Content-Type: application/json" \
        -d "{
            \"name\": \"${REPO_NAME}\",
            \"namespace\": \"${NAMESPACE}\",
            \"description\": \"${DESCRIPTION}\",
            \"is_private\": ${IS_PRIVATE},
            \"registry\": \"docker\"
        }" \
        "https://hub.docker.com/v2/repositories/")

    if echo "$CREATE_RESPONSE" | grep -q '"name"'; then
        echo "Successfully created repository ${FULL_REPO_NAME}"
        echo "Repository URL: https://hub.docker.com/r/${FULL_REPO_NAME}"

        # Update repository with overview text
        SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
        OVERVIEW_FILE="${SCRIPT_DIR}/../dockerhub_overview.txt"

        if [ -f "$OVERVIEW_FILE" ]; then
            echo "Updating repository overview..."
            OVERVIEW_CONTENT=$(cat "$OVERVIEW_FILE")

            UPDATE_RESPONSE=$(curl -s -X PATCH \
                -H "Authorization: Bearer ${DOCKERHUB_TOKEN}" \
                -H "Content-Type: application/json" \
                -d "{
                    \"full_description\": \"${OVERVIEW_CONTENT}\"
                }" \
                "https://hub.docker.com/v2/repositories/${FULL_REPO_NAME}/")

            if echo "$UPDATE_RESPONSE" | grep -q '"name"'; then
                echo "Successfully updated repository overview"
            else
                echo "Warning: Failed to update repository overview. Response:"
                echo "$UPDATE_RESPONSE"
            fi
        else
            echo "Warning: Overview file not found at ${OVERVIEW_FILE}"
        fi
    else
        echo "Failed to create repository. Response:"
        echo "$CREATE_RESPONSE"
        exit 1
    fi
else
    echo "Unexpected response when checking repository (HTTP $HTTP_STATUS)"
    echo "This might indicate an authentication issue or API changes"
    exit 1
fi