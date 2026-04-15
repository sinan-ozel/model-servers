The containers are llama.cpp servers with LLM models already downloaded and baked in.

# What's the point?

**(1) Faster start** — The model is already downloaded. No waiting on Hugging Face at startup.

**(2) Frozen models** — The model version is locked at build time. Upstream updates will not break your prompts or optimizations.

**(3) Tested on real hardware** — Every model is run through an automated test pipeline on a machine with a 6GB VRAM GPU (GeForce GTX 1660 Ti). The image will not be published unless inference actually works on that hardware.

# Quick Start

## Run

Single-model image:
```bash
docker run --gpus all -p 8080:8080 sinanozel/llama.cuda.6gb:gemma4-e2b
```

Bundle image (multiple models in one image — pick one at runtime):
```bash
docker run --gpus all -p 8080:8080 \
  -e GGUF_FILENAME=gemma-4-e2b-it-Q8_0.gguf \
  -e MODEL_NAME=gemma4 -e MODEL_TAG=e2b \
  sinanozel/llama.cuda.6gb:26.04
```

## Test
```bash
curl -s http://localhost:8080/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "gemma4:e2b",
    "messages": [{"role": "user", "content": "What is the capital of France?"}],
    "max_tokens": 50
  }'
```

## With LiteLLM
```python
import litellm

response = litellm.completion(
    model="openai/gemma4:e2b",
    api_base="http://localhost:8080/v1",
    messages=[{"role": "user", "content": "What is the capital of France?"}]
)
```

## Docker Compose with Open WebUI
```yaml
services:
  llama:
    image: sinanozel/llama.cuda.6gb:gemma4-e2b
    ports:
      - "8080:8080"
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              capabilities: ["gpu"]
              count: all

  webui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3000:3000"
    environment:
      - OPENAI_API_BASE_URL=http://llama:8080/v1
      - OPENAI_API_KEY=none
    depends_on:
      - llama
```

# More Information

All containers are created through an automated pipeline that verifies the model is present and responding before publishing, so there is a reasonable level of testing for a free project.

Host machine requirements: 🐳 `docker`, `nvidia-container-runtime`, CUDA 12+, NVidia GPU and driver. (All installable through `apt` on Ubuntu.) See the repo https://github.com/sinan-ozel/model-servers/ for more details.

Please note: while this repo and its pipeline are my own work (MIT licensed), the models each have their own license. The model license as of the time of containerization is stored in the container labels.
