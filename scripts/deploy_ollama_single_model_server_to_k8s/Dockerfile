FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Basic tools
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    git \
    jq \
    tree \
    apt-transport-https \
    wget \
    vim \
    gnupg \
    lsb-release \
    software-properties-common \
    sudo \
    bash \
    dnsutils \
    netcat-openbsd \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -m 0755 kubectl /usr/local/bin/kubectl && \
    rm kubectl

# yq
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod +x /usr/local/bin/yq

# Helm
RUN curl https://get.helm.sh/helm-v3.14.0-linux-amd64.tar.gz -o helm.tar.gz && \
    tar -zxvf helm.tar.gz && \
    mv linux-amd64/helm /usr/local/bin/helm && \
    rm -rf helm.tar.gz linux-amd64/

# AWS CLI
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" && \
    apt-get update && apt-get install -y unzip && \
    unzip awscliv2.zip && \
    ./aws/install && \
    rm -rf awscliv2.zip aws && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Create app directory and subdirectories
WORKDIR /app
RUN mkdir -p /app/.iac

# Copy deployment script and resources
COPY scripts/deploy_ollama_single_model_server_to_k8s/containerized_scripts/deploy_ollama_single_model_server_to_k8s.sh /app/
COPY helm/ /app/helm/
COPY model_metadata/ /app/model_metadata/

# Set default command
ENTRYPOINT ["/app/deploy_ollama_single_model_server_to_k8s.sh"]