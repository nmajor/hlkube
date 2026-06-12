# Marketmap

Marketmap is a CNPG-backed data workspace for permit scraping and geospatial analysis.

## PostgreSQL

- Cluster: `marketmap-db`
- Namespace: `marketmap`
- Database: `marketmap`
- Owner: `marketmap`
- Service: `marketmap-db-rw.marketmap.svc.cluster.local:5432`
- Credential secret: `marketmap-postgres-credentials`
- Storage: `50Gi` on `longhorn-single-replica`
- Extensions: `timescaledb`, `vector`, `postgis`, `pg_trgm`

## MinIO

- Service: `minio.marketmap.svc.cluster.local:9000`
- Console: `minio.marketmap.svc.cluster.local:9001`
- Bucket: `marketmap`
- Credential secret: `minio-credentials`
- Storage: `100Gi` on `longhorn-single-replica`

## Secret Setup

Fill in the local secret templates before deployment:

- `postgres-credentials.secret`
- `minio-credentials.secret`

Then run:

```bash
./seal-secrets.sh
```

Commit only the generated `*.sealed.yaml` files, not the local `*.secret` files.
