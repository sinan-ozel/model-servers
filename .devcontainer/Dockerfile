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
    gnupg \
    lsb-release \
    software-properties-common

# Docker CLI
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - && \
    add-apt-repository \
      "deb [arch=$(dpkg --print-architecture)] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" && \
    apt-get update && apt-get install -y docker-ce-cli

# kubectl
RUN curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    install -m 0755 kubectl /usr/local/bin/kubectl && rm kubectl

# yq
RUN wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && \
    chmod +x /usr/local/bin/yq

# GitHub CLI
RUN type -p curl >/dev/null || apt-get install -y curl && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && apt-get install -y gh

# Create ubuntu user and add to docker group for docker-in-docker
RUN usermod -aG sudo ubuntu && \
    echo 'ubuntu ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers && \
    groupadd -f docker && \
    usermod -aG docker ubuntu

# Create workspace directory
RUN mkdir -p /workspace && chown ubuntu:ubuntu /workspace

WORKDIR /workspace

CMD [ "bash" ]
