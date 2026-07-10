# Cloudflared VPC Connector (Workers VPC)

This is a **shared, reusable connector** that lets Cloudflare Workers reach private
PostgreSQL databases inside this cluster via **Cloudflare Workers VPC + Hyperdrive**.

It is deliberately separate from the website tunnel in
[`infrastructure/cloudflared`](../cloudflared): that tunnel routes HTTP hostnames
to Traefik and its `*.nmajor.net` wildcard would swallow raw Postgres TCP. This
connector carries **no HTTP ingress and no public hostname at all** — routing is
defined entirely on Cloudflare's side by *VPC Services*, so there is nothing here
for the wildcard to conflict with.

## How it works

```
Worker  --binding-->  Hyperdrive  --->  VPC Service (Cloudflare side)
                                          |
                                          v  (this tunnel token)
                                   cloudflared-vpc pod (in cluster)
                                          |
                                          v
                                   <db>-rw.<ns>.svc.cluster.local:5432
```

- **One connector, many databases.** A single Cloudflare Tunnel can back multiple
  VPC Services, and this pod can reach every ClusterIP service in the cluster. So
  adding a new database is **Cloudflare-side only** — no new cluster manifests.
- The connector is **token-based** (remotely managed). The token is the only
  secret; it encodes the tunnel identity. No `config.yaml` / ingress rules.
- Nothing is exposed to the internet: cloudflared makes only outbound connections,
  and each VPC Service is scoped to a single `host:port` reachable only by your
  Hyperdrive configs.

## One-time setup (this connector)

1. **Create the VPC Tunnel** in the Cloudflare dashboard: **Networks → Tunnels →
   Create a tunnel → Cloudflared**, name it e.g. `hlkube-vpc`. (This is a *Workers
   VPC* tunnel; do not add any public hostname to it.) Copy:
   - the **connector token** (the long value after `--token` in the install command)
   - the **Tunnel ID** (shown on the tunnel's page) — you need it for VPC Services.
2. Paste the token into `tunnel-token.secret` (gitignored), then seal it:
   ```bash
   ./seal-secrets.sh
   ```
3. Commit `tunnel-token.sealed.yaml` and make sure `cloudflared-vpc` is listed in
   [`infrastructure/kustomization.yaml`](../kustomization.yaml). Flux deploys the
   connector; confirm it is healthy:
   ```bash
   kubectl get pods -n cloudflared-vpc
   ```

## Adding a database (reusable pattern — no cluster changes needed)

For any CNPG database in the cluster (`<db>` = database name, `<ns>` = namespace,
targeting the primary `-rw` service — never the PgBouncer pooler, since Hyperdrive
is itself a pooler):

```bash
# 1. Create a VPC Service pointing the shared tunnel at the DB's primary service.
#    --hostname resolves from inside the cluster (this connector uses cluster DNS).
npx wrangler vpc service create <db> \
  --type tcp \
  --tcp-port 5432 \
  --app-protocol postgresql \
  --tunnel-id <HLKUBE_VPC_TUNNEL_ID> \
  --hostname <db>-rw.<ns>.svc.cluster.local
# (If DNS resolution ever fails, use the ClusterIP instead: --ipv4 <clusterip>)
# Note the returned VPC Service ID.

# 2. Create the Hyperdrive config referencing that VPC Service.
#    CNPG serves a self-signed cert, so relax verification (still TLS-encrypted).
npx wrangler hyperdrive create <db> \
  --service-id <VPC_SERVICE_ID> \
  --database <db> \
  --user <db> \
  --password '<password>' \
  --scheme postgresql \
  --cert-verification-mode disabled
# For stricter security use `--cert-verification-mode verify_ca` with the CNPG CA
# (kubectl get secret <db>-ca -n <ns> -o jsonpath='{.data.ca\.crt}' | base64 -d).

# 3. Bind it in the Worker's wrangler.toml:
#    [[hyperdrive]]
#    binding = "HYPERDRIVE"
#    id = "<hyperdrive-config-id>"
#    -> at runtime: env.HYPERDRIVE.connectionString
```

## Requirements

- The **Connectivity Directory Admin** role on the Cloudflare account (to create
  VPC Services).
- Wrangler v3.65+ (`npx wrangler`).
