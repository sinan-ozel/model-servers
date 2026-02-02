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

- **Health**: `GET http://localhost:8080/health`

For full API documentation, see: https://github.com/ggerganov/llama.cpp/blob/master/examples/server/README.md

## Requirements

- Docker with GPU support (nvidia-container-toolkit)
- NVIDIA GPU with CUDA support
- Sufficient disk space for models (4-40GB per model)
- yq (for YAML parsing)

## Dockerfile Details

The Dockerfile:
1. Uses CUDA 12.8.0 base image with cuDNN
2. Clones and builds llama.cpp from source with CMake and CUDA support (`-DGGML_CUDA=ON`)
3. Embeds the GGUF model in the image
4. Exposes port 8080
5. Runs llama-server with optimal GPU settings (-ngl 999 offloads all layers to GPU)
