# Chatwoot

Self-hosted Chatwoot deployed with CloudNativePG, Valkey, Longhorn storage, and Traefik.

## Deployment State

This directory is intentionally not referenced by `apps/third-party/kustomization.yaml` until the sealed secrets exist.

## Secret Setup

Populate these gitignored files first:

- `postgres-credentials.secret`
- `valkey-auth.secret`
- `chatwoot-secrets.secret`

Then seal them from the repository root:

```bash
./seal-secrets.sh
```

After sealing, add `chatwoot` to `apps/third-party/kustomization.yaml` and commit only the generated `.sealed.yaml` files plus the manifests.

## Initial Account Setup

`ENABLE_ACCOUNT_SIGNUP` is initially set to `"true"` in `configmap.yaml` so the first admin account can be created. After setup, set it to `"false"` and commit that follow-up change.

`ENABLE_PUSH_RELAY_SERVER` is set to `"true"` for the official Chatwoot mobile apps. Do not add Firebase project credentials unless switching to custom-built mobile apps.
