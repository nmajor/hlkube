# Docker Registry

This is a private Docker registry deployed within the Kubernetes cluster, primarily for use with GitHub Actions self-hosted runners.

## Key Details

- **Registry URL (internal)**: `registry.docker-registry.svc.cluster.local:5000`
- **Registry URL (via ingress)**: `registry.hlkube.local` (cluster-local access only)
- **Authentication**: Basic auth with htpasswd (credentials in sealed secret)
- **Storage**: 50GB Longhorn volume
- **Maintenance**: Weekly garbage collection via CronJob

## Features

- Automatic image garbage collection
- Compression via Traefik middleware
- Persistent storage with Longhorn
- Authentication to prevent unauthorized access

## Usage with GitHub Actions

To use this registry in your GitHub workflows:

```yaml
jobs:
  build:
    runs-on: [self-hosted, kubernetes]
    steps:
      - uses: actions/checkout@v3

      # Log in to the private registry (internal access)
      - name: Log in to private registry
        run: |
          echo "${{ secrets.REGISTRY_PASSWORD }}" | docker login registry.hlkube.local -u reguser --password-stdin

      # Build and tag the image
      - name: Build and push
        run: |
          docker build -t registry.hlkube.local/myapp:${{ github.sha }} .
          docker push registry.hlkube.local/myapp:${{ github.sha }}
```

## Benefits

1. **Performance**: Fast image pushing/pulling as everything stays within the cluster
2. **Security**: Images remain within your infrastructure
3. **Simplicity**: No need for external access or TLS certificates

## Using Images in Kubernetes

To deploy images from this registry in your cluster:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      containers:
        - name: app
          image: registry.hlkube.local/myapp:latest
      # No imagePullSecrets needed as it's in-cluster
```

## Maintenance

The registry has automatic garbage collection configured:

- A weekly CronJob runs to clean up unreferenced layers and manifests
- Temporary uploads are automatically purged after 7 days
- All maintenance operations are logged for review

If you need to manually trigger garbage collection, you can run:

```bash
kubectl -n docker-registry create job --from=cronjob/registry-cleanup manual-cleanup
```
