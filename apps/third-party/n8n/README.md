# n8n with Separate Valkey Installation

This directory contains the n8n deployment configuration with a separate Valkey (Redis-compatible) instance for improved performance and security.

## Architecture

- **n8n**: Workflow automation platform with main, worker, and webhook components
- **Valkey**: Separate Redis-compatible instance for queue management and caching
- **PostgreSQL**: Database using CloudNativePG operator (separate cluster)

## Components

### n8n Release (`release.yaml`)

- Main n8n application with queue mode enabled
- Worker processes for distributed job processing
- Webhook processes for external integrations
- Uses separate Valkey instance for Redis operations

### Valkey Release (`valkey-release.yaml`)

- Standalone Valkey instance with authentication
- Persistent storage using Longhorn
- Metrics enabled for monitoring
- Dedicated for n8n queue operations

### Sealed Secrets

#### Valkey Authentication (`valkey-auth.secret` → `valkey-auth.sealed.yaml`)

Contains the password for Valkey authentication.

**To update the Valkey password:**

1. Edit `valkey-auth.secret` with new password
2. Run the sealing script: `../../seal-secrets.sh`
3. Commit only the `.sealed.yaml` file

#### n8n Secrets (`n8n-secrets.sealed.yaml`, `postgres-credentials.sealed.yaml`)

- `n8n-secrets`: Contains n8n encryption key
- `postgres-credentials`: Database connection password

## Configuration

### Environment Variables

The n8n configuration uses these key environment variables for Valkey connection:

- `N8N_EXECUTIONS_MODE: "queue"` - Enables queue mode
- `QUEUE_BULL_REDIS_HOST: "n8n-valkey-primary"` - Valkey service name
- `QUEUE_BULL_REDIS_PORT: "6379"` - Valkey port
- `QUEUE_BULL_REDIS_DB: "0"` - Database number

### Service Names

- Valkey: `n8n-valkey-primary.n8n.svc.cluster.local`
- PostgreSQL: `n8n-postgres-pooler.n8n.svc.cluster.local`

## Deployment

The resources are deployed via Flux CD. Any changes to the configuration files will be automatically applied to the cluster.

### Prerequisites

- Flux CD configured
- Bitnami Helm repository added to sources
- Longhorn storage class available
- CloudNativePG operator installed

### Monitoring

- Valkey metrics are enabled and can be scraped by Prometheus
- n8n provides built-in metrics endpoints
- PostgreSQL metrics via CloudNativePG ServiceMonitor

## Troubleshooting

### Common Issues

1. **Webhook Redis Connection Error**

   - Ensure `QUEUE_BULL_REDIS_HOST` environment variables are set
   - Check Valkey service is running: `kubectl get pods -n n8n`
   - Verify service name: `kubectl get svc -n n8n`

2. **Database Connection Issues**

   - Check PostgreSQL pooler status: `kubectl get pooler -n n8n`
   - Verify credentials in sealed secret

3. **Authentication Issues**
   - Ensure sealed secrets are properly created
   - Check secret exists: `kubectl get secrets -n n8n`

### Logs

```bash
# n8n main pods
kubectl logs -n n8n -l app.kubernetes.io/name=n8n,app.kubernetes.io/type=master

# n8n worker pods
kubectl logs -n n8n -l app.kubernetes.io/name=n8n,app.kubernetes.io/type=worker

# n8n webhook pods
kubectl logs -n n8n -l app.kubernetes.io/name=n8n,app.kubernetes.io/type=webhook

# Valkey pods
kubectl logs -n n8n -l app.kubernetes.io/name=valkey
```

## Security Notes

- Valkey is configured with authentication enabled
- All passwords are stored as sealed secrets
- Network policies can be enabled for additional security
- Services are only accessible within the cluster by default
