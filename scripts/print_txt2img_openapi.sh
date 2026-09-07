#!/usr/bin/env bash
set -e

# Dumps the txt2img HTTP server's OpenAPI/Swagger docs to txt2img/openapi/.

IMAGE_NAME="model-servers/txt2img:zimage-cuda"
CONTAINER_NAME="txt2img-openapi-dump"
PORT=8092

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

echo "Waiting for API to become ready (model load can take a while)..."
MAX_WAIT=300
WAITED=0
until curl -sf "http://localhost:${PORT}/openapi.json" >/dev/null 2>&1; do
  if [ "$WAITED" -ge "$MAX_WAIT" ]; then
    echo "❌ API did not become ready within ${MAX_WAIT}s"
    docker logs "$CONTAINER_NAME" || true
    exit 1
  fi
  sleep 2
  WAITED=$((WAITED+2))
done

OUTDIR="txt2img/openapi"
mkdir -p "$OUTDIR"

curl -s "http://localhost:${PORT}/openapi.json" | jq '.' > "${OUTDIR}/openapi.json"
yq -y '.' < "${OUTDIR}/openapi.json" > "${OUTDIR}/openapi.yaml"
curl -s "http://localhost:${PORT}/docs" -o "${OUTDIR}/swagger.html"
curl -s "http://localhost:${PORT}/redoc" -o "${OUTDIR}/redoc.html"

echo "OpenAPI docs saved to ${OUTDIR}/"
