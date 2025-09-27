FROM ollama/ollama:0.12.2

ARG MODEL_NAME
ARG MODEL_TAG

ENV MODEL_NAME=${MODEL_NAME}
ENV MODEL_TAG=${MODEL_TAG}

RUN apt update
RUN apt install curl -y
RUN rm -rf /var/lib/apt/lists/*


# Copy pre-pulled models into the image
COPY model-cache/ /root/.ollama/
RUN chmod -R 444 /root/.ollama/models

RUN ls -al /root/.ollama/

RUN ls -al /root/.ollama/models/blobs/sha256-*

COPY gpu_metrics_writer.sh /usr/local/bin/gpu_metrics_writer.sh
RUN chmod +x /usr/local/bin/gpu_metrics_writer.sh

# Copy server launch script
COPY run_server.sh .
RUN chmod +x run_server.sh

EXPOSE 11434
ENTRYPOINT ["./run_server.sh"]
