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

### External — Cloudflare Workers (Hyperdrive over Tunnel)

The cloudflared tunnel exposes a public hostname that TCP-proxies to the pooler:

- Public hostname: `landscout-db.nmajor.net`
- Tunnel route (in `infrastructure/cloudflared/configmap.yaml`):
  `tcp://landscout-db-rw.landscout.svc.cluster.local:5432`

The tunnel points at the primary (`-rw`) service directly, **not** the PgBouncer
pooler — Hyperdrive is itself a connection pooler and must not sit behind a
transaction-mode PgBouncer (it breaks Hyperdrive's prepared statements).

Access to that hostname is locked down with a Cloudflare Access application +
service token so that **only Hyperdrive** can use it. Workers never talk to the
database directly — they use a Hyperdrive binding.

## Cloudflare-side setup (one-time, done outside this repo)

1. **DNS route** — point the public hostname at the tunnel:
   ```bash
   cloudflared tunnel route dns hlkube-tunnel landscout-db.nmajor.net
   ```
2. **Access application + service token** — in the Zero Trust dashboard, create a
   Self-hosted / Access application for `landscout-db.nmajor.net` with a policy of
   type *Service Auth* that requires a valid service token. Note the
   `Client ID` and `Client Secret`.
3. **Create the Hyperdrive config** (Wrangler v3.65+). Omit `--port`; the tunnel
   handles routing:
   ```bash
   npx wrangler hyperdrive create landscout \
     --host=landscout-db.nmajor.net \
     --database=landscout \
     --user=landscout \
     --password='<password>' \
     --access-client-id='<CLIENT_ID>' \
     --access-client-secret='<CLIENT_SECRET>'
   ```
4. **Bind it in `wrangler.toml`:**
   ```toml
   [[hyperdrive]]
   binding = "HYPERDRIVE"
   id = "<hyperdrive-config-id>"
   ```
   At runtime the Worker reads `env.HYPERDRIVE.connectionString`.

TimescaleDB/CNPG serves TLS by default, which Hyperdrive requires.

## Local development (without deploying a Worker)

Use the `cloudflared access` client to open a local TCP tunnel, then connect
with any Postgres client:

```bash
cloudflared access tcp --hostname landscout-db.nmajor.net --url 127.0.0.1:5432 \
  --service-token-id '<CLIENT_ID>' --service-token-secret '<CLIENT_SECRET>'
# then, in another shell:
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
