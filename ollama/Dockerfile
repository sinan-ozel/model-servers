FROM ollama/ollama:0.6.5

ARG MODEL_NAME
ARG MODEL_TAG

ENV OLLAMA_MODELS=/root/.ollama
ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_TAG=${MODEL_TAG}

# Copy pre-pulled models into the image
COPY model-cache/ /root/.ollama/
RUN chmod -R 555 /root/.ollama/

RUN ls -al /root/.ollama/models/blobs/sha256-*
RUN ls -al /root/.ollama/models/manifests/registry.ollama.ai/library

# Copy server launch script
COPY run_server.sh .
RUN chmod +x run_server.sh

EXPOSE 11434
ENTRYPOINT ["./run_server.sh"]
