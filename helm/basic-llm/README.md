# Basic Deployment Helm Chart

This Helm chart deploys a basic application with configurable image and parameters.

## Installation

### Install with default values
```bash
helm install my-basic-deployment ./basic-deployment-helm
```

### Install with custom image
```bash
helm install my-basic-deployment ./basic-deployment-helm \
  --set image.repository=nginx \
  --set image.tag=latest
```

### Install with custom values file
```bash
helm install my-basic-deployment ./basic-deployment-helm -f custom-values.yaml
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `replicaCount` | Number of replicas | `1` |
| `image.repository` | Container image repository | `hashicorp/http-echo` |
| `image.tag` | Container image tag | `0.2.3` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `service.type` | Kubernetes service type | `ClusterIP` |
| `service.port` | Service port | `80` |
| `service.targetPort` | Target port on container | `5678` |
| `ingress.enabled` | Enable ingress | `true` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.hosts` | Ingress hosts configuration | `chart-example.local` |
| `app.name` | Application name | `hello-world` |
| `app.text` | Text to display | `"hello world"` |
| `app.port` | Application port | `5678` |

## Examples

### Using different image
```yaml
# custom-values.yaml
image:
  repository: nginx
  tag: "1.21"
  pullPolicy: Always

app:
  text: "Welcome to Nginx"
  port: 80

service:
  targetPort: 80
```

### Disabling ingress
```yaml
ingress:
  enabled: false
```

### Multiple replicas
```yaml
replicaCount: 3
```

## Uninstall
```bash
helm uninstall my-basic-deployment
```