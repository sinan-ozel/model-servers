FROM ollama/ollama:0.6.5

ARG MODEL_NAME
ARG MODEL_TAG
ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_TAG=${MODEL_TAG}
ENV OLLAMA_MODELS=/root/.ollama

WORKDIR /tmp

# Download the model within a single RUN command to preserve state
RUN /bin/ollama serve & \
    serve_pid=$! && \
    sleep 5 && \
    echo "🔴 Retrieving model $MODEL_NAME:$MODEL_TAG..." && \
    ollama pull "$MODEL_NAME:$MODEL_TAG" && \
    echo "🟢 Model download complete!" && \
    kill $serve_pid && \
    wait $serve_pid 2>/dev/null

# Copy server launch script
COPY run_server.sh .
RUN chmod +x run_server.sh

EXPOSE 11434
ENTRYPOINT ["./run_server.sh"]
