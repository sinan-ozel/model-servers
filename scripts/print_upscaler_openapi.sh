#!/usr/bin/env bash
set -e

# Dumps the upscaler HTTP server's OpenAPI/Swagger docs to upscaler/openapi/.

IMAGE_NAME="model-servers/upscaler:upscaler-realesrgan"
CONTAINER_NAME="upscaler-openapi-dump"
PORT=8091

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d --gpus all \
  -p "${PORT}:8080" \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME"

echo "Waiting for API to become ready..."
until curl -sf "http://localhost:${PORT}/openapi.json" >/dev/null 2>&1; do
  sleep 1
done

OUTDIR="upscaler/openapi"
mkdir -p "$OUTDIR"

curl -s "http://localhost:${PORT}/openapi.json" | jq '.' > "${OUTDIR}/openapi.json"
yq -y '.' < "${OUTDIR}/openapi.json" > "${OUTDIR}/openapi.yaml"
curl -s "http://localhost:${PORT}/docs" -o "${OUTDIR}/swagger.html"
curl -s "http://localhost:${PORT}/redoc" -o "${OUTDIR}/redoc.html"

echo "OpenAPI docs saved to ${OUTDIR}/"
