#!/bin/bash

OUT_FILE="/metrics/gpu.json"
INTERVAL=2

mkdir -p /metrics
echo "[INFO] Starting GPU metrics writer..."

# Check if nvidia-smi is available
if ! command -v nvidia-smi &> /dev/null; then
    echo "[INFO] nvidia-smi not found. Exiting."
    exit 0
fi

while true; do
    FREE=$(nvidia-smi --query-gpu=memory.free --format=csv,noheader,nounits | head -n1)
    USED=$(nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits | head -n1)
    TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits | head -n1)

    cat <<EOF > "$OUT_FILE"
{
  "free": $FREE,
  "used": $USED,
  "total": $TOTAL
}
EOF

    sleep $INTERVAL
done
