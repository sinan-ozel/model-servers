#!/usr/bin/env bash
set -e

# Dumps the face-detector HTTP server's OpenAPI/Swagger docs to face-detector/openapi/.

IMAGE_NAME="model-servers/face-detector:yunet-cpu"
CONTAINER_NAME="face-detector-openapi-dump"
PORT=8092

cleanup() {
  docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cleanup

docker run -d \
  -p "${PORT}:8080" \
  --name "$CONTAINER_NAME" \
  "$IMAGE_NAME"

echo "Waiting for API to become ready..."
until curl -sf "http://localhost:${PORT}/openapi.json" >/dev/null 2>&1; do
  sleep 1
done

OUTDIR="face-detector/openapi"
mkdir -p "$OUTDIR"

curl -s "http://localhost:${PORT}/openapi.json" | jq '.' > "${OUTDIR}/openapi.json"
yq -y '.' < "${OUTDIR}/openapi.json" > "${OUTDIR}/openapi.yaml"
curl -s "http://localhost:${PORT}/docs" -o "${OUTDIR}/swagger.html"
curl -s "http://localhost:${PORT}/redoc" -o "${OUTDIR}/redoc.html"

echo "OpenAPI docs saved to ${OUTDIR}/"
