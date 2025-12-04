#!/usr/bin/env bash
set -e

VERSION="0.1.0"

INPUT="$1"

MODEL_PUBLISHER="${INPUT%%/*}"
MODEL_NAME="${INPUT#*/}"

docker stop text2image-server || true
docker rm text2image-server || true

docker run -d \
    --gpus all \
    -p 8000:8000 \
    --name text2image-server \
    model-servers/text2image.v${VERSION}:${MODEL_PUBLISHER}--${MODEL_NAME}

# Wait for server to become available
echo "Waiting for API to become ready..."
until curl -sf http://localhost:8000/openapi.json >/dev/null 2>&1; do
    sleep 1
done

# Create output folder
OUTDIR="text2image/swagger/${MODEL_PUBLISHER}/${MODEL_NAME}/v${VERSION}"
mkdir -p "$OUTDIR"

# Download Swagger / OpenAPI spec
curl -s http://localhost:8000/openapi.json | jq '.' > "${OUTDIR}/openapi.json"
yq -P < "${OUTDIR}/openapi.json" > "${OUTDIR}/openapi.yaml"
curl -s http://localhost:8000/docs -o "${OUTDIR}/swagger.html"
curl -s http://localhost:8000/redoc -o "${OUTDIR}/redoc.html"


echo "Swagger saved to ${OUTDIR}/openapi.json"
echo "Swagger saved to ${OUTDIR}/openapi.yaml"
echo "Swagger saved to ${OUTDIR}/swagger.html"
echo "Swagger saved to ${OUTDIR}/redoc.html"

# Git add, commit, and push
git add "${OUTDIR}/openapi.json" \
        "${OUTDIR}/openapi.yaml" \
        "${OUTDIR}/swagger.html" \
        "${OUTDIR}/redoc.html"

git commit -m "Add swagger for ${MODEL_PUBLISHER}/${MODEL_NAME} v${VERSION}"
git push
