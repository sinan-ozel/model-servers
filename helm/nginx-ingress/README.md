# Nginx Ingress Controller Helm Chart

This chart installs the nginx ingress controller using the official ingress-nginx Helm chart as a dependency.

## Installation

```bash
# Update dependencies first
helm dependency update ./helm-nginx-ingress

# Install nginx ingress controller
helm install nginx-ingress ./helm-nginx-ingress --create-namespace --namespace ingress-nginx
```

## Getting the Load Balancer Hostname

After installation, get the external hostname:

```bash
kubectl get svc -n ingress-nginx nginx-ingress-ingress-nginx-controller -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

## Usage

This creates the ingress controller that other applications can use with `ingressClassName: nginx` in their ingress resources.