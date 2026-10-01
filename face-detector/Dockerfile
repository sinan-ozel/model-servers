FROM python:3.12-slim

# ----------------------------------------------------
# System packages
# ----------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        libgl1 \
        libglib2.0-0 \
    && rm -rf /var/lib/apt/lists/*

# ----------------------------------------------------
# Requirements
# ----------------------------------------------------
COPY requirements.txt /requirements.txt

RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir -r /requirements.txt

# ----------------------------------------------------
# Bundled model weights (see scripts/download_face_detector_models.sh)
# ----------------------------------------------------
COPY --chmod=755 model-cache/ /app/model-cache/

# ----------------------------------------------------
# App code
# ----------------------------------------------------
COPY src/ /app/src/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /app
ENV PYTHONPATH=/app
ENV MODEL_CACHE_DIR=/app/model-cache

EXPOSE 8080
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:8080/status || exit 1

ENTRYPOINT ["/entrypoint.sh"]
CMD ["serve"]
