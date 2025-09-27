[![Docker Pulls 0.6.6](https://img.shields.io/docker/pulls/sinanozel/ollama-server)](https://hub.docker.com/r/sinanozel/ollama-server)
[![Docker Pulls 0.12.2](https://img.shields.io/docker/pulls/sinanozel/ollama.0.12.2)](https://hub.docker.com/r/sinanozel/ollama.0.12.2)

# Ollama Model Server Automation

This repository automates building and publishing Docker images for Ollama model servers with preloaded models.

You can choose one of three ways to use it:

1. **GitHub Actions** — (No Longer used) ~Quick and easy; suitable for small models and embedding models (limited by GitHub runner storage).~
2. **VS Code Tasks** — Convenient from your IDE; more flexible.
3. **Manual Script Execution** — Full control, ideal for large models.

Built images are pushed to **Docker Hub** and **AWS Elastic Container Registry (ECR)**.

---

## 📁 Folder Structure

- `model_metadata/` — YAML files describing each model's name, tag, memory, license, etc.
- `.github/workflows/` — GitHub Actions workflow for build/test/push.
- `scripts/` — Shell and PowerShell scripts for building/testing/pushing.
- `ollama/` — Dockerfile and Ollama server setup.

---

## 🧠 Model Metadata Example

Save this in `model_metadata/gemma-7b.yaml`:

```yaml
name: gemma-7b
tag: latest
memory:
  model_size: 7GiB
  min: 8GiB
  recommended: 12GiB
license: apache-2.0
```

---

## 🚀 Options for Running the Pipeline

### 🔹 1. GitHub Actions (Manual Dispatch)

IMPORTANT: I have not kept this up-to-date and did not test. Will likely require some fixes if used.

This is the easiest method for small or embedding models.

1. Go to **Actions** tab in GitHub.
2. Select `Build, Push and Test Ollama Model Image`.
3. Click **Run workflow**, and choose the `model_file`, e.g. `gemma2_2b.yaml`.

This will:

- Build and preload the model image.
- Test for model presence.
- Push to Docker Hub and AWS ECR.

---

### 🔹 2. VS Code Tasks (Large Models)

Use this if you want to avoid GitHub storage limits.

Open the command palette (`Ctrl+Shift+P`) → **Run Task** → choose one of:

- `build_ollama_single_model_server`
- `inspect_ollama_single_model_server`
- `push_ollama_single_model_server_to_aws`
- `push_ollama_single_model_server_to_dockerhub`
- `full_pipeline` (runs all the above in order)

Make sure to configure your VS Code `settings.json`:

```json
{
  "aws.region": "ca-central-1",
  "docker.hub.namespace": "your-dockerhub-username"
}
```

---

### 🔹 3. Manual Shell Script Execution

You can also run any of the scripts directly:

```bash
./scripts/build_ollama_single_model_server.sh model_metadata/gemma-7b.yaml
./scripts/inspect_ollama_single_model_server.sh model_metadata/gemma-7b.yaml
./scripts/push_ollama_single_model_server_to_aws.sh model_metadata/gemma-7b.yaml
./scripts/push_ollama_single_model_server_to_dockerhub.sh model_metadata/gemma-7b.yaml
```

---

## 🧪 Run the Image

### Standalone Ollama Embedding Server

```yaml
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama.0.12.2:all-minilm-33m
    ports:
      - "11434:11434"
```

```bash
curl http://localhost:11434/api/embed -d '{"model": "all-minilm:33m", "input": "The cake is a lie."}'
```


### Standalone Ollama Server

```yaml
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama.0.12.2:gemma2-2b
    ports:
      - "11434:11434"
    deploy:
      resources:
        reservations:
          devices:
          - driver: nvidia
            capabilities: ["gpu"]
            count: all
```

```bash
curl http://localhost:11434/api/generate -d '{"model": "all-minilm:33m", "prompt": "Is the cake real?"}'
```



---

### With Open Web UI

```yaml
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama-server:gemma2-2b
    ports:
      - "11434:11434"
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
      - OLLAMA_API_BASE_URL=http://ollama:11434
    depends_on:
      - ollama

  keep-in-memory:
    image: curlimages/curl:latest
    depends_on:
      - ollama
    entrypoint: [ "sh", "-c" ]
    command:
      - |
        echo "[keep-alive] Started...";
        while true; do
          curl -s -X POST http://ollama:11434/api/generate \
            -H "Content-Type: application/json" \
            -d '{"model": "gemma2:2b", "prompt": "ping", "options": {"use_mmap": false}, "stream": false}' \
            > /dev/null;
          sleep 300;
        done
```

The `keep-in-memory` pod makes triggers the model every five minutes to make sure that it is always
in memory.

### To have GPU monitoring

The server writes GPU use regularly to a file. If this is contained as a mount point, other
containers or pods will be able to access this information.

I am planning to have another method for Prometheus later on.

```
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama-server:gemma2-2b
    ports:
      - "11434:11434"
    volumes:
      - ollama_metrics:/metrics  # <-- volume mount for GPU metrics output

volumes:
  ollama_metrics:

```

Inside the folder, you will see a file called `gpu.json`. This file is updated every 2 minutes.

---

## 🛠️ Requirements

- [`yq`](https://github.com/mikefarah/yq) — used for parsing YAML in GitHub workflows
- Docker
- AWS CLI (for ECR pushing)
- GitHub Secrets (for GitHub Actions):

  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `DOCKER_USERNAME`
  - `DOCKER_TOKEN`

---

## 🪪 License

MIT
