# PostgreSQL Sample Cluster

This directory contains the configuration for a sample PostgreSQL cluster managed by CloudNativePG, including connection poolers for improved scalability and connection management.

## Components

- **PostgreSQL Cluster**: A 3-instance PostgreSQL cluster with optimized configuration
- **Read-Write Pooler**: PgBouncer connection pooler for read-write access to the primary
- **Read-Only Pooler**: PgBouncer connection pooler for read-only access to replicas

## Connection Poolers

Two connection poolers are configured to improve database performance:

1. **postgres-sample-pooler** - For read-write operations (connects to primary)

   - Service: `postgres-sample-pooler-rw`
   - 2 replicas for high availability
   - Maximum 100 client connections per instance
   - Maximum 20 connections per database

2. **postgres-sample-pooler-ro** - For read-only operations (connects to replicas)
   - Service: `postgres-sample-pooler-ro`
   - 2 replicas for high availability
   - Maximum 150 client connections per instance
   - Maximum 30 connections per database

## Connecting to the Database

### Application Configuration

For applications that need to connect to the database:

```yaml
# Example for read-write access through the pooler
DB_HOST: postgres-sample-pooler-rw.postgres-sample.svc.cluster.local
DB_PORT: 5432
DB_USER: app
DB_NAME: app_database

# Example for read-only access through the pooler
DB_HOST_RO: postgres-sample-pooler-ro.postgres-sample.svc.cluster.local
DB_PORT_RO: 5432
DB_USER_RO: app_ro
DB_NAME_RO: app_database
```

### Benefits of Connection Pooling

- **Reduced Resource Usage**: Maintains a pool of connections to PostgreSQL, reducing the overhead of establishing new connections
- **Connection Limiting**: Prevents database overload by limiting the number of connections
- **High Availability**: Multiple pooler instances ensure connection availability
- **Load Distribution**: Read-only queries can be distributed across replicas

## Monitoring

All poolers have PodMonitors enabled for Prometheus integration. Key metrics to monitor:

- Number of active connections
- Connection pooler latency
- Connection errors

Access these metrics through Grafana at: https://grafana.nmajor.net
