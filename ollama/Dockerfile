FROM ollama/ollama:0.6.5

# Pass in build-time variables that will be used by the scripts.
ARG MODEL_NAME
ARG MODEL_TAG
ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_TAG=${MODEL_TAG}

ENV OLLAMA_MODELS=/root/.ollama

WORKDIR /tmp

# Copy and run the download script.
COPY download_model.sh .
RUN chmod +x download_model.sh
RUN ./download_model.sh
RUN rm download_model.sh

# Copy and set executable permission on the preload script.
COPY preload_model.sh .
COPY run_server.sh .
RUN chmod +x preload_model.sh run_server.sh

EXPOSE 11434

ENTRYPOINT ["./run_server.sh"]

