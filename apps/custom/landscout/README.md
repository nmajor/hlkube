# Landscout

Landscout is a CNPG-backed PostgreSQL database for the Landscout project. It is
reachable from Cloudflare Workers via **Cloudflare Hyperdrive over the existing
Cloudflare Tunnel** (no raw public exposure of the database).

## PostgreSQL

- Cluster: `landscout-db`
- Namespace: `landscout`
- Database: `landscout`
- Owner: `landscout`
- Image: `ghcr.io/nmajor/cnpg-timescaledb:17.5` (PostgreSQL 17 + TimescaleDB)
- Instances: 3 (HA)
- Storage: `50Gi` per instance on `longhorn-single-replica`
- Extensions: `timescaledb`, `vector`, `postgis`, `pg_trgm`
- Credential secret: `landscout-postgres-credentials` (`kubernetes.io/basic-auth`)

### Services

- Read/write (primary): `landscout-db-rw.landscout.svc.cluster.local:5432`
- Read-only (replicas): `landscout-db-ro.landscout.svc.cluster.local:5432`
- Pooler (PgBouncer, rw): `landscout-db-pooler.landscout.svc.cluster.local:5432`

## Connection Details

### Internal (from within the cluster)

```
postgresql://landscout:<password>@landscout-db-pooler.landscout.svc.cluster.local:5432/landscout
```

### External — Cloudflare Workers (Hyperdrive via Workers VPC)

Workers reach this database through the shared Workers VPC connector documented in
[`infrastructure/cloudflared-vpc`](../../../infrastructure/cloudflared-vpc). There
is **no public hostname and no DNS record** — the connector provides private egress
into the cluster and Hyperdrive routes to the primary (`-rw`) service.

We target `landscout-db-rw` (the primary), **not** the PgBouncer pooler — Hyperdrive
is itself a connection pooler and must not sit behind a transaction-mode PgBouncer.

## Cloudflare-side setup (one-time, done outside this repo)

Prerequisite: the shared `cloudflared-vpc` connector is deployed (see its README)
and you have its **VPC Tunnel ID**.

```bash
# 1. VPC Service -> the DB's primary service (resolved via in-cluster DNS).
npx wrangler vpc service create landscout \
  --type tcp --tcp-port 5432 --app-protocol postgresql \
  --tunnel-id <HLKUBE_VPC_TUNNEL_ID> \
  --hostname landscout-db-rw.landscout.svc.cluster.local
# -> note the VPC Service ID

# 2. Hyperdrive config. CNPG serves a self-signed cert, so relax verification
#    (traffic is still TLS-encrypted end to end).
npx wrangler hyperdrive create landscout \
  --service-id <VPC_SERVICE_ID> \
  --database landscout --user landscout --password '<password>' \
  --scheme postgresql --cert-verification-mode disabled

# 3. Bind it in the Worker's wrangler.toml:
#    [[hyperdrive]]
#    binding = "HYPERDRIVE"
#    id = "<hyperdrive-config-id>"
#    -> at runtime: env.HYPERDRIVE.connectionString
```

## Local development (without deploying a Worker)

Workers VPC has no public endpoint, so for local access port-forward the primary
service and connect over localhost:

```bash
kubectl port-forward -n landscout svc/landscout-db-rw 5432:5432
psql 'postgresql://landscout:<password>@127.0.0.1:5432/landscout?sslmode=require'
```

## Secret Setup

The password lives in the gitignored `postgres-credentials.secret`. To rotate it,
edit that file and re-seal:

```bash
./seal-secrets.sh
```

Commit only the generated `postgres-credentials.sealed.yaml`.

## Reusing this pattern for other databases

The Hyperdrive-over-Tunnel path is fully reusable. For each additional database:

1. Add a TCP hostname route to `infrastructure/cloudflared/configmap.yaml`
   (above the wildcard rules), pointing at that DB's pooler/service.
2. Create a DNS route, Access application, and `wrangler hyperdrive create` config
   for the new hostname.

The same tunnel and (optionally) the same service token can serve many databases.
