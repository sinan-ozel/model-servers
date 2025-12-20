# Containerized Deployment

This directory contains the containerized deployment solution for Ollama model servers.

## Overview

The containerized deployment approach packages the deployment script and all its dependencies (kubectl, helm, yq) into a Docker container. This ensures consistent deployment environments and eliminates dependency issues.

## Files

- `Dockerfile` - Container definition with kubectl, helm, and yq
- `../scripts/build_deployment_container.sh` - Builds the deployment container
- `../scripts/run_containerized_deployment.sh` - Runs the containerized deployment

## Usage

### VS Code Task (Recommended)

Use the `deploy_ollama_containerized` task in VS Code:

1. Open VS Code Command Palette (`Ctrl+Shift+P`)
2. Run "Tasks: Run Task"
3. Select `deploy_ollama_containerized`
4. Choose your model file when prompted

This task will automatically:
1. Download the cluster kubeconfig (if needed)
2. Build the deployment container (if needed)
3. Run the containerized deployment

### Manual Usage

```bash
# Build the deployment container
./scripts/build_deployment_container.sh

# Run containerized deployment (requires kubeconfig in .iac/)
./scripts/run_containerized_deployment.sh gemma3_12b.yaml
```

## Dependencies

The containerized deployment automatically handles these dependencies:
- `download_model_cluster_kubeconfig` - Downloads cluster kubeconfig to `.iac/kubeconfig.yaml`
- `build_deployment_container` - Builds the deployment container

## Container Contents

The deployment container includes:
- Ubuntu 24.04 base image
- kubectl (latest stable)
- Helm v3.14.0
- yq (YAML processor)
- jq (JSON processor)
- Deployment script and helm charts
- Model metadata files

## Benefits

1. **Consistent Environment** - Same deployment tools and versions every time
2. **Isolation** - No interference with host system dependencies
3. **Portability** - Can run on any system with Docker
4. **Dependency Management** - All tools bundled in container
5. **VS Code Integration** - Seamless task integration with automatic dependencies