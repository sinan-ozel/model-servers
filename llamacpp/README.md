# llama.cpp Model Server

This directory contains the Dockerfile and resources for building llama.cpp-based model servers with pre-loaded GGUF models.

## Configuration

Models are configured in YAML files in the `model_metadata/` directory. Each model must have the following GGUF fields:

```yaml
name: gemma3
tag: 270m
memory:
  model_size: 292MiB
  min: 1GiB
  recommended: 1GiB
license: Gemma Terms of Use
max_context_window: 32k
gguf:
  url: https://huggingface.co/ggml-org/gemma-3-270m-GGUF/resolve/main/gemma-3-270m-Q8_0.gguf
  filename: gemma-3-270m-Q8_0.gguf
```

To enable audio transcription (whisper), add an optional `gguf.whisper` section:

```yaml
gguf:
  url: ...
  filename: ...
  whisper:
    url: https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small.bin
    filename: ggml-small.bin
    file_size: 488MiB
```

When configured, `whisper-server` (whisper.cpp v1.8.1) starts automatically on port 8081 alongside the main server.

## Quick Start

### 1. Download a GGUF Model

Run the VS Code task: `download_gguf_model` and select a model file.

Or manually:
```bash
./scripts/download_gguf_model.sh model_metadata/gemma3_270m.yaml
```

### 2. Build the Container

Run the VS Code task: `build_llamacpp_model_server`

Or manually:
```bash
./scripts/build_llamacpp_model_server.sh model_metadata/gemma3_270m.yaml
```

### 3. Test the Container

Run the VS Code task: `test_llamacpp_model_server`

Or manually:
```bash
./scripts/test_llamacpp_model_server.sh model_metadata/gemma3_270m.yaml
```

### 4. Push to Docker Hub

Run the VS Code task: `push_llamacpp_model_server_to_dockerhub`

Or manually:
```bash
export DOCKERHUB_NAMESPACE=yourusername
./scripts/push_llamacpp_model_server_to_dockerhub.sh model_metadata/gemma3_270m.yaml
```

## Full Pipeline

Run the VS Code task: `llamacpp_full_pipeline` to execute all steps in sequence.

## Model Cache

Downloaded GGUF models are stored in `llamacpp/model-cache/` and are excluded from git.

## API Endpoints

Once running, the server exposes:

- **Completion**: `POST http://localhost:8080/completion`
  ```json
  {
    "prompt": "What is the capital of France?",
    "n_predict": 50,
    "temperature": 0.7
  }
  ```

- **Chat (OpenAI-compatible)**: `POST http://localhost:8080/v1/chat/completions`

- **Health**: `GET http://localhost:8080/health`

- **Audio transcription** *(whisper models only)*: `POST http://localhost:8081/inference`
  ```bash
  curl http://localhost:8081/inference \
    -F "file=@audio.mp3" \
    -F "temperature=0" \
    -F "response_format=json"
  ```

For full llama-server API documentation, see: https://github.com/ggerganov/llama.cpp/blob/master/tools/server/README.md

## Requirements

- Docker with GPU support (nvidia-container-toolkit)
- NVIDIA GPU with CUDA 12.8 (compute capability 8.0+)
- Sufficient disk space for models (varies per model)
- `yq` (for YAML parsing in build/test scripts)

## Dockerfile Details

The Dockerfile uses a two-stage build:

1. **Builder stage** (`nvidia/cuda:12.8.0-devel-ubuntu22.04`): compiles whisper.cpp v1.8.1 from source with CUDA support (`-DGGML_CUDA=1`), producing the `whisper-server` binary.
2. **Final stage** (`ghcr.io/ggml-org/llama.cpp:server-cuda`, CUDA 12.8): the prebuilt `llama-server` binary with the `whisper-server` binary copied in. The GGUF model is embedded at build time.

Ports:
- `8080` — llama-server (LLM inference)
- `8081` — whisper-server (audio transcription, only started when a whisper model is configured)
