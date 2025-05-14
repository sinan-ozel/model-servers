FROM ollama/ollama:0.6.5

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

# RUN mv /root/.ollama/models/* /root/.ollama/

RUN ls -al /root/.ollama/models/blobs/sha256-*

# Copy server launch script
COPY run_server.sh .
RUN chmod +x run_server.sh

COPY preload_model.sh .
RUN chmod +x preload_model.sh

EXPOSE 11434
ENTRYPOINT ["./run_server.sh"]
