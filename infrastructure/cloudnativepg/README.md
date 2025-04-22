# CloudNativePG

This directory contains the configuration for the CloudNativePG Kubernetes operator, which manages PostgreSQL clusters in a cloud native way.

## Components

- **Operator**: The main CloudNativePG operator deployed via Helm
- **ServiceMonitor**: Configures Prometheus to scrape metrics from the operator
- **Sample Cluster**: A sample PostgreSQL cluster configuration with optimized settings

## Usage

The CloudNativePG operator allows you to create PostgreSQL clusters by defining Cluster resources:

```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: my-app-db
  namespace: my-app
spec:
  instances: 3
  storage:
    size: 10Gi
    storageClass: longhorn
  monitoring:
    enablePodMonitor: true
```

### Connecting to a Database

To connect to a PostgreSQL cluster from your application:

1. Reference the cluster's service: `my-app-db-rw` (read-write) or `my-app-db-r` (read-only)
2. Use the automatically generated secret that contains credentials: `my-app-db-superuser`

### Monitoring

The operator exports metrics to Prometheus with the following features:

- Built-in PodMonitor and ServiceMonitor resources
- PostgreSQL metrics for connections, replication, query performance
- Access metrics through Grafana at: https://grafana.nmajor.net

### Connection Pooling

The sample cluster includes a connection pooler with the following configuration:

- 2 pooler instances for high availability
- 100 max client connections per pooler

### Performance Tuning

The PostgreSQL configuration includes optimized settings for:

- Memory allocation (shared_buffers, work_mem)
- Worker processes for parallelism
- I/O concurrency optimized for SSD storage
- Query planner configuration

## References

- [CloudNativePG Documentation](https://cloudnative-pg.io/documentation/)
- [Operator API Reference](https://cloudnative-pg.io/documentation/current/api_reference/)
- [Prometheus Integration](https://cloudnative-pg.io/documentation/current/monitoring/)
