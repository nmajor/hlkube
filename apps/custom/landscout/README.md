# Landscout

Landscout is a CNPG-backed PostgreSQL database for the Landscout project. It is
reached two ways:

- **From a Cloudflare Worker** (production app) — via **Cloudflare Workers VPC +
  Hyperdrive**. No public exposure of the database.
- **From inside the cluster** (e.g. a script in a Coder workspace) — directly over
  the internal service DNS. No Cloudflare involved.

Both are documented below.

## PostgreSQL

- Cluster: `landscout-db`
- Namespace: `landscout`
- Database: `landscout`
- Owner: `landscout`
- Image: `ghcr.io/nmajor/cnpg-timescaledb:17.5` (PostgreSQL 17 + TimescaleDB)
- Instances: 3 (HA)
- Storage: `100Gi` per instance on `longhorn-single-replica`
- Extensions: `timescaledb`, `vector`, `postgis`, `pg_trgm`
- Credential secret: `landscout-postgres-credentials` (`kubernetes.io/basic-auth`)

### Services

- Read/write (primary): `landscout-db-rw.landscout.svc.cluster.local:5432`
- Read-only (replicas): `landscout-db-ro.landscout.svc.cluster.local:5432`
- Pooler (PgBouncer, rw): `landscout-db-pooler.landscout.svc.cluster.local:5432`

## Connection Details

### In-cluster / Coder workspace (direct — full access)

A script running in a Coder workspace (namespace `coder-workspaces`) or any pod in
the cluster connects **directly** to the database over internal DNS — no Cloudflare,
no Hyperdrive, no VPC. Cross-namespace DNS is open (verified: a `coder-workspaces`
pod reaches `landscout-db-rw` with no NetworkPolicy in the way).

For a build/maintenance script that needs **full access** (DDL, migrations,
extensions, session-level features) connect to the **primary** service — not the
pooler, whose transaction-pooling mode disables session features and prepared
statements:

```bash
# Primary (read-write, full session features) — use this for the workspace agent:
export DATABASE_URL='postgresql://landscout:<password>@landscout-db-rw.landscout.svc.cluster.local:5432/landscout?sslmode=require'
psql "$DATABASE_URL" -c '\dx'   # e.g. list installed extensions
```

Service options:
- `landscout-db-rw.landscout.svc.cluster.local:5432` — primary, read-write (default).
- `landscout-db-ro.landscout.svc.cluster.local:5432` — replicas, read-only.
- `landscout-db-pooler.landscout.svc.cluster.local:5432` — PgBouncer (transaction
  mode); use only for high-connection-count app workloads, not for migrations/DDL.

CNPG serves TLS; `sslmode=require` works. If a client insists on verifying the CA,
fetch it with `kubectl get secret landscout-db-ca -n landscout -o jsonpath='{.data.ca\.crt}' | base64 -d`.

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
