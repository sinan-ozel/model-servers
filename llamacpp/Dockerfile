FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ARG MODEL_NAME
ARG MODEL_TAG
ENV MODEL_ALIAS="${MODEL_NAME}:${MODEL_TAG}"

COPY model.gguf /models/model.gguf
COPY mmproj.gguf /models/mmproj.gguf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
