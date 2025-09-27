[![Docker Pulls 0.12.2](https://img.shields.io/docker/pulls/sinanozel/ollama.0.12.2)](https://hub.docker.com/r/sinanozel/ollama.0.12.2)

# Ollama Model Server Automation

This repository streamlines the building and publishing of Docker images for Ollama model servers with preloaded models, unlocking a suite of powerful benefits:

✨ Version Control: Your models are frozen in time—no more automatic updates from Hugging Face.

✨ Independence: Say goodbye to relying on external Hugging Face servers.

✨ Lightning-Fast Startup: Perfect for heavy workloads where every second counts.

To boost performance even further, the container can be kept alive continuously. There is an example below in this README.md file.
Additionally, a simple GPU VRAM monitoring script is included, logging usage to a file for easy tracking. For larger organizations, there’s also a ready-made pipeline to upload images to your own AWS repository.

This project is MIT licensed, giving you freedom to use it commercially. Feel free to clone, enhance, or tweak to your heart’s content. If you want, you can also reach out for explicit permission.

## Quick Start

Requirements: docker

### Standalone Ollama Server

```yaml
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama.0.12.2:gemma3-4b
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

To test:
```bash
curl http://localhost:11434/api/generate -d '{"model": "gemma3:4b", "prompt": "Is the cake real?"}'
```


## Advanced - Creating Your Own Image

Requirements: docker, git, VS Code.

Clone the repo and run the "full pipeline" or any one of the tasks that go into the full pipeline.
You can actually do this without VSCode, just read the file `.vscode/tasks.json` and
run the same scripts manually.


---

## 📁 Folder Structure

- `model_metadata/` — YAML files describing each model's name, tag, memory, license, etc.
- `.github/workflows/` — GitHub Actions workflow for build/test/push.
- `scripts/` — Shell and PowerShell scripts for building/testing/pushing.
- `ollama/` — Dockerfile and Ollama server setup.

---

## 🧠 Model Metadata Example

If you want to clone the repo and add another file.

Save this in `model_metadata/devstral_24b.yaml`:

```yaml
name: devstral
tag: 24b
memory:
  model_size: 25GiB
  min: 32GiB
  recommended: 56GiB
license: Apache License Version 2.0, January 2004
max_context_window: 128k

```

Then add to `.vscode/tasks.json`

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

To test:
```bash
curl http://localhost:11434/api/embed -d '{"model": "all-minilm:33m", "input": "The cake is a lie."}'
```


### Standalone Ollama Server

```yaml
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama.0.12.2:gemma3-4b
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

To test:
```bash
curl http://localhost:11434/api/generate -d '{"model": "gemma3:4b", "prompt": "Is the cake real?"}'
```


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
            -d '{"model": "gemma3:4b", "prompt": "ping", "options": {"use_mmap": false}, "stream": false}' \
            > /dev/null;
          sleep 300;
        done
```

The `keep-in-memory` pod makes triggers the model every five minutes to make sure that it is always
in memory.

### For GPU Monitoring

The server writes GPU use regularly to a file. If this is contained as a mount point, other
containers or pods will be able to access this information.

I am planning to have another method for Prometheus, or at least make this a bit more robust
by changing it into a service and adding timestamps.

```yaml
version: '3.8'
services:
  ollama:
    image: sinanozel/ollama.0.12.2:gemma3-4b
    ports:
      - "11434:11434"
    deploy:
      resources:
        reservations:
          devices:
          - driver: nvidia
            capabilities: ["gpu"]
            count: all
    volumes:
      - './ollama_gpu_metrics:/metrics'

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
