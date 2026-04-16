# FROM nvidia/cuda:12.8.0-devel-ubuntu22.04 AS whisper-builder

# RUN apt-get update && apt-get install -y --no-install-recommends \
#     cmake git g++ ninja-build pkg-config \
#     && rm -rf /var/lib/apt/lists/*

# RUN git clone --depth 1 --branch v1.8.1 https://github.com/ggml-org/whisper.cpp /whisper.cpp

# WORKDIR /whisper.cpp
# RUN cmake -B build \
#       -DGGML_CUDA=1 \
#       -DWHISPER_BUILD_SERVER=ON \
#       -DCMAKE_BUILD_TYPE=Release \
#       -G Ninja \
#     && cmake --build build --target whisper-server -j$(nproc)

FROM ghcr.io/ggml-org/llama.cpp:server-cuda

ARG MODEL_NAME
ARG MODEL_TAG
ARG GGUF_FILENAME
ARG MMPROJ_FILENAME=""
# ARG WHISPER_FILENAME=""

ENV MODEL_ALIAS="${MODEL_NAME}:${MODEL_TAG}"
ENV GGUF_FILENAME="${GGUF_FILENAME}"
ENV MMPROJ_FILENAME="${MMPROJ_FILENAME}"
# ENV WHISPER_FILENAME="${WHISPER_FILENAME}"

# COPY --from=whisper-builder /whisper.cpp/build/bin/whisper-server /app/whisper-server

COPY *.gguf /models/
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080
# EXPOSE 8081
ENTRYPOINT ["/entrypoint.sh"]
