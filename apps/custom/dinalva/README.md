# Dinalva PostgreSQL Database

This project provides a dedicated PostgreSQL database cluster for the Dinalva application.

## Resources

- **Namespace**: `dinalva`
- **Database**: `dinalva`
- **User**: `dinalva`
- **Password**: Stored in `postgres-credentials.secret` (sealed)

## Components

### PostgreSQL Cluster

- **File**: `postgres-cluster.yaml`
- **Type**: CloudNativePG Cluster
- **Instances**: 2 (high availability)
- **Storage**: 5Gi Longhorn single-replica per instance

### Connection Pooler

- **File**: `postgres-pooler.yaml`
- **Type**: PgBouncer via CloudNativePG Pooler
- **Instances**: 2
- **Pool Mode**: Transaction-level
- **Max Connections**: 100 clients, 20 per pool

### External Access

- **File**: `postgres-tcp-ingress.yaml`
- **Type**: Traefik IngressRouteTCP
- **Port**: 5432 (exposed via Traefik)
- **Protocol**: TCP

## Connection Details

### Internal (from within cluster)

```bash
Host: dinalva-postgres-pooler.dinalva.svc.cluster.local
Port: 5432
Database: dinalva
Username: dinalva
Password: <from secret>
```

### External (via Traefik TCP routing)

```bash
Host: <your-domain>
Port: 5432
Database: dinalva
Username: dinalva
Password: <from secret>
```

### Connection URL

```
postgresql://dinalva:<password>@<host>:5432/dinalva
```

## Security Notes

⚠️ **Warning**: This database is exposed to the internet via TCP routing. Consider:

1. Using strong passwords
2. Implementing IP allowlists
3. Enabling PostgreSQL SSL/TLS
4. Using VPN access instead of public exposure
5. Monitoring for unauthorized access

## Monitoring

- Pod monitoring is enabled for both the cluster and pooler
- Metrics are available via Prometheus ServiceMonitors
