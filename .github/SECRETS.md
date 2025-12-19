# GitHub Secrets and Variables Configuration

This document outlines the required secrets and variables needed to run the `Deploy Model to Kubernetes` GitHub workflow.

## Required Repository Secrets

### `GITHUB_TOKEN`
- **Description**: GitHub token for authenticating with GitHub CLI and downloading artifacts
- **Type**: Repository Secret
- **Value**: This is automatically provided by GitHub Actions - no manual setup required
- **Usage**: Used to authenticate with GitHub CLI and download kubeconfig artifacts from the IAC repository

## Required Repository Variables

### `IAC_REPO`
- **Description**: Repository containing the Infrastructure as Code and kubeconfig artifacts
- **Type**: Repository Variable
- **Value**: Repository name in format `owner/repo-name` (e.g., `myorg/infrastructure-repo`)
- **Usage**: Specifies which repository to download kubeconfig artifacts from

### `AWS_REGION` (Optional)
- **Description**: AWS region for operations
- **Type**: Repository Variable
- **Default**: `us-east-1`
- **Value**: AWS region code (e.g., `us-west-2`, `eu-west-1`)
- **Usage**: Used for AWS-specific operations when provider is `aws`

### `DOCKERHUB_NAMESPACE` (Optional)
- **Description**: Docker Hub namespace for container images
- **Type**: Repository Variable
- **Value**: Your Docker Hub username or organization name
- **Usage**: Used when referencing Docker Hub images in the deployment

## Setup Instructions

### 1. Repository Secrets
Navigate to your repository → Settings → Secrets and variables → Actions → Secrets:

1. **GITHUB_TOKEN**: This is automatically available - no action needed

### 2. Repository Variables
Navigate to your repository → Settings → Secrets and variables → Actions → Variables:

1. **IAC_REPO**:
   - Click "New repository variable"
   - Name: `IAC_REPO`
   - Value: `your-org/your-iac-repo`

2. **AWS_REGION** (optional):
   - Click "New repository variable"
   - Name: `AWS_REGION`
   - Value: `us-west-2` (or your preferred region)

3. **DOCKERHUB_NAMESPACE** (optional):
   - Click "New repository variable"
   - Name: `DOCKERHUB_NAMESPACE`
   - Value: `your-dockerhub-username`

## Kubeconfig Artifact Requirements

The workflow expects the IAC repository to have GitHub Actions that publish artifacts with the following structure:

- **Artifact Name Pattern**: `pulumi-{provider}-model-server`
  - Where `{provider}` is either `aws` or `exoscale`
- **Artifact Content**: A JSON file named `model-server.json` containing:
  ```json
  {
    "kubeconfig": "<base64-encoded-kubeconfig-content>"
  }
  ```

The kubeconfig should have permissions to:
- Create and manage pods, services, and ingresses
- Install Helm charts
- Access the `kube-system` namespace (for GPU device plugin)
- Access the `ingress-nginx` namespace

## Permissions Required

The kubeconfig should have sufficient permissions for:

### Kubernetes Resources
- **Pods**: create, get, list, watch, delete
- **Services**: create, get, list, watch, delete
- **Ingresses**: create, get, list, watch, delete
- **DaemonSets**: create, get, list (for GPU device plugin)
- **Namespaces**: create, get, list

### Helm Operations
- Install and uninstall Helm charts
- Create namespaces for Helm releases

### GPU Support
- Deploy NVIDIA GPU device plugin
- Access nodes with GPU taints

## Troubleshooting

### Common Issues

1. **"kubeconfig not found"**
   - Verify `IAC_REPO` variable points to the correct repository
   - Ensure the artifact `pulumi-{provider}-model-server` exists
   - Check that the artifact contains `model-server.json` with valid kubeconfig

2. **"Permission denied" errors**
   - Verify kubeconfig has sufficient RBAC permissions
   - Check if the service account has cluster-admin or appropriate roles

3. **"LoadBalancer not found"**
   - Ensure your Kubernetes cluster supports LoadBalancer services
   - Verify nginx-ingress is properly configured
   - Check cloud provider LoadBalancer integration

4. **"GPU node not found"**
   - Verify your cluster has GPU-enabled nodes
   - Check that nodes have the `nvidia.com/gpu=true` taint
   - Ensure NVIDIA device plugin is installed

## Security Notes

- Store all sensitive information in GitHub Secrets, not Variables
- Repository Variables are visible in the repository, so only use them for non-sensitive configuration
- Regularly rotate kubeconfig credentials
- Limit kubeconfig permissions to minimum required scope
- Consider using OIDC/Workload Identity for better security instead of long-lived kubeconfig files