# Ollama Model Server Automation

This repository automates the process of building and publishing Docker images
for Ollama model servers with preloaded models.
Images are published both to AWS Elastic Container Registry (ECR) and Docker Hub.

## Folder Structure

* `model_metadata/` — YAML files describing each model's metadata.
* `.github/workflows/build-push-test.yaml` — GitHub Actions workflow to build, test, and push model images.
* `ollama/` — Dockerfile and server setup.

## Model Metadata Example

Each model YAML should look like this:

```yaml
name: gemma-7b
tag: latest
memory: 8GiB
```

Save this as `model_metadata/gemma-7b.yaml`.

## Triggering a Build

Trigger the GitHub workflow manually and specify the metadata file:

```yaml
model_file: gemma-7b.yaml
```

This will:

* Build a Docker image with the specified model preloaded.
* Tag and push it to Docker Hub and AWS ECR.
* Run a test to confirm the model was preloaded (i.e., model file exists inside container).

## Running the Image with Open Web UI

Here are example `docker-compose.yml` configurations:

### Example 1: Standalone Ollama Server

```yaml
version: '3.8'
services:
  ollama:
    image: your-docker-username/ollama-server-gemma-7b:latest
    ports:
      - "11434:11434"
```

### Example 2: With Open Web UI

```yaml
version: '3.8'
services:
  ollama:
    image: your-docker-username/ollama-server-gemma-7b:latest
    ports:
      - "11434:11434"

  webui:
    image: ghcr.io/open-webui/open-webui:main
    ports:
      - "3000:3000"
    environment:
      - OLLAMA_API_BASE_URL=http://ollama:11434
    depends_on:
      - ollama
```

## Requirements

* `yq` (used in the GitHub workflow to read YAML model metadata)
* GitHub Secrets:

  * `AWS_ACCESS_KEY_ID`
  * `AWS_SECRET_ACCESS_KEY`
  * `DOCKER_USERNAME`
  * `DOCKER_TOKEN`

## License

MIT
