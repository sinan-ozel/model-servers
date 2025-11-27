FROM nvidia/cuda:12.5.1-base-ubuntu22.04

# ----------------------------------------------------
# System packages
# ----------------------------------------------------
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        curl \
        nodejs \
        npm \
        git \
        python3.11 \
        python3-pip \
        python3.11-venv \
    && rm -rf /var/lib/apt/lists/*



# ----------------------------------------------------
# Requirements
# ----------------------------------------------------
COPY requirements.txt /requirements.txt

RUN pip3 install --upgrade pip && \
    pip3 install -r /requirements.txt

RUN pip3 freeze > /requirements.frozen.txt

# ----------------------------------------------------
# Hugging Face cache
# ----------------------------------------------------
COPY model-cache/ /app/hf/hub/

# Read-only for everything except directories (directories need +x)
RUN chmod -R a=rX /app/hf

ENV HF_HOME=/app/hf

# ----------------------------------------------------
# App code + config
# ----------------------------------------------------
COPY server/ /app/server/
COPY MODEL_PATH.txt /app/MODEL_PATH.txt
COPY PIPELINE.txt /app/PIPELINE.txt1

WORKDIR /app

CMD ["uvicorn", "server.app:app", "--host", "0.0.0.0", "--port", "8000"]