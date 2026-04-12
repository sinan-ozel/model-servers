FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ARG MODEL_NAME
ARG MODEL_TAG
ARG GGUF_FILENAME
ARG MMPROJ_FILENAME=""

ENV MODEL_ALIAS="${MODEL_NAME}:${MODEL_TAG}"
ENV GGUF_FILENAME="${GGUF_FILENAME}"
ENV MMPROJ_FILENAME="${MMPROJ_FILENAME}"

COPY *.gguf /models/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
